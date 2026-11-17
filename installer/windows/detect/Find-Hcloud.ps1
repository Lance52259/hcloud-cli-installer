# 探测本机 hcloud.exe。顺序：安装记录、默认目录、PATH。

function ConvertTo-HcloudVersionNumber {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }
    $match = [regex]::Match($Text, '\d+\.\d+\.\d+')
    if (-not $match.Success) {
        return $null
    }
    return $match.Value
}

function Get-HcloudEmbeddedVersion {
    param([string]$Executable)
    if ([string]::IsNullOrWhiteSpace($Executable) -or -not (Test-Path -LiteralPath $Executable)) {
        return $null
    }
    $stream = $null
    try {
        $stream = [System.IO.File]::Open(
            $Executable,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::ReadWrite)
        $length = $stream.Length
        $count = 8388608
        if ($count -gt $length) {
            $count = [int]$length
        }
        $stream.Position = $length - $count
        $bytes = New-Object byte[] $count
        $got = 0
        while ($got -lt $count) {
            $read = $stream.Read($bytes, $got, $count - $got)
            if ($read -le 0) {
                break
            }
            $got += $read
        }
        $text = [System.Text.Encoding]::ASCII.GetString($bytes, 0, $got)
        $match = [regex]::Match($text, 'util\.CliVersion=(\d+\.\d+\.\d+)')
        if ($match.Success) {
            return $match.Groups[1].Value
        }
    } catch {
        return $null
    } finally {
        if ($stream) {
            $stream.Dispose()
        }
    }
    return $null
}

function Get-HcloudCliVersion {
    param([string]$Executable)
    if ([string]::IsNullOrWhiteSpace($Executable) -or -not (Test-Path -LiteralPath $Executable)) {
        return $null
    }
    $embedded = Get-HcloudEmbeddedVersion -Executable $Executable
    if (-not [string]::IsNullOrWhiteSpace($embedded)) {
        return $embedded
    }
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $Executable
    $info.Arguments = 'version'
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.CreateNoWindow = $true
    try {
        $utf8 = New-Object System.Text.UTF8Encoding $false
        $info.StandardOutputEncoding = $utf8
        $info.StandardErrorEncoding = $utf8
    } catch { }
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $info
    try {
        [void]$process.Start()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(8000)) {
            try { $process.Kill() } catch { }
        }
        [void]$process.WaitForExit()
        $text = [string]$stdoutTask.Result
        if ([string]::IsNullOrWhiteSpace($text)) {
            $text = [string]$stderrTask.Result
        }
        if ([string]::IsNullOrWhiteSpace($text)) {
            return $null
        }
        return (ConvertTo-HcloudVersionNumber $text)
    } catch {
        return $null
    } finally {
        $process.Dispose()
    }
}

function Find-HcloudOnPath {
    $where = Join-Path $env:SystemRoot 'System32\where.exe'
    if (-not (Test-Path -LiteralPath $where)) {
        return @()
    }
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $where
    $info.Arguments = 'hcloud'
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.CreateNoWindow = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $info
    [void]$process.Start()
    $stdout = $process.StandardOutput.ReadToEnd()
    [void]$process.StandardError.ReadToEnd()
    [void]$process.WaitForExit()
    if ($process.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($stdout)) {
        return @()
    }
    $output = @($stdout -split '\r?\n')
    $found = New-Object System.Collections.Generic.List[string]
    foreach ($line in $output) {
        $candidate = ([string]$line).Trim()
        if ([string]::IsNullOrWhiteSpace($candidate) -or -not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            continue
        }
        $name = [System.IO.Path]::GetFileName($candidate)
        if ($name -ine 'hcloud.exe' -and $name -ine 'hcloud') {
            continue
        }
        $found.Add((Resolve-Path -LiteralPath $candidate).Path)
    }
    return @($found.ToArray())
}

function New-HcloudCandidate {
    param(
        [string]$ExecutablePath,
        [string]$InstallDir,
        [string]$ReleaseTag,
        [string]$PathScope,
        [string]$Source,
        $Record,
        [int]$Priority
    )
    return [pscustomobject]@{
        ExecutablePath = $ExecutablePath
        InstallDir     = $InstallDir
        ReleaseTag     = $ReleaseTag
        PathScope      = $PathScope
        Source         = $Source
        Record         = $Record
        Priority       = $Priority
    }
}

function Find-HcloudInstallation {
    $candidates = New-Object System.Collections.Generic.List[object]
    $priority = 0
    foreach ($hive in @('CurrentUser', 'LocalMachine')) {
        try {
            $record = Get-HcloudInstallRecord -Hive $hive
        } catch {
            $priority++
            continue
        }
        $priority++
        if (-not $record -or [string]::IsNullOrWhiteSpace($record.ExecutablePath)) {
            continue
        }
        if (-not (Test-Path -LiteralPath $record.ExecutablePath -PathType Leaf)) {
            continue
        }
        $installDir = $record.InstallDir
        if ([string]::IsNullOrWhiteSpace($installDir)) {
            $installDir = Split-Path -Parent $record.ExecutablePath
        }
        $candidates.Add((New-HcloudCandidate `
            -ExecutablePath (Resolve-Path -LiteralPath $record.ExecutablePath).Path `
            -InstallDir $installDir `
            -ReleaseTag $record.ReleaseTag `
            -PathScope $record.PathScope `
            -Source 'record' `
            -Record $record `
            -Priority $priority))
    }

    $defaults = @(
        (Join-Path $env:LOCALAPPDATA 'hcloud\hcloud.exe'),
        (Join-Path $env:USERPROFILE 'hcloud\hcloud.exe')
    )
    foreach ($path in $defaults) {
        $priority++
        if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {
            continue
        }
        $candidates.Add((New-HcloudCandidate `
            -ExecutablePath (Resolve-Path -LiteralPath $path).Path `
            -InstallDir (Split-Path -Parent $path) `
            -ReleaseTag '' `
            -PathScope '' `
            -Source 'default' `
            -Record $null `
            -Priority $priority))
    }

    # 安装记录和默认目录优先于 PATH。已经找到时不再启动 where.exe。
    if ($candidates.Count -eq 0) {
        foreach ($path in @(Find-HcloudOnPath)) {
            $priority++
            if ([string]::IsNullOrWhiteSpace($path)) {
                continue
            }
            $candidates.Add((New-HcloudCandidate `
                -ExecutablePath $path `
                -InstallDir (Split-Path -Parent $path) `
                -ReleaseTag '' `
                -PathScope '' `
                -Source 'path' `
                -Record $null `
                -Priority $priority))
        }
    }

    $selected = $null
    if ($candidates.Count -gt 0) {
        $selected = $candidates | Sort-Object Priority | Select-Object -First 1
    }

    if (-not $selected) {
        return [pscustomobject]@{
            Found          = $false
            ExecutablePath = ''
            InstallDir     = ''
            Version        = $null
            ReleaseTag     = ''
            PathScope      = ''
            Source         = ''
            Record         = $null
        }
    }

    return [pscustomobject]@{
        Found          = $true
        ExecutablePath = $selected.ExecutablePath
        InstallDir     = $selected.InstallDir
        Version        = (Get-HcloudEmbeddedVersion -Executable $selected.ExecutablePath)
        ReleaseTag     = $selected.ReleaseTag
        PathScope      = $selected.PathScope
        Source         = $selected.Source
        Record         = $selected.Record
    }
}
