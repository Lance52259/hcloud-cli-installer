# 旧的在线安装向导。发布的 Windows 安装器不再启动本脚本。
# 发布的 exe 由 installer/windows/build.sh 生成，并内嵌 scripts/setup.ps1。
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
