# 从 GitHub Releases 查询、下载并校验 Windows 安装包。不读取 debug/ 目录。

if ([string]::IsNullOrWhiteSpace($env:HCLOUD_RELEASE_DOWNLOAD_BASE)) {
    $script:HcloudReleaseBase = 'https://github.com/Lance52259/hcloud-cli-storage/releases'
} else {
    $script:HcloudReleaseBase = $env:HCLOUD_RELEASE_DOWNLOAD_BASE.TrimEnd('/')
}

$script:HcloudAssetName = 'huaweicloud-cli-windows-amd64.zip'
$script:HcloudUserAgent = 'hcloud-setup'

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[Net.ServicePointManager]::Expect100Continue = $false

function Get-HcloudSetupLogPath {
    return (Join-Path $env:TEMP 'hcloud-setup.log')
}

function Write-HcloudLogFile {
    param(
        [string]$Message,
        [string]$Path
    )
    if ([string]::IsNullOrWhiteSpace($Message)) {
        return
    }
    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = Get-HcloudSetupLogPath
    }
    $text = $Message.Replace("`r", ' ').Replace("`n", ' | ')
    $line = '{0:yyyy-MM-dd HH:mm:ss.fff} {1}{2}' -f (Get-Date), $text, [Environment]::NewLine
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($line)
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        try {
            if (-not (Test-Path -LiteralPath $Path)) {
                [System.IO.File]::WriteAllText($Path, '', (New-Object System.Text.UTF8Encoding $true))
            }
            $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
            try {
                $stream.Write($bytes, 0, $bytes.Length)
                $stream.Flush()
            } finally {
                $stream.Dispose()
            }
            return
        } catch {
            Start-Sleep -Milliseconds 40
        }
    }
}

function Format-HcloudError {
    param($ErrorRecord)
    $parts = New-Object System.Collections.Generic.List[string]
    $exception = $null
    if ($ErrorRecord -and $ErrorRecord.Exception) {
        $exception = $ErrorRecord.Exception
    } elseif ($ErrorRecord -is [System.Exception]) {
        $exception = $ErrorRecord
    }
    $depth = 0
    while ($exception -and $depth -lt 6) {
        $parts.Add(('{0}: {1}' -f $exception.GetType().FullName, $exception.Message))
        $web = $exception -as [System.Net.WebException]
        if ($web) {
            $parts.Add(('WebException.Status={0}' -f $web.Status))
            if ($web.Response) {
                try { $parts.Add(('HTTP {0}' -f [int]$web.Response.StatusCode)) } catch { }
                try { $parts.Add(('ResponseUri={0}' -f $web.Response.ResponseUri)) } catch { }
            }
        }
        $exception = $exception.InnerException
        $depth++
    }
    if ($parts.Count -eq 0 -and $ErrorRecord) {
        $parts.Add([string]$ErrorRecord)
    }
    return ($parts -join ' | ')
}

function New-HcloudWebRequest {
    param(
        [string]$Url,
        [string]$Method = 'GET',
        [int]$Timeout = 20000
    )
    $request = [System.Net.HttpWebRequest]::Create($Url)
    $request.Method = $Method
    $request.UserAgent = $script:HcloudUserAgent
    $request.AllowAutoRedirect = $true
    $request.KeepAlive = $false
    $request.ProtocolVersion = [Version]'1.1'
    $request.ConnectionGroupName = [guid]::NewGuid().ToString('N')
    $request.Timeout = $Timeout
    $request.ReadWriteTimeout = $Timeout
    return $request
}

function Test-HcloudVersionTag {
    param([string]$Version)
    return $Version -match '^[A-Za-z0-9._+-]+$'
}

function Get-HcloudAssetUrl {
    param([Parameter(Mandatory = $true)][string]$Version)
    if (-not (Test-HcloudVersionTag $Version) -and $Version -ne 'latest') {
        throw "版本号无效：$Version"
    }
    $base = $script:HcloudReleaseBase.TrimEnd('/')
    if ($Version -eq 'latest') {
        return "$base/latest/download/$script:HcloudAssetName"
    }
    return "$base/download/$Version/$script:HcloudAssetName"
}

function Get-HcloudSumsUrl {
    param([Parameter(Mandatory = $true)][string]$Version)
    $assetUrl = Get-HcloudAssetUrl -Version $Version
    $suffix = '/' + $script:HcloudAssetName
    if (-not $assetUrl.EndsWith($suffix)) {
        throw "无法得到 SHA256SUMS 地址：$assetUrl"
    }
    return $assetUrl.Substring(0, $assetUrl.Length - $script:HcloudAssetName.Length) + 'SHA256SUMS'
}

function Get-HcloudLatestApiUrl {
    $base = $script:HcloudReleaseBase.TrimEnd('/')
    if ($base -match '^https://github\.com/([^/]+)/([^/]+)/releases$') {
        return "https://api.github.com/repos/$($Matches[1])/$($Matches[2])/releases/latest"
    }
    throw "无法根据下载地址确定 GitHub API：$base"
}

function Get-LatestHcloudReleaseTag {
    $request = New-HcloudWebRequest -Url (Get-HcloudLatestApiUrl) -Timeout 20000
    $request.Accept = 'application/vnd.github+json'
    try {
        $response = $request.GetResponse()
    } catch [System.Net.WebException] {
        throw "无法查询最新版本。$($_.Exception.Message)"
    }
    try {
        $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
        $body = $reader.ReadToEnd()
    } finally {
        $response.Close()
    }
    $tag = [string](($body | ConvertFrom-Json).tag_name)
    if (-not (Test-HcloudVersionTag $tag)) {
        throw "最新版本标签无效：$tag"
    }
    return $tag
}

function Test-HcloudUrlExists {
    param([string]$Url)
    foreach ($method in @('HEAD', 'GET')) {
        $request = New-HcloudWebRequest -Url $Url -Method $method -Timeout 20000
        if ($method -eq 'GET') {
            $request.AddRange(0, 0)
        }
        try {
            $response = $request.GetResponse()
            $code = [int]$response.StatusCode
            $response.Close()
            return ($code -ge 200 -and $code -lt 400)
        } catch [System.Net.WebException] {
            $webResponse = $_.Exception.Response
            if ($webResponse) {
                $code = [int]$webResponse.StatusCode
                $webResponse.Close()
                if ($code -eq 404) {
                    return $false
                }
                if ($method -eq 'HEAD' -and ($code -eq 403 -or $code -eq 405 -or $code -eq 501)) {
                    continue
                }
            }
            if ($method -eq 'GET') {
                throw "无法检查安装包是否存在。$($_.Exception.Message)"
            }
        }
    }
    return $false
}

function Test-HcloudReleaseAsset {
    param([Parameter(Mandatory = $true)][string]$Version)
    return (Test-HcloudUrlExists -Url (Get-HcloudAssetUrl -Version $Version))
}

function Test-HcloudErrorIsNotFound {
    param($ErrorRecord)
    $parts = New-Object System.Collections.Generic.List[string]
    if ($ErrorRecord) {
        $parts.Add([string]$ErrorRecord)
    }
    $exception = $null
    if ($ErrorRecord -and $ErrorRecord.Exception) {
        $exception = $ErrorRecord.Exception
    } elseif ($ErrorRecord -is [System.Exception]) {
        $exception = $ErrorRecord
    }
    while ($exception) {
        $parts.Add([string]$exception.Message)
        $web = $exception -as [System.Net.WebException]
        if ($web -and $web.Response) {
            try {
                $parts.Add([string][int]$web.Response.StatusCode)
            } catch { }
            try { $web.Response.Close() } catch { }
        }
        $exception = $exception.InnerException
    }
    $text = $parts -join ' '
    return $text -match '404|Not Found|未找到|找不到|不存在'
}

function Test-HcloudSumsFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }
    foreach ($line in @(Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue)) {
        if ($line -match '^\s*[0-9a-fA-F]{64}\s+\S+') {
            return $true
        }
    }
    return $false
}

function Receive-HcloudFile {
    param(
        [string]$Url,
        [string]$Destination,
        $Progress,
        [int]$PercentStart = 10,
        [int]$PercentEnd = 50,
        [int]$Timeout = 300000
    )
    $partial = $Destination + '.partial'
    $logPath = ''
    if ($Progress -and $Progress.LogFile) {
        $logPath = [string]$Progress.LogFile
    }
    Write-HcloudLogFile -Path $logPath -Message ("开始下载 {0}，超时 {1} 毫秒，保存到 {2}" -f $Url, $Timeout, $Destination)
    $request = New-HcloudWebRequest -Url $Url -Timeout $Timeout
    try {
        $response = $request.GetResponse()
    } catch [System.Net.WebException] {
        Write-HcloudLogFile -Path $logPath -Message ("下载失败 {0}。{1}" -f $Url, (Format-HcloudError $_))
        if (Test-Path -LiteralPath $partial) {
            Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
        }
        if (Test-HcloudErrorIsNotFound $_) {
            throw "文件不存在（404）：$Url"
        }
        throw "下载失败：$Url。$($_.Exception.Message)"
    }

    try {
        $total = $response.ContentLength
        Write-HcloudLogFile -Path $logPath -Message ("已连接 {0}，HTTP {1}，长度 {2}" -f $response.ResponseUri, [int]$response.StatusCode, $total)
        $stream = $response.GetResponseStream()
        $file = [System.IO.File]::Create($partial)
        try {
            $buffer = New-Object byte[] 81920
            $received = [int64]0
            while (($count = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $file.Write($buffer, 0, $count)
                $received += $count
                if ($Progress -and $total -gt 0) {
                    $span = $PercentEnd - $PercentStart
                    $percent = $PercentStart + [int](($span * $received) / $total)
                    if ($percent -gt $PercentEnd) {
                        $percent = $PercentEnd
                    }
                    $Progress.Percent = $percent
                    $Progress.Detail = "已下载 $received / $total 字节"
                }
            }
        } finally {
            $file.Dispose()
        }
    } catch {
        Write-HcloudLogFile -Path $logPath -Message ("读取下载内容失败 {0}。{1}" -f $Url, (Format-HcloudError $_))
        if (Test-Path -LiteralPath $partial) {
            Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
        }
        throw "下载失败：$Url。$($_.Exception.Message)"
    } finally {
        $response.Close()
    }
    $saved = (Get-Item -LiteralPath $partial).Length
    Write-HcloudLogFile -Path $logPath -Message ("下载完成 {0}，{1} 字节" -f $Destination, $saved)

    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Force
    }
    Move-Item -LiteralPath $partial -Destination $Destination
}

function Test-HcloudSha256 {
    param(
        [string]$File,
        [string]$SumsFile,
        [string]$AssetName
    )
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $File).Hash.ToLowerInvariant()
    $found = $false
    foreach ($line in @(Get-Content -LiteralPath $SumsFile)) {
        if ($line -match '^\s*([0-9a-fA-F]{64})\s+\*?(.+?)\s*$') {
            $name = Split-Path -Leaf ($Matches[2].Trim())
            if ($name -eq $AssetName) {
                $found = $true
                $expected = $Matches[1].ToLowerInvariant()
                if ($expected -ne $actual) {
                    throw "校验失败：安装包的 SHA256 与 SHA256SUMS 不一致。"
                }
            }
        }
    }
    if (-not $found) {
        throw "SHA256SUMS 中没有 $AssetName。"
    }
}

function Expand-HcloudZip {
    param([string]$ZipPath, [string]$Destination)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Recurse -Force
    }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null

    $archive = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        foreach ($entry in $archive.Entries) {
            $name = $entry.FullName.Replace('/', '\')
            if ($name.StartsWith('\') -or $name.Contains('..\') -or [System.IO.Path]::IsPathRooted($name)) {
                throw "压缩包包含不安全路径：$($entry.FullName)"
            }
        }
    } finally {
        $archive.Dispose()
    }

    [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $Destination)
    $executable = Get-ChildItem -LiteralPath $Destination -Filter 'hcloud.exe' -Recurse -File |
        Sort-Object { ($_.FullName -split '\\').Count } |
        Select-Object -First 1
    if (-not $executable) {
        throw '压缩包中没有找到 hcloud.exe。'
    }
    return $executable.FullName
}
