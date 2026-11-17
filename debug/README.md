当前调试包。只放下面这些压缩包，后续用同名文件覆盖：

- `huaweicloud-cli-linux-amd64.tar.gz`
- `huaweicloud-cli-linux-arm64.tar.gz`
- `huaweicloud-cli-windows-amd64.zip`
- `huaweicloud-cli-darwin-amd64.tar.gz`
- `huaweicloud-cli-darwin-arm64.tar.gz`

Linux 和 macOS 包顶层要包含可执行文件 `hcloud`，Windows 包顶层要包含 `hcloud.exe`。包内还可以有说明文件。这里的文件名不带版本号。发布时，Linux 压缩包会改成带版本号的文件名后上传；Windows 和 macOS 压缩包写入对应安装器，不单独上传。安装程序不会直接下载这个目录。
