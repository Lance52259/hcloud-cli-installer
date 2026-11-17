# 提权后的短进程。只复制程序、修改系统 PATH 和系统安装记录。
param(
    [Parameter(Mandatory = $true)]
    [string]$JobFile
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
. (Join-Path $PSScriptRoot 'PathRegistry.ps1')

function Write-HcloudElevatedFailure {
    param([string]$ResultFile, [string]$Message)
    if (-not [string]::IsNullOrWhiteSpace($ResultFile)) {
        [System.IO.File]::WriteAllText($ResultFile, $Message, (New-Object System.Text.UTF8Encoding $false))
    }
}

$resultFile = ''
try {
    $jobText = [System.IO.File]::ReadAllText($JobFile, (New-Object System.Text.UTF8Encoding $false))
    $job = $jobText | ConvertFrom-Json
    $resultFile = [string]$job.ResultFile
    if ($job.Action -eq 'install') {
        $destination = Join-Path ([string]$job.InstallDir) 'hcloud.exe'
        if ($job.CopyFile) {
            Copy-HcloudExecutable -Source ([string]$job.SourceExe) -Destination $destination
        }
        if ($job.UpdateMachinePath) {
            [void](Add-HcloudPathEntry -Scope 'Machine' -Directory ([string]$job.InstallDir))
        }
        if ($job.UpdateMachineRecord) {
            Set-HcloudInstallRecord -Hive 'LocalMachine' `
                -InstallDir ([string]$job.InstallDir) `
                -ExecutablePath $destination `
                -ReleaseTag ([string]$job.ReleaseTag) `
                -PathScope 'Machine'
        }
    } elseif ($job.Action -eq 'uninstall') {
        if ($job.RemoveMachinePath) {
            [void](Remove-HcloudPathEntry -Scope 'Machine' -Directory ([string]$job.InstallDir))
        }
        if ($job.DeleteProgram) {
            Remove-HcloudProgramFile -Path ([string]$job.ExecutablePath)
        }
        if ($job.RemoveMachineRecord) {
            Remove-HcloudInstallRecord -Hive 'LocalMachine'
        }
    } else {
        throw "未知的提权操作：$($job.Action)"
    }
    exit 0
} catch {
    Write-HcloudElevatedFailure -ResultFile $resultFile -Message $_.Exception.Message
    exit 1
}
