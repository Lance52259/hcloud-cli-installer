# 五步图形向导：介绍、操作、分支、进度、结果。
# 控件和状态放在 $script:Wz，按钮事件才能调用到这些函数。

function New-HcloudWizardLabel {
    param([string]$Text, [int]$X, [int]$Y, [int]$Width, [int]$Height)
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.Location = New-Object System.Drawing.Point($X, $Y)
    $label.Size = New-Object System.Drawing.Size($Width, $Height)
    return $label
}

function Test-HcloudWindowsAmd64 {
    $arch = $env:PROCESSOR_ARCHITECTURE
    $wow = ${env:PROCESSOR_ARCHITEW6432}
    return ($arch -eq 'AMD64' -or $wow -eq 'AMD64')
}

function Add-HcloudWizardText {
    param([string]$Text)
    $box = New-Object System.Windows.Forms.TextBox
    $box.Multiline = $true
    $box.ReadOnly = $true
    $box.BorderStyle = 'None'
    $box.BackColor = $script:Wz.Form.BackColor
    $box.Dock = 'Fill'
    $box.TabStop = $false
    $box.ScrollBars = 'Vertical'
    $box.Text = $Text
    $script:Wz.Content.Controls.Add($box)
}

function Update-HcloudWizardButtons {
    $wz = $script:Wz
    $wz.BackButton.Visible = $true
    $wz.NextButton.Visible = $true
    $wz.CancelButton.Visible = $true
    $wz.BackButton.Enabled = -not $wz.State.Busy -and $wz.State.Page -gt 0 -and $wz.State.Page -lt 4
    $wz.NextButton.Enabled = -not $wz.State.Busy
    $wz.CancelButton.Enabled = -not $wz.State.Busy
    $wz.CancelButton.Text = '取消'
    $wz.NextButton.Text = '下一步'
    if ($wz.State.Page -eq 0) {
        $wz.BackButton.Enabled = $false
        $wz.CancelButton.Text = '退出'
    } elseif ($wz.State.Page -eq 3) {
        if ($wz.State.Busy) {
            $wz.NextButton.Text = '请稍候'
        } elseif ($wz.State.Progress -and -not $wz.State.Progress.Ok) {
            $wz.NextButton.Text = '重试'
            $wz.BackButton.Enabled = $true
            $wz.CancelButton.Text = '关闭'
        }
    } elseif ($wz.State.Page -eq 4) {
        $wz.BackButton.Visible = $false
        $wz.CancelButton.Visible = $false
        $wz.NextButton.Text = '完成'
    }
}

function Show-HcloudIntroPage {
    $script:Wz.Title.Text = '欢迎'
    $lines = @(
        '华为云命令行工具（hcloud）用于在命令行中访问和管理华为云服务。',
        '',
        '请阅读以下说明：',
        '',
        '1. 本安装器不包含命令行程序本身。进入进度步骤后，才会从 GitHub Releases 下载所选版本的 Windows 安装包。',
        '2. 安装和更新只修改你确认的目录，并把该目录写入 PATH。相同目录已经存在时不会重复添加。',
        '3. 卸载会删除程序文件和安装记录，并从 PATH 中删除本次安装加入的目录。不会因为路径里出现 hcloud 就删除其他软件的目录。',
        '4. 用户配置目录 %USERPROFILE%\.hcloud 默认保留，只有在卸载步骤中勾选后才会删除。',
        '5. 安装到个人目录时不需要管理员权限。安装到受保护目录或为所有用户安装时，进度中会请求授权，向导窗口保持打开。',
        '6. 完成后请新开一个终端，再执行 hcloud version。已经打开的终端看不到刚修改的 PATH。'
    )
    Add-HcloudWizardText ($lines -join "`r`n")
}

function Get-HcloudShownVersion {
    $installation = $script:Wz.State.Installation
    if ($installation -and -not [string]::IsNullOrWhiteSpace($installation.Version)) {
        return [string]$installation.Version
    }
    if ($script:Wz.VersionProbe) {
        if ($installation -and -not [string]::IsNullOrWhiteSpace($installation.ReleaseTag)) {
            return [string]$installation.ReleaseTag
        }
        return '正在读取'
    }
    return '未知'
}

function Update-HcloudVersionLabel {
    $label = $script:Wz.State.VersionLabel
    if ($label -and -not $label.IsDisposed) {
        $label.Text = [string]$script:Wz.State.VersionPrefix + (Get-HcloudShownVersion)
    }
}

function Stop-HcloudVersionProbe {
    $probe = $script:Wz.VersionProbe
    if (-not $probe) {
        return
    }
    $script:Wz.VersionProbe = $null
    try { $probe.PowerShell.Stop() } catch { }
    try { $probe.PowerShell.Dispose() } catch { }
    try { $probe.Runspace.Close() } catch { }
    try { $probe.Runspace.Dispose() } catch { }
}

function Start-HcloudVersionProbe {
    $installation = $script:Wz.State.Installation
    if (-not $installation -or -not $installation.Found) {
        return
    }
    if (-not [string]::IsNullOrWhiteSpace($installation.Version)) {
        return
    }
    $executable = [string]$installation.ExecutablePath
    if ($script:Wz.VersionProbe -and $script:Wz.VersionProbe.Executable -eq $executable) {
        return
    }
    Stop-HcloudVersionProbe
    $root = $script:InstallerRoot
    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.Open()
    $powershell = [powershell]::Create()
    $powershell.Runspace = $runspace
    $async = $powershell.AddScript({
        param($Root, $Executable)
        . (Join-Path $Root 'detect\Find-Hcloud.ps1')
        Get-HcloudCliVersion -Executable $Executable
    }).AddArgument($root).AddArgument($executable).BeginInvoke()
    $script:Wz.VersionProbe = @{
        PowerShell = $powershell
        Runspace   = $runspace
        Async      = $async
        Executable = $executable
    }
    $script:Wz.Timer.Start()
}

function Update-HcloudVersionProbe {
    $probe = $script:Wz.VersionProbe
    if (-not $probe -or -not $probe.Async.IsCompleted) {
        return
    }
    $version = $null
    try {
        $output = @($probe.PowerShell.EndInvoke($probe.Async))
        if ($output.Count -gt 0) {
            $version = ConvertTo-HcloudVersionNumber ([string]$output[0])
        }
    } catch {
        $version = $null
    }
    $executable = [string]$probe.Executable
    Stop-HcloudVersionProbe
    $installation = $script:Wz.State.Installation
    if ($installation -and $installation.ExecutablePath -eq $executable) {
        $installation.Version = $version
    }
    Update-HcloudVersionLabel
    Stop-HcloudWizardTimerIfIdle
}

function Stop-HcloudWizardTimerIfIdle {
    if ($script:Wz.State.Busy) {
        return
    }
    if ($script:Wz.VersionProbe -and -not $script:Wz.VersionProbe.Async.IsCompleted) {
        return
    }
    if ($script:Wz.LatestProbe -and -not $script:Wz.LatestProbe.Async.IsCompleted) {
        return
    }
    $script:Wz.Timer.Stop()
}

function Stop-HcloudLatestProbe {
    $probe = $script:Wz.LatestProbe
    if (-not $probe) {
        return
    }
    $script:Wz.LatestProbe = $null
    try { $probe.PowerShell.Stop() } catch { }
    try { $probe.PowerShell.Dispose() } catch { }
    try { $probe.Runspace.Close() } catch { }
    try { $probe.Runspace.Dispose() } catch { }
}

function Start-HcloudLatestProbe {
    if (-not [string]::IsNullOrWhiteSpace($script:Wz.State.LatestTag)) {
        return
    }
    if ($script:Wz.LatestProbe) {
        return
    }
    $root = $script:InstallerRoot
    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.Open()
    $powershell = [powershell]::Create()
    $powershell.Runspace = $runspace
    $async = $powershell.AddScript({
        param($Root)
        . (Join-Path $Root 'actions\ReleaseClient.ps1')
        Get-LatestHcloudReleaseTag
    }).AddArgument($root).BeginInvoke()
    $script:Wz.LatestProbe = @{
        PowerShell = $powershell
        Runspace   = $runspace
        Async      = $async
    }
    $script:Wz.Timer.Start()
}

function Update-HcloudLatestProbe {
    $probe = $script:Wz.LatestProbe
    if (-not $probe -or -not $probe.Async.IsCompleted) {
        return
    }
    $tag = ''
    $errorText = ''
    try {
        $output = @($probe.PowerShell.EndInvoke($probe.Async))
        if ($output.Count -gt 0) {
            $tag = ([string]$output[0]).Trim()
        }
        if (-not (Test-HcloudVersionTag $tag)) {
            if ($tag) {
                $errorText = "最新版本标签无效：$tag"
            } else {
                $errorText = '无法查询最新版本。'
            }
            $tag = ''
        }
    } catch {
        $errorText = $_.Exception.Message
        $tag = ''
    }
    Stop-HcloudLatestProbe
    $state = $script:Wz.State
    $state.LatestTag = $tag
    $state.LatestError = $errorText
    $radio = $state.LatestRadio
    if ($radio -and -not $radio.IsDisposed) {
        if ($tag) {
            $radio.Text = "升级到最新版本（$tag）"
            $radio.Enabled = $true
            if ($state.UpdateMode -ne 'Specific') {
                $radio.Checked = $true
            }
        } else {
            $radio.Text = '升级到最新版本（暂时无法查询）'
            $radio.Enabled = $false
            $radio.Checked = $false
        }
    }
    if ($state.LatestErrorLabel -and -not $state.LatestErrorLabel.IsDisposed) {
        $state.LatestErrorLabel.Text = $errorText
    }
    Stop-HcloudWizardTimerIfIdle
}

function Show-HcloudOperationPage {
    $script:Wz.Title.Text = '选择操作'
    $state = $script:Wz.State
    $installed = $state.Installation -and $state.Installation.Found
    if (-not $installed) {
        $script:Wz.Content.Controls.Add((New-HcloudWizardLabel '没有发现已安装的 hcloud。' 0 8 620 24))
        $install = New-Object System.Windows.Forms.RadioButton
        $install.Text = '安装'
        $install.Location = New-Object System.Drawing.Point(0, 44)
        $install.Size = New-Object System.Drawing.Size(200, 24)
        $install.Checked = $true
        $script:Wz.Content.Controls.Add($install)
        $state.InstallRadio = $install
        $state.UpdateRadio = $null
        $state.UninstallRadio = $null
        return
    }

    if ([string]::IsNullOrWhiteSpace($state.Installation.Version)) {
        Start-HcloudVersionProbe
    }
    $script:Wz.Content.Controls.Add((New-HcloudWizardLabel '已发现 hcloud，可以更新或卸载。' 0 0 620 24))
    $script:Wz.Content.Controls.Add((New-HcloudWizardLabel ("程序路径：" + $state.Installation.ExecutablePath) 0 32 620 40))
    $state.VersionPrefix = '版本：'
    $versionLabel = New-HcloudWizardLabel ('版本：' + (Get-HcloudShownVersion)) 0 76 620 24
    $script:Wz.Content.Controls.Add($versionLabel)
    $state.VersionLabel = $versionLabel

    $update = New-Object System.Windows.Forms.RadioButton
    $update.Text = '更新'
    $update.Location = New-Object System.Drawing.Point(0, 116)
    $update.Size = New-Object System.Drawing.Size(200, 24)
    $update.Checked = $state.Operation -ne 'Uninstall'
    $script:Wz.Content.Controls.Add($update)

    $uninstall = New-Object System.Windows.Forms.RadioButton
    $uninstall.Text = '卸载'
    $uninstall.Location = New-Object System.Drawing.Point(0, 148)
    $uninstall.Size = New-Object System.Drawing.Size(200, 24)
    $uninstall.Checked = $state.Operation -eq 'Uninstall'
    $script:Wz.Content.Controls.Add($uninstall)
    $state.InstallRadio = $null
    $state.UpdateRadio = $update
    $state.UninstallRadio = $uninstall
}

function Show-HcloudBranchPage {
    $state = $script:Wz.State
    if ($state.Operation -eq 'Install') {
        $script:Wz.Title.Text = '选择安装目录'
        $script:Wz.Content.Controls.Add((New-HcloudWizardLabel '程序会安装为该目录下的 hcloud.exe，并把该目录写入 PATH。' 0 0 620 36))
        $dir = New-Object System.Windows.Forms.TextBox
        $dir.Location = New-Object System.Drawing.Point(0, 48)
        $dir.Size = New-Object System.Drawing.Size(520, 24)
        $dir.Text = $state.InstallDir
        $script:Wz.Content.Controls.Add($dir)
        $browse = New-Object System.Windows.Forms.Button
        $browse.Text = '浏览'
        $browse.Location = New-Object System.Drawing.Point(532, 46)
        $browse.Size = New-Object System.Drawing.Size(88, 28)
        $script:Wz.Content.Controls.Add($browse)
        $allUsers = New-Object System.Windows.Forms.CheckBox
        $allUsers.Text = '为所有用户安装（写入系统 PATH，需要授权）'
        $allUsers.Location = New-Object System.Drawing.Point(0, 88)
        $allUsers.Size = New-Object System.Drawing.Size(620, 24)
        $allUsers.Checked = [bool]$state.AllUsers
        $script:Wz.Content.Controls.Add($allUsers)
        $script:Wz.Content.Controls.Add((New-HcloudWizardLabel '默认安装到个人目录，不需要管理员权限。选择 Program Files 等受保护目录时，进度中会请求授权。' 0 124 620 48))
        $errorLabel = New-HcloudWizardLabel $state.PageError 0 180 620 72
        $errorLabel.ForeColor = [System.Drawing.Color]::DarkRed
        $script:Wz.Content.Controls.Add($errorLabel)
        $state.DirBox = $dir
        $state.AllUsersBox = $allUsers
        $state.PageErrorLabel = $errorLabel
        $browse.Add_Click({
            $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
            $dialog.Description = '选择安装目录'
            if (Test-Path -LiteralPath $script:Wz.State.DirBox.Text) {
                $dialog.SelectedPath = $script:Wz.State.DirBox.Text
            }
            if ($dialog.ShowDialog() -eq 'OK') {
                $script:Wz.State.DirBox.Text = $dialog.SelectedPath
            }
        })
        $allUsers.Add_CheckedChanged({
            $current = $script:Wz.State.DirBox.Text
            if ($script:Wz.State.AllUsersBox.Checked) {
                if (Test-HcloudUnderUserProfile $current) {
                    $script:Wz.State.DirBox.Text = Join-Path $env:ProgramFiles 'hcloud'
                }
            } elseif (Test-HcloudSameDirectory $current (Join-Path $env:ProgramFiles 'hcloud')) {
                $script:Wz.State.DirBox.Text = Join-Path $env:LOCALAPPDATA 'hcloud'
            }
        })
        return
    }

    if ($state.Operation -eq 'Update') {
        $script:Wz.Title.Text = '选择版本'
        $script:Wz.Content.Controls.Add((New-HcloudWizardLabel ("将覆盖：" + $state.Installation.ExecutablePath) 0 0 620 40))
        $state.VersionPrefix = '当前版本：'
        $versionLabel = New-HcloudWizardLabel ('当前版本：' + (Get-HcloudShownVersion)) 0 40 620 24
        $script:Wz.Content.Controls.Add($versionLabel)
        $state.VersionLabel = $versionLabel

        if (-not $state.LatestTag) {
            Start-HcloudLatestProbe
        }
        $latest = New-Object System.Windows.Forms.RadioButton
        $latest.Location = New-Object System.Drawing.Point(0, 80)
        $latest.Size = New-Object System.Drawing.Size(620, 24)
        if ($state.LatestTag) {
            $latest.Text = "升级到最新版本（$($state.LatestTag)）"
            $latest.Enabled = $true
            $latest.Checked = $state.UpdateMode -ne 'Specific'
        } elseif ($script:Wz.LatestProbe) {
            $latest.Text = '升级到最新版本（正在查询）'
            $latest.Enabled = $false
            $latest.Checked = $false
        } else {
            $latest.Text = '升级到最新版本（暂时无法查询）'
            $latest.Enabled = $false
            $latest.Checked = $false
        }
        $script:Wz.Content.Controls.Add($latest)

        $specific = New-Object System.Windows.Forms.RadioButton
        $specific.Text = '升级到指定版本'
        $specific.Location = New-Object System.Drawing.Point(0, 116)
        $specific.Size = New-Object System.Drawing.Size(160, 24)
        $specific.Checked = -not $latest.Checked
        $script:Wz.Content.Controls.Add($specific)
        $versionBox = New-Object System.Windows.Forms.TextBox
        $versionBox.Location = New-Object System.Drawing.Point(170, 114)
        $versionBox.Size = New-Object System.Drawing.Size(180, 24)
        $versionBox.Text = $state.SpecificVersion
        $script:Wz.Content.Controls.Add($versionBox)
        $latestError = New-HcloudWizardLabel $state.LatestError 0 150 620 40
        $script:Wz.Content.Controls.Add($latestError)
        $state.LatestErrorLabel = $latestError
        $errorLabel = New-HcloudWizardLabel $state.PageError 0 196 620 80
        $errorLabel.ForeColor = [System.Drawing.Color]::DarkRed
        $script:Wz.Content.Controls.Add($errorLabel)
        $state.LatestRadio = $latest
        $state.SpecificRadio = $specific
        $state.VersionBox = $versionBox
        $state.PageErrorLabel = $errorLabel
        $specific.Add_CheckedChanged({
            if ($script:Wz.State.SpecificRadio.Checked) {
                if (-not [string]::IsNullOrWhiteSpace($script:Wz.State.VersionBox.Text)) {
                    $script:Wz.State.UpdateMode = 'Specific'
                }
                $script:Wz.State.VersionBox.Focus() | Out-Null
            }
        })
        return
    }

    $script:Wz.Title.Text = '确认卸载'
    $script:Wz.Content.Controls.Add((New-HcloudWizardLabel ("将删除程序：" + $state.Installation.ExecutablePath) 0 0 620 40))
    $script:Wz.Content.Controls.Add((New-HcloudWizardLabel ("将从 PATH 删除目录：" + $state.Installation.InstallDir) 0 44 620 40))
    $config = New-Object System.Windows.Forms.CheckBox
    $config.Text = "同时删除用户配置目录 $env:USERPROFILE\.hcloud"
    $config.Location = New-Object System.Drawing.Point(0, 100)
    $config.Size = New-Object System.Drawing.Size(620, 24)
    $config.Checked = [bool]$state.RemoveConfig
    $script:Wz.Content.Controls.Add($config)
    $script:Wz.Content.Controls.Add((New-HcloudWizardLabel '默认不删除配置。无论是否勾选，都会删除程序、安装记录，以及 PATH 中对应的目录项。' 0 136 620 48))
    $state.ConfigBox = $config
}

function Show-HcloudProgressPage {
    $heading = '正在安装'
    if ($script:Wz.State.Operation -eq 'Update') { $heading = '正在更新' }
    if ($script:Wz.State.Operation -eq 'Uninstall') { $heading = '正在卸载' }
    $script:Wz.Title.Text = $heading
    $step = New-HcloudWizardLabel '准备开始' 0 0 620 24
    $script:Wz.Content.Controls.Add($step)
    $bar = New-Object System.Windows.Forms.ProgressBar
    $bar.Location = New-Object System.Drawing.Point(0, 32)
    $bar.Size = New-Object System.Drawing.Size(620, 22)
    $bar.Minimum = 0
    $bar.Maximum = 100
    $script:Wz.Content.Controls.Add($bar)
    $log = New-Object System.Windows.Forms.TextBox
    $log.Location = New-Object System.Drawing.Point(0, 68)
    $log.Size = New-Object System.Drawing.Size(620, 150)
    $log.Multiline = $true
    $log.ReadOnly = $true
    $log.ScrollBars = 'Vertical'
    $script:Wz.Content.Controls.Add($log)
    $logPath = Get-HcloudSetupLogPath
    $script:Wz.Content.Controls.Add((New-HcloudWizardLabel ("调试日志：" + $logPath) 0 224 620 28))
    $errorLabel = New-HcloudWizardLabel '' 0 256 620 80
    $errorLabel.ForeColor = [System.Drawing.Color]::DarkRed
    $script:Wz.Content.Controls.Add($errorLabel)
    $script:Wz.State.StepLabel = $step
    $script:Wz.State.ProgressBar = $bar
    $script:Wz.State.LogBox = $log
    $script:Wz.State.ErrorLabel = $errorLabel
}

function Show-HcloudResultPage {
    $script:Wz.Title.Text = '完成'
    $state = $script:Wz.State
    $progress = $state.Progress
    if ($state.Operation -eq 'Uninstall') {
        $text = "卸载完成。`r`n`r`n已删除程序，并已从 PATH 移除安装目录 $($state.Installation.InstallDir)。"
        if ($state.RemoveConfig) {
            $text += "`r`n用户配置目录 .hcloud 已删除。"
        } else {
            $text += "`r`n用户配置目录 .hcloud 已保留。"
        }
        $text += "`r`n调试日志：$(Get-HcloudSetupLogPath)"
    } else {
        $action = '安装'
        if ($state.Operation -eq 'Update') { $action = '更新' }
        $shownVersion = $state.ResolvedVersion
        if ($shownVersion -eq 'latest') { $shownVersion = '最新版本' }
        $text = "$action 完成。`r`n`r`n程序路径：$($progress.ResultPath)`r`n版本：$shownVersion"
        if ($progress.Note) {
            $text += "`r`n$($progress.Note)"
        }
        $text += "`r`n`r`n请新开一个终端，再执行 hcloud version。已经打开的 PowerShell、CMD 和终端看不到刚修改的 PATH。"
        $text += "`r`n调试日志：$(Get-HcloudSetupLogPath)"
    }
    Add-HcloudWizardText $text
}

function Show-HcloudWizardPage {
    $script:Wz.Content.Controls.Clear()
    $script:Wz.State.PageErrorLabel = $null
    switch ($script:Wz.State.Page) {
        0 { Show-HcloudIntroPage }
        1 { Show-HcloudOperationPage }
        2 { Show-HcloudBranchPage }
        3 { Show-HcloudProgressPage }
        4 { Show-HcloudResultPage }
    }
    Update-HcloudWizardButtons
}

function Save-HcloudWizardPage {
    $state = $script:Wz.State
    if ($state.Page -eq 1) {
        if ($state.InstallRadio) {
            $state.Operation = 'Install'
        } elseif ($state.UninstallRadio -and $state.UninstallRadio.Checked) {
            $state.Operation = 'Uninstall'
        } else {
            $state.Operation = 'Update'
        }
    } elseif ($state.Page -eq 2 -and $state.Operation -eq 'Install' -and $state.DirBox) {
        $state.InstallDir = $state.DirBox.Text.Trim()
        $state.AllUsers = $state.AllUsersBox.Checked
    } elseif ($state.Page -eq 2 -and $state.Operation -eq 'Update' -and $state.SpecificRadio) {
        $state.SpecificVersion = $state.VersionBox.Text.Trim()
        if ($state.LatestRadio -and $state.LatestRadio.Checked) {
            $state.UpdateMode = 'Latest'
        } elseif (-not [string]::IsNullOrWhiteSpace($state.SpecificVersion)) {
            $state.UpdateMode = 'Specific'
        }
    } elseif ($state.Page -eq 2 -and $state.Operation -eq 'Uninstall' -and $state.ConfigBox) {
        $state.RemoveConfig = $state.ConfigBox.Checked
    }
}

function Set-HcloudWizardPageError {
    param([string]$Message)
    $script:Wz.State.PageError = $Message
    if ($script:Wz.State.PageErrorLabel) {
        $script:Wz.State.PageErrorLabel.Text = $Message
    }
}

function Resolve-HcloudWizardRelease {
    param([string]$Version)
    if (-not (Test-HcloudReleaseAsset -Version $Version)) {
        Set-HcloudWizardPageError "版本 $Version 没有 Windows 安装包 huaweicloud-cli-windows-amd64.zip。"
        return $false
    }
    $script:Wz.State.ResolvedVersion = $Version
    return $true
}

function Confirm-HcloudWizardPage {
    $state = $script:Wz.State
    $state.PageError = ''
    if ($state.Page -eq 0) {
        $script:Wz.Form.UseWaitCursor = $true
        try {
            $state.Installation = Find-HcloudInstallation
        } catch {
            [System.Windows.Forms.MessageBox]::Show($script:Wz.Form, $_.Exception.Message, '探测失败') | Out-Null
            return $false
        } finally {
            $script:Wz.Form.UseWaitCursor = $false
        }
        if ($state.Installation.Found) {
            if ($state.Operation -eq 'Install') {
                $state.Operation = 'Update'
            }
        } else {
            $state.Operation = 'Install'
        }
        return $true
    }

    if ($state.Page -ne 2) {
        return $true
    }

    if (-not (Test-HcloudWindowsAmd64)) {
        Set-HcloudWizardPageError '当前只提供 Windows amd64 安装包。'
        return $false
    }

    if ($state.Operation -eq 'Install') {
        $raw = $state.DirBox.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($raw)) {
            Set-HcloudWizardPageError '请选择安装目录。'
            return $false
        }
        try {
            $full = Get-HcloudFullPath $raw
        } catch {
            Set-HcloudWizardPageError '安装目录无效。'
            return $false
        }
        $allUsers = [bool]$state.AllUsersBox.Checked
        $protected = Test-HcloudProtectedDirectory $full
        if (($allUsers -or $protected) -and (Test-HcloudUnderUserProfile $full)) {
            Set-HcloudWizardPageError '为所有用户安装时，请选择 Program Files 等所有用户都能访问的目录。'
            return $false
        }
        $state.InstallDir = $full
        $state.AllUsers = $allUsers -or $protected
        if ($state.AllUsers) {
            $state.PathScope = 'Machine'
        } else {
            $state.PathScope = 'User'
        }
        $script:Wz.Form.UseWaitCursor = $true
        try {
            try {
                $tag = Get-LatestHcloudReleaseTag
            } catch {
                $state.ResolvedVersion = 'latest'
                return $true
            }
            return (Resolve-HcloudWizardRelease -Version $tag)
        } catch {
            Set-HcloudWizardPageError $_.Exception.Message
            return $false
        } finally {
            $script:Wz.Form.UseWaitCursor = $false
        }
    }

    if ($state.Operation -eq 'Update') {
        $state.InstallDir = $state.Installation.InstallDir
        if ($state.Installation.PathScope -eq 'Machine' -or (Test-HcloudProtectedDirectory $state.InstallDir)) {
            $state.PathScope = 'Machine'
        } else {
            $state.PathScope = 'User'
        }
        $script:Wz.Form.UseWaitCursor = $true
        try {
            if ($state.LatestRadio.Checked) {
                if ([string]::IsNullOrWhiteSpace($state.LatestTag)) {
                    Set-HcloudWizardPageError '正在查询最新版本，请稍候。'
                    return $false
                }
                return (Resolve-HcloudWizardRelease -Version $state.LatestTag)
            }
            if ($script:Wz.LatestProbe -and [string]::IsNullOrWhiteSpace($state.VersionBox.Text)) {
                Set-HcloudWizardPageError '正在查询最新版本，请稍候，或输入指定版本。'
                return $false
            }
            $tag = $state.VersionBox.Text.Trim()
            if (-not (Test-HcloudVersionTag $tag)) {
                Set-HcloudWizardPageError '版本号只能包含字母、数字、点、下划线、加号和减号，并且要与 Release 标签完全一致，例如 1.2.0。'
                return $false
            }
            $state.SpecificVersion = $tag
            return (Resolve-HcloudWizardRelease -Version $tag)
        } catch {
            Set-HcloudWizardPageError $_.Exception.Message
            return $false
        } finally {
            $script:Wz.Form.UseWaitCursor = $false
        }
    }

    $state.RemoveConfig = $state.ConfigBox.Checked
    $state.InstallDir = $state.Installation.InstallDir
    if ($state.Installation.PathScope -eq 'Machine' -or (Test-HcloudProtectedDirectory $state.InstallDir)) {
        $state.PathScope = 'Machine'
    } else {
        $state.PathScope = 'User'
    }
    return $true
}

function Stop-HcloudWizardRunspace {
    $wz = $script:Wz
    if ($wz.PowerShell) {
        try { $wz.PowerShell.Dispose() } catch { }
        $wz.PowerShell = $null
    }
    if ($wz.Runspace) {
        try { $wz.Runspace.Close() } catch { }
        try { $wz.Runspace.Dispose() } catch { }
        $wz.Runspace = $null
    }
}

function Start-HcloudWizardAction {
    Stop-HcloudWizardRunspace
    $state = $script:Wz.State
    $lock = New-Object System.Object
    $progress = [hashtable]::Synchronized(@{
        Lock         = $lock
        Percent      = 0
        Step         = '准备开始'
        Detail       = ''
        Log          = ''
        Note         = ''
        Done         = $false
        Ok           = $false
        ErrorStep    = ''
        ErrorMessage = ''
        ResultPath   = ''
        KeptArchive  = ''
        LogFile      = (Get-HcloudSetupLogPath)
    })
    $state.Progress = $progress
    $request = @{
        Operation      = [string]$state.Operation
        Version        = [string]$state.ResolvedVersion
        InstallDir     = [string]$state.InstallDir
        ExecutablePath = ''
        PathScope      = [string]$state.PathScope
        RemoveConfig   = [bool]$state.RemoveConfig
        WorkRoot       = [string]$state.WorkRoot
    }
    if ($state.Installation -and $state.Installation.Found) {
        $request.ExecutablePath = [string]$state.Installation.ExecutablePath
        if ($state.Operation -ne 'Install') {
            $request.InstallDir = [string]$state.Installation.InstallDir
        }
    }

    $root = $script:InstallerRoot
    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.ApartmentState = 'STA'
    $runspace.ThreadOptions = 'ReuseThread'
    $runspace.Open()
    $powershell = [powershell]::Create()
    $powershell.Runspace = $runspace
    [void]$powershell.AddScript({
        param($Root, $Progress, $Request)
        $ErrorActionPreference = 'Stop'
        try {
            $script:InstallerRoot = $Root
            . (Join-Path $Root 'actions\PathRegistry.ps1')
            . (Join-Path $Root 'actions\ReleaseClient.ps1')
            . (Join-Path $Root 'actions\SetupActions.ps1')
            Invoke-HcloudSetupAction -Request $Request -Progress $Progress
        } catch {
            $Progress.Ok = $false
            $Progress.ErrorStep = '准备'
            $Progress.ErrorMessage = $_.Exception.Message
            $Progress.Done = $true
            try {
                Write-HcloudLogFile -Path ([string]$Progress.LogFile) -Message ("准备失败。{0}" -f (Format-HcloudError $_))
            } catch { }
        }
    }).AddArgument($root).AddArgument($progress).AddArgument($request)
    $script:Wz.PowerShell = $powershell
    $script:Wz.Runspace = $runspace
    $script:Wz.Async = $powershell.BeginInvoke()
    $state.Busy = $true
    Update-HcloudWizardButtons
    $script:Wz.Timer.Start()
}

function Move-HcloudWizardNext {
    $state = $script:Wz.State
    if ($state.Busy) {
        return
    }
    if ($state.Page -eq 4) {
        $script:Wz.Form.Close()
        return
    }
    if ($state.Page -eq 3) {
        if ($state.ErrorLabel) {
            $state.ErrorLabel.Text = ''
        }
        $script:Wz.Title.Text = $(if ($state.Operation -eq 'Uninstall') { '正在卸载' } elseif ($state.Operation -eq 'Update') { '正在更新' } else { '正在安装' })
        Start-HcloudWizardAction
        return
    }

    Save-HcloudWizardPage
    if (-not (Confirm-HcloudWizardPage)) {
        return
    }
    $state.Page++
    Show-HcloudWizardPage
    if ($state.Page -eq 3) {
        Start-HcloudWizardAction
    }
}

function Move-HcloudWizardBack {
    $state = $script:Wz.State
    if ($state.Busy -or $state.Page -le 0 -or $state.Page -ge 4) {
        return
    }
    Save-HcloudWizardPage
    $state.Page--
    Show-HcloudWizardPage
}

function Update-HcloudWizardProgress {
    $progress = $script:Wz.State.Progress
    if (-not $progress) {
        return
    }
    $snapshot = @{}
    $lockTaken = $false
    [System.Threading.Monitor]::Enter($progress.Lock, [ref]$lockTaken)
    try {
        $snapshot.Percent = [int]$progress.Percent
        $snapshot.Step = [string]$progress.Step
        $snapshot.Log = [string]$progress.Log
        $snapshot.Done = [bool]$progress.Done
        $snapshot.Ok = [bool]$progress.Ok
        $snapshot.ErrorStep = [string]$progress.ErrorStep
        $snapshot.ErrorMessage = [string]$progress.ErrorMessage
        $snapshot.KeptArchive = [string]$progress.KeptArchive
    } finally {
        if ($lockTaken) {
            [System.Threading.Monitor]::Exit($progress.Lock)
        }
    }

    $state = $script:Wz.State
    if ($state.StepLabel) {
        $state.StepLabel.Text = $snapshot.Step
    }
    if ($state.ProgressBar) {
        $percent = $snapshot.Percent
        if ($percent -lt 0) { $percent = 0 }
        if ($percent -gt 100) { $percent = 100 }
        $state.ProgressBar.Value = $percent
    }
    if ($state.LogBox -and $state.LogBox.Text -ne $snapshot.Log) {
        $state.LogBox.Text = $snapshot.Log
        $state.LogBox.SelectionStart = $state.LogBox.Text.Length
        $state.LogBox.ScrollToCaret()
    }
    if (-not $snapshot.Done) {
        return
    }

    $script:Wz.Timer.Stop()
    try { $script:Wz.PowerShell.EndInvoke($script:Wz.Async) | Out-Null } catch { }
    $state.Busy = $false
    if ($snapshot.Ok) {
        $state.Page = 4
        Show-HcloudWizardPage
        return
    }
    $message = "失败步骤：$($snapshot.ErrorStep)`r`n$($snapshot.ErrorMessage)"
    if ($snapshot.KeptArchive) {
        $message += "`r`n已保留安装包：$($snapshot.KeptArchive)"
    }
    $message += "`r`n调试日志：$(Get-HcloudSetupLogPath)"
    $script:Wz.Title.Text = '未能完成'
    if ($state.ErrorLabel) {
        $state.ErrorLabel.Text = $message
    }
    Update-HcloudWizardButtons
}

function New-HcloudWizardFont {
    param([float]$Size, [string]$StyleName = 'Regular')
    $style = [System.Drawing.FontStyle]$StyleName
    foreach ($name in @('Microsoft YaHei UI', 'Microsoft YaHei', 'Segoe UI')) {
        try {
            return (New-Object System.Drawing.Font($name, $Size, $style))
        } catch {
            continue
        }
    }
    return (New-Object System.Drawing.Font('Segoe UI', $Size, $style))
}

function Show-SetupWizard {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    $form = New-Object System.Windows.Forms.Form
    $form.Text = '华为云命令行工具安装程序'
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ClientSize = New-Object System.Drawing.Size(680, 460)
    $form.Font = New-HcloudWizardFont 9

    $title = New-HcloudWizardLabel '' 24 16 632 32
    $title.Font = New-HcloudWizardFont 14 Bold
    $form.Controls.Add($title)

    $content = New-Object System.Windows.Forms.Panel
    $content.Location = New-Object System.Drawing.Point(24, 56)
    $content.Size = New-Object System.Drawing.Size(632, 340)
    $form.Controls.Add($content)

    $back = New-Object System.Windows.Forms.Button
    $next = New-Object System.Windows.Forms.Button
    $cancel = New-Object System.Windows.Forms.Button
    foreach ($button in @($back, $next, $cancel)) {
        $button.Size = New-Object System.Drawing.Size(88, 28)
        $form.Controls.Add($button)
    }
    $back.Text = '上一步'
    $back.Location = New-Object System.Drawing.Point(376, 414)
    $next.Text = '下一步'
    $next.Location = New-Object System.Drawing.Point(472, 414)
    $cancel.Text = '取消'
    $cancel.Location = New-Object System.Drawing.Point(568, 414)
    $form.AcceptButton = $next
    $form.CancelButton = $cancel

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 200

    $script:Wz = @{
        Form          = $form
        Title         = $title
        Content       = $content
        BackButton    = $back
        NextButton    = $next
        CancelButton  = $cancel
        Timer         = $timer
        PowerShell    = $null
        Runspace      = $null
        Async         = $null
        State         = @{
            Page            = 0
            Installation    = $null
            Operation       = 'Install'
            InstallDir      = (Join-Path $env:LOCALAPPDATA 'hcloud')
            AllUsers        = $false
            UpdateMode      = 'Latest'
            SpecificVersion = ''
            ResolvedVersion = ''
            RemoveConfig    = $false
            PathScope       = 'User'
            WorkRoot        = (Join-Path $env:TEMP ('hcloud-setup-' + [guid]::NewGuid().ToString('n')))
            Busy            = $false
            LatestTag       = ''
            LatestError     = ''
            PageError       = ''
            Progress        = $null
        }
    }

    $next.Add_Click({ Move-HcloudWizardNext })
    $back.Add_Click({ Move-HcloudWizardBack })
    $cancel.Add_Click({
        if (-not $script:Wz.State.Busy) {
            $script:Wz.Form.Close()
        }
    })
    $form.Add_FormClosing({
        if ($script:Wz.State.Busy) {
            $_.Cancel = $true
            [System.Windows.Forms.MessageBox]::Show($script:Wz.Form, '操作仍在进行。失败后可以关闭，或重试授权。', '请稍候') | Out-Null
        }
    })
    $timer.Add_Tick({
        Update-HcloudVersionProbe
        Update-HcloudLatestProbe
        Update-HcloudWizardProgress
    })

    Write-HcloudLogFile -Message '向导已打开。'
    Show-HcloudWizardPage
    $form.Add_Shown({
        $script:Wz.Form.Activate()
    })
    [void]$form.ShowDialog()
    $timer.Stop()
    $timer.Dispose()
    Stop-HcloudVersionProbe
    Stop-HcloudLatestProbe
    Stop-HcloudWizardRunspace
}
