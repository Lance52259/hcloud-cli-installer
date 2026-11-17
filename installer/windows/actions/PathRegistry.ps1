# 安装目录、PATH 和安装记录。当前用户记录在 HKCU，所有用户记录在 HKLM。

$script:HcloudRegistryPath = 'Software\HuaweiCloud\hcloud'

function ConvertTo-HcloudComparablePath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ''
    }
    return $Path.Trim().TrimEnd('\').ToLowerInvariant()
}

function Test-HcloudSameDirectory {
    param([string]$Left, [string]$Right)
    return (ConvertTo-HcloudComparablePath $Left) -eq (ConvertTo-HcloudComparablePath $Right)
}

function Get-HcloudFullPath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path.Trim())
}

function Test-HcloudUnderDirectory {
    param([string]$Directory, [string]$Root)
    if ([string]::IsNullOrWhiteSpace($Directory) -or [string]::IsNullOrWhiteSpace($Root)) {
        return $false
    }
    try {
        $full = Get-HcloudFullPath $Directory
        $rootFull = (Get-HcloudFullPath $Root).TrimEnd('\')
    } catch {
        return $false
    }
    if ($full.Equals($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }
    return $full.StartsWith($rootFull + '\', [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-HcloudProtectedDirectory {
    param([string]$Directory)
    if ([string]::IsNullOrWhiteSpace($Directory)) {
        return $false
    }
    $roots = @(
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)},
        $env:SystemRoot
    )
    foreach ($root in $roots) {
        if (Test-HcloudUnderDirectory -Directory $Directory -Root $root) {
            return $true
        }
    }
    return $false
}

function Test-HcloudUnderUserProfile {
    param([string]$Directory)
    return (Test-HcloudUnderDirectory -Directory $Directory -Root $env:USERPROFILE)
}

function Get-HcloudPathTarget {
    param([ValidateSet('User', 'Machine')][string]$Scope)
    if ($Scope -eq 'Machine') {
        return [System.EnvironmentVariableTarget]::Machine
    }
    return [System.EnvironmentVariableTarget]::User
}

function Get-HcloudPathEntries {
    param([ValidateSet('User', 'Machine')][string]$Scope)
    $raw = [Environment]::GetEnvironmentVariable('Path', (Get-HcloudPathTarget $Scope))
    if ([string]::IsNullOrEmpty($raw)) {
        return @()
    }
    return @($raw -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
}

function Test-HcloudPathEntry {
    param(
        [ValidateSet('User', 'Machine')][string]$Scope,
        [string]$Directory
    )
    foreach ($entry in @(Get-HcloudPathEntries -Scope $Scope)) {
        if (Test-HcloudSameDirectory $entry $Directory) {
            return $true
        }
    }
    return $false
}

function Send-HcloudEnvironmentChange {
    if (-not ('HcloudNative.Environment' -as [type])) {
        Add-Type -Namespace HcloudNative -Name Environment -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll", SetLastError=true, CharSet=System.Runtime.InteropServices.CharSet.Auto)]
public static extern System.IntPtr SendMessageTimeout(
    System.IntPtr hWnd,
    uint Msg,
    System.UIntPtr wParam,
    string lParam,
    uint fuFlags,
    uint uTimeout,
    out System.UIntPtr lpdwResult);
'@
    }
    $result = [UIntPtr]::Zero
    [void][HcloudNative.Environment]::SendMessageTimeout(
        [IntPtr]0xffff,
        0x001A,
        [UIntPtr]::Zero,
        'Environment',
        2,
        5000,
        [ref]$result)
}

function Set-HcloudPathEntries {
    param(
        [ValidateSet('User', 'Machine')][string]$Scope,
        [string[]]$Entries
    )
    $value = ''
    if ($Entries -and $Entries.Count -gt 0) {
        $value = ($Entries -join ';')
    }
    [Environment]::SetEnvironmentVariable('Path', $value, (Get-HcloudPathTarget $Scope))
    Send-HcloudEnvironmentChange
}

function Add-HcloudPathEntry {
    param(
        [ValidateSet('User', 'Machine')][string]$Scope,
        [string]$Directory
    )
    $directory = Get-HcloudFullPath $Directory
    $entries = @(Get-HcloudPathEntries -Scope $Scope)
    foreach ($entry in $entries) {
        if (Test-HcloudSameDirectory $entry $directory) {
            return $false
        }
    }
    $updated = @($entries + $directory)
    Set-HcloudPathEntries -Scope $Scope -Entries $updated
    return $true
}

function Remove-HcloudPathEntry {
    param(
        [ValidateSet('User', 'Machine')][string]$Scope,
        [string]$Directory
    )
    $entries = @(Get-HcloudPathEntries -Scope $Scope)
    $kept = New-Object System.Collections.Generic.List[string]
    $removed = $false
    foreach ($entry in $entries) {
        if (Test-HcloudSameDirectory $entry $Directory) {
            $removed = $true
            continue
        }
        $kept.Add($entry)
    }
    if (-not $removed) {
        return $false
    }
    Set-HcloudPathEntries -Scope $Scope -Entries $kept.ToArray()
    return $true
}

function Get-HcloudRegistryRoot {
    param([ValidateSet('CurrentUser', 'LocalMachine')][string]$Hive)
    $hive = [Microsoft.Win32.RegistryHive]::CurrentUser
    if ($Hive -eq 'LocalMachine') {
        $hive = [Microsoft.Win32.RegistryHive]::LocalMachine
    }
    return [Microsoft.Win32.RegistryKey]::OpenBaseKey($hive, [Microsoft.Win32.RegistryView]::Default)
}

function Get-HcloudInstallRecord {
    param([ValidateSet('CurrentUser', 'LocalMachine')][string]$Hive)
    $root = Get-HcloudRegistryRoot -Hive $Hive
    $key = $root.OpenSubKey($script:HcloudRegistryPath, $false)
    if (-not $key) {
        $root.Close()
        return $null
    }
    try {
        return [pscustomobject]@{
            InstallDir      = [string]$key.GetValue('InstallDir')
            ExecutablePath  = [string]$key.GetValue('ExecutablePath')
            ReleaseTag      = [string]$key.GetValue('ReleaseTag')
            PathScope       = [string]$key.GetValue('PathScope')
            InstalledAt     = [string]$key.GetValue('InstalledAt')
            Hive            = $Hive
        }
    } finally {
        $key.Close()
        $root.Close()
    }
}

function Set-HcloudInstallRecord {
    param(
        [ValidateSet('CurrentUser', 'LocalMachine')][string]$Hive,
        [string]$InstallDir,
        [string]$ExecutablePath,
        [string]$ReleaseTag,
        [ValidateSet('User', 'Machine')][string]$PathScope
    )
    $root = Get-HcloudRegistryRoot -Hive $Hive
    $key = $root.CreateSubKey($script:HcloudRegistryPath)
    try {
        $key.SetValue('InstallDir', $InstallDir)
        $key.SetValue('ExecutablePath', $ExecutablePath)
        $key.SetValue('ReleaseTag', $ReleaseTag)
        $key.SetValue('PathScope', $PathScope)
        $key.SetValue('InstalledAt', ([DateTime]::UtcNow.ToString('o')))
    } finally {
        $key.Close()
        $root.Close()
    }
}

function Remove-HcloudInstallRecord {
    param([ValidateSet('CurrentUser', 'LocalMachine')][string]$Hive)
    $root = Get-HcloudRegistryRoot -Hive $Hive
    try {
        $root.DeleteSubKeyTree($script:HcloudRegistryPath, $false)
    } catch [System.ArgumentException] {
        return
    } finally {
        $root.Close()
    }
}

function Test-HcloudDirectoryWritable {
    param([string]$Directory)
    try {
        if (-not (Test-Path -LiteralPath $Directory)) {
            New-Item -ItemType Directory -Path $Directory -Force -ErrorAction Stop | Out-Null
        }
        $probe = Join-Path $Directory ('.hcloud-write-' + [guid]::NewGuid().ToString('n'))
        [System.IO.File]::WriteAllText($probe, 'ok')
        Remove-Item -LiteralPath $probe -Force
        return $true
    } catch {
        return $false
    }
}

function Copy-HcloudExecutable {
    param([string]$Source, [string]$Destination)
    $parent = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
    Unblock-File -LiteralPath $Destination -ErrorAction SilentlyContinue
}

function Remove-HcloudProgramFile {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }
    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Force
    }
    $directory = Split-Path -Parent $Path
    if ([string]::IsNullOrWhiteSpace($directory) -or -not (Test-Path -LiteralPath $directory)) {
        return
    }
    $blocked = @(
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)},
        $env:SystemRoot,
        $env:USERPROFILE,
        $env:LOCALAPPDATA
    )
    foreach ($root in $blocked) {
        if ([string]::IsNullOrWhiteSpace($root)) {
            continue
        }
        $full = Get-HcloudFullPath $directory
        $rootFull = (Get-HcloudFullPath $root).TrimEnd('\')
        if ($full.Equals($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
            return
        }
    }
    $remaining = @(Get-ChildItem -LiteralPath $directory -Force -ErrorAction SilentlyContinue)
    if ($remaining.Count -eq 0) {
        Remove-Item -LiteralPath $directory -Force -ErrorAction SilentlyContinue
    }
}
