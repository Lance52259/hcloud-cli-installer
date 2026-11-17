// Windows 离线安装器。发布时编译为 hcloudSetup-windows-x64-<版本>.exe。
// 构建前把 debug/huaweicloud-cli-windows-amd64.zip 复制到 payload/，并写入版本号与 SHA256：
//
//	HCLOUD_RELEASE_TAG=1.2.0 bash build.sh
package main

import (
	"crypto/sha256"
	_ "embed"
	"encoding/hex"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"unsafe"
)

//go:embed payload/huaweicloud-cli-windows-amd64.zip
var payloadZip []byte

//go:embed scripts/setup.ps1
var setupScript []byte

//go:embed actions/PathRegistry.ps1
var pathRegistry []byte

//go:embed actions/Invoke-Elevated.ps1
var invokeElevated []byte

var releaseTag = ""
var payloadSHA256 = ""

func main() {
	os.Exit(run())
}

func run() int {
	tag := strings.TrimSpace(releaseTag)
	sum := strings.ToLower(strings.TrimSpace(payloadSHA256))
	if tag == "" || sum == "" {
		showError("安装器未写入版本号。")
		return 1
	}
	digest := sha256.Sum256(payloadZip)
	if hex.EncodeToString(digest[:]) != sum {
		showError("安装包校验失败，无法启动安装程序。")
		return 1
	}

	root, err := os.MkdirTemp("", "hcloud-setup-")
	if err != nil {
		showError("无法准备安装程序。\n" + err.Error())
		return 1
	}
	defer os.RemoveAll(root)
	archive := filepath.Join(root, "huaweicloud-cli-windows-amd64.zip")
	script := filepath.Join(root, "setup.ps1")
	if writeFile(archive, payloadZip) != nil ||
		writeFile(script, setupScript) != nil ||
		writeFile(filepath.Join(root, "actions", "PathRegistry.ps1"), pathRegistry) != nil ||
		writeFile(filepath.Join(root, "actions", "Invoke-Elevated.ps1"), invokeElevated) != nil {
		showError("无法准备安装程序。")
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
	command := exec.Command(powershell,
		"-NoProfile",
		"-STA",
		"-ExecutionPolicy", "Bypass",
		"-File", script,
		"-Archive", archive,
		"-Version", tag,
		"-Sha256", sum,
	)
	command.Dir = root
	output, err := command.CombinedOutput()
	if err == nil {
		return 0
	}
	detail := strings.TrimSpace(string(output))
	if detail == "" {
		detail = err.Error()
	}
	showError("无法启动安装程序。\n" + detail)
	if exitErr, ok := err.(*exec.ExitError); ok {
		return exitErr.ExitCode()
	}
	return 1
}

func writeFile(path string, content []byte) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	return os.WriteFile(path, content, 0o644)
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
