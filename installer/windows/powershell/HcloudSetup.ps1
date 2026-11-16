# 华为云命令行工具的 Windows 图形安装器。
# 安装器不包含 CLI 本体，进度步骤从 GitHub Releases 下载。
#
# 在 Windows PowerShell 中运行：
#   powershell -NoProfile -ExecutionPolicy Bypass -STA -File installer\windows\powershell\HcloudSetup.ps1
# 发布出的 huaweicloud-cli-setup-windows-amd64.exe 用同样的参数启动本脚本。
#Requires -Version 5.1

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

try {
    if (-not ('HcloudSetupConsole.Native' -as [type])) {
        Add-Type -Namespace HcloudSetupConsole -Name Native -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("kernel32.dll")]
public static extern System.IntPtr GetConsoleWindow();
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);
'@
    }
    $consoleWindow = [HcloudSetupConsole.Native]::GetConsoleWindow()
    if ($consoleWindow -ne [IntPtr]::Zero) {
        [HcloudSetupConsole.Native]::ShowWindow($consoleWindow, 0) | Out-Null
    }
} catch {
}

if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arguments = "-NoProfile -STA -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    Start-Process -FilePath $powershell -ArgumentList $arguments | Out-Null
    exit 0
}

$script:InstallerRoot = $PSScriptRoot
. (Join-Path $PSScriptRoot 'actions\PathRegistry.ps1')
. (Join-Path $PSScriptRoot 'actions\ReleaseClient.ps1')
. (Join-Path $PSScriptRoot 'actions\SetupActions.ps1')
. (Join-Path $PSScriptRoot 'detect\Find-Hcloud.ps1')
. (Join-Path $PSScriptRoot 'ui\Show-SetupWizard.ps1')

Show-SetupWizard
