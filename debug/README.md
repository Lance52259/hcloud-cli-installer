当前调试包。只放下面三个压缩包，后续用同名文件覆盖：

- `huaweicloud-cli-linux-amd64.tar.gz`
- `huaweicloud-cli-linux-arm64.tar.gz`
- `huaweicloud-cli-windows-amd64.zip`

Linux 包顶层要包含可执行文件 `hcloud`，Windows 包顶层要包含 `hcloud.exe`。包内还可以有说明文件。临时发布版本不要放在这里，请发布到本仓库的 GitHub Releases。安装这些文件使用 `install.sh -v debug`。
