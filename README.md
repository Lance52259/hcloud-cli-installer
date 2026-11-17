# hcloud-cli-installer

HWCloudCLI 尚未开源，也还没有官方发布仓库。本仓库暂时做两件事：

- 在 `debug/` 中存放当前调试用的 Linux、Windows 与 macOS 安装包
- 预开发一键安装脚本。临时发布版本发到本仓库的 GitHub Releases

`install.sh` 用 `-v` 或 `--version` 选择版本，下载对应的 Linux 压缩包并安装到 `/usr/local/bin/hcloud`。Windows 和 macOS 使用 Release 里的离线安装器，安装过程不访问网络。

## 目录

```text
.
├── .github/
│   └── workflows/
│       └── release-assets.yml
├── docs/
│   └── offline-installer-design.md
├── installer/
│   ├── windows/
│   │   └── build.sh
│   └── macos/
│       └── pkg/
│           └── build.sh
├── install.sh
├── scripts/
│   └── gen-sha256sums.sh
└── debug/
    ├── huaweicloud-cli-linux-amd64.tar.gz
    ├── huaweicloud-cli-linux-arm64.tar.gz
    ├── huaweicloud-cli-windows-amd64.zip
    ├── huaweicloud-cli-darwin-amd64.tar.gz
    └── huaweicloud-cli-darwin-arm64.tar.gz
```

`debug/` 放这些压缩包，文件名不带版本号。包的顶层要包含可执行文件，也可以同时放说明文件。Linux 和 macOS 包的可执行文件是 `hcloud`，Windows 包是 `hcloud.exe`。仓库里不存放版本目录。提交到这里的单个文件需小于 GitHub 约 100MB 的限制。

## GitHub Releases

临时发布版本创建为本仓库的 Release，标签即版本号（例如 `1.2.0`，不加 `v` 前缀）。发布 Release 后，`.github/workflows/release-assets.yml` 会把该标签提交里的 Linux 压缩包改成带版本号的文件名后上传，并按 `scripts/gen-sha256sums.sh` 的格式生成 `SHA256SUMS`。同一流程把 Windows x64 压缩包写入 `hcloudSetup-windows-x64-<版本>.exe`，把 macOS 压缩包写入三个架构的 pkg 和 dmg。安装器不访问网络。当前不发布 Windows ARM64 安装器。

Release 当前各版本包含以下附件：

- `SHA256SUMS`
- `hcloud-linux-amd64-x.xx.xx.tar.gz`
- `hcloud-linux-arm64-x.xx.xx.tar.gz`
- `hcloudSetup-windows-x64-x.xx.xx.exe`
- `hcloudsetup-darwin-arm64-x.xx.xx.pkg`
- `hcloudsetup-darwin-arm64-x.xx.xx.dmg`
- `hcloudsetup-darwin-x64-x.xx.xx.pkg`
- `hcloudsetup-darwin-x64-x.xx.xx.dmg`
- `hcloudsetup-darwin-universal-x.xx.xx.pkg`
- `hcloudsetup-darwin-universal-x.xx.xx.dmg`

`SHA256SUMS` 和安装器都不保存在仓库里。`SHA256SUMS` 只覆盖上面两个 Linux 压缩包，文件名使用带版本号的发布名。workflow 只处理该标签所指向的提交；缺少对应的 `debug/` 压缩包时，相关上传会失败。

本地要对一组压缩包生成同样格式的校验文件时：

```bash
./scripts/gen-sha256sums.sh /path/to/assets
```

## 安装

Linux 用 `install.sh` 安装。目标路径为 `/usr/local/bin/hcloud`，目录不可写时会使用 `sudo`。不带参数时先查询最新 Release 标签，再下载 `hcloud-linux-<arch>-<标签>.tar.gz`，并用同一 Release 的 `SHA256SUMS` 校验。

```bash
bash install.sh
bash install.sh -v x.xx.xx
bash install.sh --version latest
```

从 `master` 上的脚本远程执行：

```bash
# 下载最新版本的 CLI
curl -fsSL https://raw.githubusercontent.com/Lance52259/hcloud-cli-installer/master/install.sh | bash

# 下载指定版本的 CLI
curl -fsSL https://raw.githubusercontent.com/Lance52259/hcloud-cli-installer/master/install.sh | bash -s -- -v x.xx.xx
```

| 参数 | 说明 | 默认 |
| --- | --- | --- |
| `-h` | 显示帮助 | |
| `-v`, `--version` | `latest`、Release 标签 | `latest` |

Windows 运行 Release 中的 `hcloudSetup-windows-x64-<版本>.exe`。它只安装这个版本，默认目录是 `%LOCALAPPDATA%\hcloud`。macOS 运行对应架构的 `hcloudsetup-darwin-<架构>-<版本>.pkg`，程序安装到 `/usr/local/bin/hcloud`。这两个安装器都不访问网络。

可用环境变量改 Linux 安装位置或 Release 根地址：`HCLOUD_INSTALL_DIR`、`HCLOUD_RELEASE_DOWNLOAD_BASE`。
