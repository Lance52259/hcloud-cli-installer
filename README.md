# hcloud-cli-storage

HWCloudCLI 尚未开源，也还没有官方发布仓库。本仓库暂时做两件事：

- 在 `debug/` 中存放当前调试用的 Linux 与 Windows 安装包
- 预开发一键安装脚本。临时发布版本发到本仓库的 GitHub Releases

安装脚本用 `-v` 或 `--version` 选择版本，按系统和架构下载压缩包。Linux 安装到 `/usr/local/bin/hcloud`。Windows 在 Git Bash 中运行，默认安装到 `%LOCALAPPDATA%\hcloud\hcloud.exe`。

## 目录

```text
.
├── .github/
│   └── workflows/
│      └── release-assets.yml
├── install.sh
├── scripts/
│   └── gen-sha256sums.sh
└── debug/
    ├── huaweicloud-cli-linux-amd64.tar.gz
    ├── huaweicloud-cli-linux-arm64.tar.gz
    └── huaweicloud-cli-windows-amd64.zip
```

`debug/` 放这三个压缩包。包的顶层要包含可执行文件，也可以同时放说明文件。Linux 包的可执行文件是 `hcloud`，Windows 包是 `hcloud.exe`。仓库里不存放版本目录。提交到这里的单个文件需小于 GitHub 约 100MB 的限制。

## GitHub Releases

临时发布版本创建为本仓库的 Release，标签即版本号（例如 `1.0.0`）。发布 Release 后，`.github/workflows/release-assets.yml` 会把该标签提交里 `debug/` 的安装包上传为同名附件，并按 `scripts/gen-sha256sums.sh` 的格式为这些实际上传的压缩包生成 `SHA256SUMS`，再作为同名附件上传：

- `huaweicloud-cli-linux-amd64.tar.gz`
- `huaweicloud-cli-linux-arm64.tar.gz`
- `huaweicloud-cli-windows-amd64.zip`
- `SHA256SUMS`

压缩包附件和 `debug/` 中的文件同名。`SHA256SUMS` 不保存在仓库里，只存在于 Release。各 Release 都要使用上面的压缩包文件名，默认的 `latest` 和 `-v <标签>` 才会下载到同一个路径。标签必须和 Release 的标签完全一致，例如 `1.2.0`，不要额外加上 `v` 前缀。workflow 只处理该标签所指向的提交；该提交的 `debug/` 里没有的包不会上传，也不会写入校验文件。

本地要对一组压缩包生成同样格式的校验文件时：

```bash
./scripts/gen-sha256sums.sh /path/to/assets
```

## 安装

默认安装最新 Release。Linux 目标路径为 `/usr/local/bin/hcloud`，目录不可写时会使用 `sudo`。Windows 在 Git Bash 中默认安装到 `%LOCALAPPDATA%\hcloud\hcloud.exe`；读不到 `LOCALAPPDATA` 时改为 `~/hcloud/hcloud.exe`。安装成功后会把该目录写入用户 PATH。已经打开的 PowerShell 或 CMD 窗口仍使用旧 PATH，需要新开一个窗口后再执行 `hcloud version`。

```bash
bash install.sh
bash install.sh -v 1.2.0
bash install.sh --version latest
```

从 `master` 上的脚本远程执行：

```bash
# 下载最新版本的CLI
curl -fsSL https://raw.githubusercontent.com/Lance52259/hcloud-cli-storage/master/install.sh | bash

# 下载指定版本的CLI
curl -fsSL https://raw.githubusercontent.com/Lance52259/hcloud-cli-storage/master/install.sh | bash -s -- -v 1.2.0
```

| 参数 | 说明 | 默认 |
| --- | --- | --- |
| `-h` | 显示帮助 | |
| `-v`, `--version` | `latest`、Release 标签 | `latest` |

不带参数和 `-v latest` 都下载 `releases/latest/download/` 下当前系统的附件。`-v <标签>` 下载 `releases/download/<标签>/` 下的同名文件。Linux 文件名是 `huaweicloud-cli-linux-<arch>.tar.gz`，Windows 是 `huaweicloud-cli-windows-amd64.zip`。

Windows 请在 Git Bash 中执行上面的命令。当前没有 Windows arm64 安装包。

可用环境变量改安装位置或 Release 根地址：`HCLOUD_INSTALL_DIR`、`HCLOUD_RELEASE_DOWNLOAD_BASE`。
