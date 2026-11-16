// Windows 安装器启动程序。发布时编译为 huaweicloud-cli-setup-windows-amd64.exe。
// 脚本位置相对本程序固定为 ..\powershell\HcloudSetup.ps1。
//
// 在本目录重新构建：
//
//	GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -ldflags "-H windowsgui -s -w" -o huaweicloud-cli-setup-windows-amd64.exe .
package main

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"time"
	"unsafe"
)

func main() {
	code := run()
	os.Exit(code)
}

func run() int {
	exe, err := os.Executable()
	if err != nil {
		showError("无法确定安装程序位置。\n" + err.Error())
		return 1
	}
	script := filepath.Clean(filepath.Join(filepath.Dir(exe), "..", "powershell", "HcloudSetup.ps1"))
	if _, err = os.Stat(script); err != nil {
		showError("找不到安装脚本：\n" + script)
		return 1
	}

	systemRoot := os.Getenv("SystemRoot")
	if systemRoot == "" {
		systemRoot = os.Getenv("WINDIR")
	}
	if systemRoot == "" {
		systemRoot = `C:\Windows`
	}
	powershell := filepath.Join(systemRoot, "System32", "WindowsPowerShell", "v1.0", "powershell.exe")
	if _, err = os.Stat(powershell); err != nil {
		showError("找不到 Windows PowerShell：\n" + powershell)
		return 1
	}

	command := exec.Command(powershell,
		"-NoProfile",
		"-STA",
		"-ExecutionPolicy", "Bypass",
		"-File", script,
	)
	command.Dir = filepath.Dir(script)
	var output bytes.Buffer
	command.Stdout = &output
	command.Stderr = &output
	writeLog("启动 PowerShell：" + powershell)
	writeLog("安装脚本：" + script)
	err = command.Run()
	if err == nil {
		writeLog("安装程序已退出。")
		return 0
	}
	detail := strings.TrimSpace(output.String())
	if detail == "" {
		detail = err.Error()
	}
	writeLog("启动失败：" + detail)
	showError("无法启动安装程序。\n" + detail)
	if exitErr, ok := err.(*exec.ExitError); ok {
		return exitErr.ExitCode()
	}
	return 1
}

func writeLog(text string) {
	dir := os.Getenv("TEMP")
	if dir == "" {
		dir = os.Getenv("TMP")
	}
	if dir == "" {
		return
	}
	path := filepath.Join(dir, "hcloud-setup.log")
	file, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		return
	}
	defer file.Close()
	line := fmt.Sprintf("%s %s\r\n", time.Now().Format("2006-01-02 15:04:05.000"), strings.ReplaceAll(text, "\n", " | "))
	_, _ = file.WriteString(line)
}

func showError(text string) {
	user32 := syscall.NewLazyDLL("user32.dll")
	messageBox := user32.NewProc("MessageBoxW")
	title, titleErr := syscall.UTF16PtrFromString("华为云命令行工具安装程序")
	body, bodyErr := syscall.UTF16PtrFromString(text)
	if titleErr != nil || bodyErr != nil {
		return
	}
	_, _, _ = messageBox.Call(0, uintptr(unsafe.Pointer(body)), uintptr(unsafe.Pointer(title)), 0x10)
}
