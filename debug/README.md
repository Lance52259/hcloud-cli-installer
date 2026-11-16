当前调试包。只放下面三个压缩包，后续用同名文件覆盖：

- `huaweicloud-cli-linux-amd64.tar.gz`
- `huaweicloud-cli-linux-arm64.tar.gz`
- `huaweicloud-cli-windows-amd64.zip`

Linux 包顶层要包含可执行文件 `hcloud`，Windows 包顶层要包含 `hcloud.exe`。包内还可以有说明文件。这里的文件只作为发布来源，发布后由 workflow 上传到 GitHub Releases。安装程序不会直接下载这个目录。
