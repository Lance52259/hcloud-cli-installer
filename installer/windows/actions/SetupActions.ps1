# 安装、更新和卸载。下载留在当前用户进程，受保护位置交给提权短进程。

function Write-HcloudProgress {
    param($Progress, [string]$Step, [int]$Percent, [string]$Detail)
    $lockTaken = $false
    $line = $Step
    $logFile = ''
    [System.Threading.Monitor]::Enter($Progress.Lock, [ref]$lockTaken)
    try {
        $Progress.Step = $Step
        $Progress.Percent = $Percent
        if (-not [string]::IsNullOrWhiteSpace($Detail)) {
            $Progress.Detail = $Detail
            $line = $Detail
            $Progress.Log = [string]$Progress.Log + $Detail + "`r`n"
        } else {
            $line = $Step
            $Progress.Log = [string]$Progress.Log + $Step + "`r`n"
        }
        $logFile = [string]$Progress.LogFile
    } finally {
        if ($lockTaken) {
            [System.Threading.Monitor]::Exit($Progress.Lock)
        }
    }
    Write-HcloudLogFile -Path $logFile -Message ("[{0}] {1}" -f $Step, $line)
}

function Invoke-HcloudElevatedJob {
    param($Job)
    $id = [guid]::NewGuid().ToString('n')
    $jobFile = Join-Path $env:TEMP "hcloud-elevated-$id.json"
    $resultFile = Join-Path $env:TEMP "hcloud-elevated-$id.txt"
    $Job.ResultFile = $resultFile
    $json = $Job | ConvertTo-Json -Compress
    [System.IO.File]::WriteAllText($jobFile, $json, (New-Object System.Text.UTF8Encoding $false))
    $script = Join-Path $script:InstallerRoot 'actions\Invoke-Elevated.ps1'
    $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$script`" -JobFile `"$jobFile`""
    try {
        $process = Start-Process -FilePath $powershell -Verb RunAs -Wait -PassThru -ArgumentList $arguments
    } catch {
        throw "用户拒绝了授权。已下载的文件会保留，可以重试。$($_.Exception.Message)"
    }
    if (-not $process -or $process.ExitCode -ne 0) {
        $reason = "提权操作失败（退出码 $($process.ExitCode)）。"
        if (Test-Path -LiteralPath $resultFile) {
            $written = [System.IO.File]::ReadAllText($resultFile).Trim()
            if (-not [string]::IsNullOrWhiteSpace($written)) {
                $reason = $written
            }
        }
        throw $reason
    }
}

function Invoke-HcloudInstallAction {
    param($Request, $Progress)
    $work = [string]$Request.WorkRoot
    if (-not (Test-Path -LiteralPath $work)) {
        New-Item -ItemType Directory -Path $work -Force | Out-Null
    }
    $zip = Join-Path $work $script:HcloudAssetName
    $sums = Join-Path $work 'SHA256SUMS'
    $extract = Join-Path $work 'extract'
    $marker = Join-Path $work 'version.txt'
    $version = [string]$Request.Version
    $installDir = Get-HcloudFullPath ([string]$Request.InstallDir)
    $destination = Join-Path $installDir 'hcloud.exe'
    $scope = [string]$Request.PathScope

    Write-HcloudProgress -Progress $Progress -Step '确定下载地址' -Percent 5
    $url = Get-HcloudAssetUrl -Version $version
    Write-HcloudProgress -Progress $Progress -Step '确定下载地址' -Percent 8 -Detail $url

    $savedVersion = ''
    if (Test-Path -LiteralPath $marker) {
        $savedVersion = [System.IO.File]::ReadAllText($marker).Trim()
    }
    if ((Test-Path -LiteralPath $zip) -and $savedVersion -eq $version) {
        Write-HcloudProgress -Progress $Progress -Step '下载安装包' -Percent 40 -Detail '使用上次已下载的安装包。'
    } else {
        if (Test-Path -LiteralPath $zip) {
            Remove-Item -LiteralPath $zip -Force
        }
        Write-HcloudProgress -Progress $Progress -Step '下载安装包' -Percent 10 -Detail '正在下载安装包。'
        Receive-HcloudFile -Url $url -Destination $zip -Progress $Progress -PercentStart 10 -PercentEnd 50
        [System.IO.File]::WriteAllText($marker, $version, (New-Object System.Text.UTF8Encoding $false))
    }

    Write-HcloudProgress -Progress $Progress -Step '校验安装包' -Percent 55 -Detail '正在检查 SHA256SUMS。'
    $sumsUrl = Get-HcloudSumsUrl -Version $version
    Write-HcloudLogFile -Path ([string]$Progress.LogFile) -Message ("校验文件地址 {0}" -f $sumsUrl)
    $sumsReady = $false
    try {
        Receive-HcloudFile -Url $sumsUrl -Destination $sums -Timeout 20000 -Progress $Progress
        if (Test-HcloudSumsFile -Path $sums) {
            $sumsReady = $true
            Write-HcloudLogFile -Path ([string]$Progress.LogFile) -Message 'SHA256SUMS 已下载，开始比对哈希。'
        } else {
            Write-HcloudLogFile -Path ([string]$Progress.LogFile) -Message '下载到的内容不是 SHA256SUMS，将跳过校验。'
        }
    } catch {
        Write-HcloudLogFile -Path ([string]$Progress.LogFile) -Message ("SHA256SUMS 未取得，将跳过校验。{0}" -f (Format-HcloudError $_))
        $sumsReady = $false
    }
    if (-not $sumsReady) {
        $Progress.Note = '未取得 SHA256SUMS，已跳过校验。'
        Write-HcloudProgress -Progress $Progress -Step '校验安装包' -Percent 68 -Detail $Progress.Note
    } else {
        try {
            Test-HcloudSha256 -File $zip -SumsFile $sums -AssetName $script:HcloudAssetName
        } catch {
            Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
            throw
        }
        $Progress.Note = '已根据 SHA256SUMS 校验安装包。'
        Write-HcloudProgress -Progress $Progress -Step '校验安装包' -Percent 68 -Detail $Progress.Note
    }

    Write-HcloudProgress -Progress $Progress -Step '解压安装包' -Percent 74 -Detail '正在解压并取出 hcloud.exe。'
    $source = Expand-HcloudZip -ZipPath $zip -Destination $extract

    $copyNeedsElevation = (Test-HcloudProtectedDirectory $installDir) -or -not (Test-HcloudDirectoryWritable $installDir)
    $machineScope = ($scope -eq 'Machine')
    if ($copyNeedsElevation -or $machineScope) {
        Write-HcloudProgress -Progress $Progress -Step '请求授权' -Percent 82 -Detail '正在请求授权。向导会保持打开。'
        Invoke-HcloudElevatedJob @{
            Action              = 'install'
            SourceExe           = $source
            InstallDir          = $installDir
            ReleaseTag          = $version
            CopyFile            = [bool]$copyNeedsElevation
            UpdateMachinePath   = [bool]$machineScope
            UpdateMachineRecord = [bool]$machineScope
        }
        if (-not $copyNeedsElevation) {
            Write-HcloudProgress -Progress $Progress -Step '复制程序' -Percent 86 -Detail '正在复制 hcloud.exe。'
            Copy-HcloudExecutable -Source $source -Destination $destination
        } else {
            Write-HcloudProgress -Progress $Progress -Step '复制程序' -Percent 88 -Detail '已复制 hcloud.exe。'
        }
    } else {
        Write-HcloudProgress -Progress $Progress -Step '复制程序' -Percent 86 -Detail '正在复制 hcloud.exe。'
        Copy-HcloudExecutable -Source $source -Destination $destination
    }

    if ($machineScope) {
        Write-HcloudProgress -Progress $Progress -Step '写入 PATH' -Percent 92 -Detail '已写入系统 PATH。'
    } else {
        Write-HcloudProgress -Progress $Progress -Step '写入 PATH' -Percent 92 -Detail '正在写入当前用户 PATH。'
        [void](Add-HcloudPathEntry -Scope 'User' -Directory $installDir)
    }

    Write-HcloudProgress -Progress $Progress -Step '写入安装记录' -Percent 97 -Detail '正在写入当前用户安装记录。'
    Set-HcloudInstallRecord -Hive 'CurrentUser' -InstallDir $installDir -ExecutablePath $destination `
        -ReleaseTag $version -PathScope $(if ($machineScope) { 'Machine' } else { 'User' })

    $Progress.ResultPath = $destination
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    $Progress.KeptArchive = ''
}

function Invoke-HcloudUninstallAction {
    param($Request, $Progress)
    $installDir = [string]$Request.InstallDir
    $executable = [string]$Request.ExecutablePath
    $scope = [string]$Request.PathScope
    $removeMachinePath = $false
    $removeMachineRecord = $false
    $deleteInElevated = $false

    if ($scope -eq 'Machine') {
        $removeMachinePath = $true
        $removeMachineRecord = $true
        $deleteInElevated = $true
    } elseif ([string]::IsNullOrWhiteSpace($scope)) {
        $removeMachinePath = Test-HcloudPathEntry -Scope 'Machine' -Directory $installDir
        $removeMachineRecord = $null -ne (Get-HcloudInstallRecord -Hive 'LocalMachine')
        $deleteInElevated = (Test-HcloudProtectedDirectory (Split-Path -Parent $executable)) -or $removeMachinePath
    } else {
        $parent = Split-Path -Parent $executable
        $deleteInElevated = Test-HcloudProtectedDirectory $parent
    }

    if ($deleteInElevated -or $removeMachinePath -or $removeMachineRecord) {
        Write-HcloudProgress -Progress $Progress -Step '请求授权' -Percent 20 -Detail '正在请求授权。向导会保持打开。'
        Invoke-HcloudElevatedJob @{
            Action              = 'uninstall'
            InstallDir          = $installDir
            ExecutablePath      = $executable
            RemoveMachinePath   = [bool]$removeMachinePath
            DeleteProgram       = [bool]$deleteInElevated
            RemoveMachineRecord = [bool]$removeMachineRecord
        }
    }

    Write-HcloudProgress -Progress $Progress -Step '从 PATH 删除目录' -Percent 55
    if ($scope -ne 'Machine') {
        [void](Remove-HcloudPathEntry -Scope 'User' -Directory $installDir)
        Write-HcloudProgress -Progress $Progress -Step '从 PATH 删除目录' -Percent 60 -Detail '已检查当前用户 PATH。'
    } else {
        Write-HcloudProgress -Progress $Progress -Step '从 PATH 删除目录' -Percent 60 -Detail '已检查系统 PATH。'
    }

    Write-HcloudProgress -Progress $Progress -Step '删除程序' -Percent 75
    if (-not $deleteInElevated) {
        Remove-HcloudProgramFile -Path $executable
    }

    Write-HcloudProgress -Progress $Progress -Step '删除安装记录' -Percent 88 -Detail '正在删除当前用户安装记录。'
    Remove-HcloudInstallRecord -Hive 'CurrentUser'

    if ($Request.RemoveConfig) {
        Write-HcloudProgress -Progress $Progress -Step '删除用户配置' -Percent 95 -Detail '正在删除 .hcloud。'
        $config = Join-Path $env:USERPROFILE '.hcloud'
        if (Test-Path -LiteralPath $config) {
            $item = Get-Item -LiteralPath $config -Force
            if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                throw '用户配置目录是链接，已停止删除。'
            }
            Remove-Item -LiteralPath $config -Recurse -Force
        }
    }

    $Progress.ResultPath = $executable
}

function Invoke-HcloudSetupAction {
    param($Request, $Progress)
    if ([string]::IsNullOrWhiteSpace([string]$Progress.LogFile)) {
        $Progress.LogFile = Get-HcloudSetupLogPath
    }
    Write-HcloudLogFile -Path ([string]$Progress.LogFile) -Message ("---- 开始 {0}，版本 {1}，目录 {2}，日志 {3}" -f $Request.Operation, $Request.Version, $Request.InstallDir, $Progress.LogFile)
    try {
        if ([string]$Request.Operation -eq 'Uninstall') {
            Invoke-HcloudUninstallAction -Request $Request -Progress $Progress
        } else {
            Invoke-HcloudInstallAction -Request $Request -Progress $Progress
        }
        $Progress.Ok = $true
        $Progress.Percent = 100
        Write-HcloudProgress -Progress $Progress -Step '完成' -Percent 100 -Detail '操作已完成。'
    } catch {
        $lockTaken = $false
        [System.Threading.Monitor]::Enter($Progress.Lock, [ref]$lockTaken)
        try {
            if ([string]::IsNullOrWhiteSpace([string]$Progress.Step)) {
                $Progress.Step = '准备'
            }
            $Progress.ErrorStep = [string]$Progress.Step
            $Progress.ErrorMessage = $_.Exception.Message
            $Progress.Ok = $false
            $zip = Join-Path ([string]$Request.WorkRoot) $script:HcloudAssetName
            if (Test-Path -LiteralPath $zip) {
                $Progress.KeptArchive = $zip
            } else {
                $Progress.KeptArchive = ''
            }
        } finally {
            if ($lockTaken) {
                [System.Threading.Monitor]::Exit($Progress.Lock)
            }
        }
        Write-HcloudLogFile -Path ([string]$Progress.LogFile) -Message ("失败步骤：{0}。{1}" -f $Progress.ErrorStep, (Format-HcloudError $_))
    } finally {
        $Progress.Done = $true
    }
}
