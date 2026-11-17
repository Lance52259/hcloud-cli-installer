# 离线安装器界面。程序压缩包、版本号和 SHA256 由 exe 传入。
param(
    [Parameter(Mandatory = $true)][string]$Archive,
    [Parameter(Mandatory = $true)][string]$Version,
    [Parameter(Mandatory = $true)][string]$Sha256
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'actions\PathRegistry.ps1')

function Get-HcloudDefaultInstallDir {
    foreach ($hive in @('CurrentUser', 'LocalMachine')) {
        $record = Get-HcloudInstallRecord -Hive $hive
        if ($record -and -not [string]::IsNullOrWhiteSpace([string]$record.InstallDir)) {
            return [string]$record.InstallDir
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        return (Join-Path $env:LOCALAPPDATA 'hcloud')
    }
    return (Join-Path $env:USERPROFILE 'hcloud')
}

function Invoke-HcloudElevatedInstall {
    param(
        [string]$InstallDir,
        [string]$SourceExe,
        [string]$ReleaseTag
    )
    $id = [guid]::NewGuid().ToString('n')
    $jobFile = Join-Path $env:TEMP "hcloud-elevated-$id.json"
    $resultFile = Join-Path $env:TEMP "hcloud-elevated-$id.txt"
    $job = [pscustomobject]@{
        Action              = 'install'
        CopyFile            = $true
        UpdateMachinePath   = $true
        UpdateMachineRecord = $true
        InstallDir          = $InstallDir
        SourceExe           = $SourceExe
        ReleaseTag          = $ReleaseTag
        ResultFile          = $resultFile
    }
    $json = $job | ConvertTo-Json -Compress
    [System.IO.File]::WriteAllText($jobFile, $json, (New-Object System.Text.UTF8Encoding $false))
    $script = Join-Path $PSScriptRoot 'actions\Invoke-Elevated.ps1'
    $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$script`" -JobFile `"$jobFile`""
    try {
        $process = Start-Process -FilePath $powershell -Verb RunAs -Wait -PassThru -ArgumentList $arguments
    } catch {
        throw "用户拒绝了授权。已有安装保持原样。"
    }
    if (-not $process -or $process.ExitCode -ne 0) {
        $reason = "提权安装失败。"
        if (Test-Path -LiteralPath $resultFile) {
            $written = [System.IO.File]::ReadAllText($resultFile).Trim()
            if (-not [string]::IsNullOrWhiteSpace($written)) {
                $reason = $written
            }
        }
        throw "$reason 已有安装保持原样。"
    }
}

function Install-EmbeddedHcloud {
    param([string]$InstallDir)
    $expected = $Sha256.Trim().ToLowerInvariant()
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $Archive).Hash.ToLowerInvariant()
    if ($actual -ne $expected) {
        throw "安装包校验失败，已停止。未改动已有文件。"
    }
    $work = Join-Path $env:TEMP ('hcloud-setup-' + [guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    try {
        Expand-Archive -LiteralPath $Archive -DestinationPath $work -Force
        $source = Join-Path $work 'hcloud.exe'
        if (-not (Test-Path -LiteralPath $source)) {
            throw "压缩包顶层没有 hcloud.exe。未改动已有文件。"
        }
        $directory = Get-HcloudFullPath $InstallDir
        $destination = Join-Path $directory 'hcloud.exe'
        if (Test-HcloudProtectedDirectory $directory) {
            Invoke-HcloudElevatedInstall -InstallDir $directory -SourceExe $source -ReleaseTag $Version
        } else {
            Copy-HcloudExecutable -Source $source -Destination $destination
            [void](Add-HcloudPathEntry -Scope 'User' -Directory $directory)
            Set-HcloudInstallRecord -Hive 'CurrentUser' -InstallDir $directory -ExecutablePath $destination -ReleaseTag $Version -PathScope 'User'
        }
        return $destination
    } finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function New-HcloudLabel {
    param([string]$Text, [int]$X, [int]$Y, [int]$Width, [int]$Height)
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.Location = New-Object System.Drawing.Point($X, $Y)
    $label.Size = New-Object System.Drawing.Size($Width, $Height)
    return $label
}

function Clear-HcloudContent {
    $script:Ui.Content.Controls.Clear()
}

function Update-HcloudButtons {
    $ui = $script:Ui
    $ui.BackButton.Visible = $true
    $ui.NextButton.Visible = $true
    $ui.CancelButton.Visible = $true
    $ui.BackButton.Enabled = -not $ui.State.Busy -and $ui.State.Page -eq 1
    $ui.NextButton.Enabled = -not $ui.State.Busy
    $ui.CancelButton.Enabled = -not $ui.State.Busy
    $ui.NextButton.Text = '下一步'
    $ui.CancelButton.Text = '取消'
    if ($ui.State.Page -eq 0) {
        $ui.BackButton.Enabled = $false
        $ui.CancelButton.Text = '退出'
    } elseif ($ui.State.Page -eq 3) {
        $ui.BackButton.Visible = -not $ui.State.Ok
        $ui.BackButton.Enabled = -not $ui.State.Ok
        $ui.CancelButton.Visible = -not $ui.State.Ok
        $ui.CancelButton.Text = '关闭'
        $ui.NextButton.Text = '完成'
        $ui.NextButton.Enabled = $ui.State.Ok
    }
}

function Show-HcloudIntro {
    $script:Ui.Title.Text = '安装华为云命令行工具'
    $text = @(
        "本次安装的版本是 $Version。",
        '',
        '程序已经包含在这个安装器里，安装过程不访问网络。',
        '安装会把 hcloud.exe 复制到你选择的目录，并把该目录写入 PATH。',
        '安装到个人目录时不需要管理员权限。安装到受保护目录时会请求授权。',
        '用户配置目录 %USERPROFILE%\.hcloud 会保留。',
        '完成后请新开一个终端，再执行 hcloud version。'
    ) -join "`r`n"
    $box = New-Object System.Windows.Forms.TextBox
    $box.Multiline = $true
    $box.ReadOnly = $true
    $box.BorderStyle = 'None'
    $box.BackColor = $script:Ui.Form.BackColor
    $box.Dock = 'Fill'
    $box.TabStop = $false
    $box.Text = $text
    $script:Ui.Content.Controls.Add($box)
}

function Show-HcloudDirectory {
    $script:Ui.Title.Text = '选择安装目录'
    $script:Ui.Content.Controls.Add((New-HcloudLabel '默认安装到 %LOCALAPPDATA%\hcloud。已经安装过时，这里显示上次的目录。' 0 0 600 40))
    $box = New-Object System.Windows.Forms.TextBox
    $box.Location = New-Object System.Drawing.Point(0, 52)
    $box.Size = New-Object System.Drawing.Size(480, 24)
    $box.Text = [string]$script:Ui.State.Directory
    $browse = New-Object System.Windows.Forms.Button
    $browse.Text = '浏览'
    $browse.Location = New-Object System.Drawing.Point(492, 50)
    $browse.Size = New-Object System.Drawing.Size(88, 28)
    $browse.Add_Click({
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = '选择 hcloud.exe 的安装目录'
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $script:Ui.DirectoryBox.Text = $dialog.SelectedPath
        }
    })
    $script:Ui.DirectoryBox = $box
    $script:Ui.Content.Controls.Add($box)
    $script:Ui.Content.Controls.Add($browse)
}

function Show-HcloudResult {
    if ($script:Ui.State.Ok) {
        $script:Ui.Title.Text = '安装完成'
        $text = @(
            '安装完成。',
            '',
            "程序路径：$($script:Ui.State.ResultPath)",
            "版本：$Version",
            '',
            '请新开一个终端，再执行 hcloud version。'
        ) -join "`r`n"
    } else {
        $script:Ui.Title.Text = '安装未完成'
        $text = [string]$script:Ui.State.ErrorText
        if ([string]::IsNullOrWhiteSpace($text)) {
            $text = '安装失败。未改动已有文件。'
        }
    }
    $box = New-Object System.Windows.Forms.TextBox
    $box.Multiline = $true
    $box.ReadOnly = $true
    $box.BorderStyle = 'None'
    $box.BackColor = $script:Ui.Form.BackColor
    $box.Dock = 'Fill'
    $box.TabStop = $false
    $box.Text = $text
    $script:Ui.Content.Controls.Add($box)
}

function Start-HcloudInstall {
    $script:Ui.State.Busy = $true
    $script:Ui.Title.Text = '正在安装'
    Clear-HcloudContent
    $script:Ui.Content.Controls.Add((New-HcloudLabel '正在校验并安装…' 0 8 600 32))
    Update-HcloudButtons
    $script:Ui.Form.Refresh()
    [System.Windows.Forms.Application]::DoEvents()
    try {
        $installed = Install-EmbeddedHcloud -InstallDir ([string]$script:Ui.State.Directory)
        $script:Ui.State.Ok = $true
        $script:Ui.State.ResultPath = $installed
        $script:Ui.State.ErrorText = ''
    } catch {
        $script:Ui.State.Ok = $false
        $script:Ui.State.ResultPath = ''
        $script:Ui.State.ErrorText = $_.Exception.Message
    }
    $script:Ui.State.Busy = $false
    $script:Ui.State.Page = 3
    Show-HcloudPage
}

function Show-HcloudPage {
    if ($script:Ui.State.Page -eq 2) {
        Start-HcloudInstall
        return
    }
    Clear-HcloudContent
    switch ($script:Ui.State.Page) {
        0 { Show-HcloudIntro }
        1 { Show-HcloudDirectory }
        3 { Show-HcloudResult }
    }
    Update-HcloudButtons
}

function Show-InstallWindow {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $form = New-Object System.Windows.Forms.Form
    $form.Text = '华为云命令行工具安装程序'
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ClientSize = New-Object System.Drawing.Size(640, 360)
    $form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
    $title = New-HcloudLabel '安装华为云命令行工具' 16 12 608 28
    $title.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 12)
    $content = New-Object System.Windows.Forms.Panel
    $content.Location = New-Object System.Drawing.Point(16, 48)
    $content.Size = New-Object System.Drawing.Size(608, 240)
    $back = New-Object System.Windows.Forms.Button
    $back.Text = '上一步'
    $back.Location = New-Object System.Drawing.Point(328, 308)
    $back.Size = New-Object System.Drawing.Size(88, 32)
    $next = New-Object System.Windows.Forms.Button
    $next.Text = '下一步'
    $next.Location = New-Object System.Drawing.Point(424, 308)
    $next.Size = New-Object System.Drawing.Size(88, 32)
    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = '退出'
    $cancel.Location = New-Object System.Drawing.Point(520, 308)
    $cancel.Size = New-Object System.Drawing.Size(88, 32)
    $form.Controls.Add($title)
    $form.Controls.Add($content)
    $form.Controls.Add($back)
    $form.Controls.Add($next)
    $form.Controls.Add($cancel)
    $form.AcceptButton = $next
    $form.CancelButton = $cancel
    $script:Ui = @{
        Form         = $form
        Title        = $title
        Content      = $content
        BackButton   = $back
        NextButton   = $next
        CancelButton = $cancel
        DirectoryBox = $null
        State        = @{
            Page       = 0
            Busy       = $false
            Directory  = (Get-HcloudDefaultInstallDir)
            Ok         = $false
            ResultPath = ''
            ErrorText  = ''
        }
    }
    $back.Add_Click({
        if ($script:Ui.State.Busy) { return }
        if ($script:Ui.State.Page -eq 1) {
            $script:Ui.State.Page = 0
        } elseif ($script:Ui.State.Page -eq 3 -and -not $script:Ui.State.Ok) {
            $script:Ui.State.Page = 1
        }
        Show-HcloudPage
    })
    $next.Add_Click({
        if ($script:Ui.State.Busy) { return }
        if ($script:Ui.State.Page -eq 0) {
            $script:Ui.State.Page = 1
            Show-HcloudPage
            return
        }
        if ($script:Ui.State.Page -eq 1) {
            $chosen = $script:Ui.DirectoryBox.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($chosen)) {
                [System.Windows.Forms.MessageBox]::Show('请填写安装目录。', '华为云命令行工具安装程序')
                return
            }
            try {
                $script:Ui.State.Directory = Get-HcloudFullPath $chosen
            } catch {
                [System.Windows.Forms.MessageBox]::Show('安装目录无效。', '华为云命令行工具安装程序')
                return
            }
            $script:Ui.State.Page = 2
            Show-HcloudPage
            return
        }
        if ($script:Ui.State.Page -eq 3 -and $script:Ui.State.Ok) {
            $script:Ui.Form.Close()
        }
    })
    $cancel.Add_Click({
        if (-not $script:Ui.State.Busy) {
            $script:Ui.Form.Close()
        }
    })
    Show-HcloudPage
    [void]$form.ShowDialog()
}

try {
    Show-InstallWindow
} catch {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, '华为云命令行工具安装程序')
    exit 1
}
