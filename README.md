# hcloud-cli-storage

HWCloudCLI 尚未开源，也还没有官方发布仓库。本仓库暂时做两件事：

- 在 `debug/` 中存放当前调试用的两份 Linux 二进制
- 预开发一键安装脚本。临时发布版本发到本仓库的 GitHub Releases

安装脚本用 `-v` 或 `--version` 选择版本，按架构下载压缩包，解压出顶层可执行文件，安装到 `/usr/local/bin`。

## 目录

```text
.
├── install.sh
├── scripts/
│   └── gen-sha256sums.sh
└── debug/
    ├── huaweicloud-cli-linux-amd64.tar.gz
    └── huaweicloud-cli-linux-arm64.tar.gz
```

`debug/` 放这两个压缩包。解压后顶层应直接是可执行文件 `hcloud`。仓库里不存放版本目录。提交到这里的单个文件需小于 GitHub 约 100MB 的限制。

## GitHub Releases

临时发布版本创建为本仓库的 Release，标签即版本号（例如 `v0.1.0`）。每个 Release 上传同名附件：

- `hcloud-cli-linux-amd64.tgz`
- `hcloud-cli-linux-arm64.tgz`

压缩包解压后，当前目录下应直接得到可执行文件 `hcloud`。各 Release 的附件名保持一致，这样默认的 `latest` 和 `-v <标签>` 才能下载到同一文件名。

可选：上传前在附件目录生成校验文件（安装脚本不强制校验）：

```bash
./scripts/gen-sha256sums.sh /path/to/assets
```

## 安装

默认安装最新 Release，目标路径为 `/usr/local/bin/hcloud`。目录不可写时会使用 `sudo`。

```bash
bash install.sh
bash install.sh -v v0.1.0
bash install.sh --version debug
```

远程执行（脚本推送到 `master` 之后）：

```bash
curl -fsSL https://raw.githubusercontent.com/Lance52259/hcloud-cli-storage/master/install.sh | bash
curl -fsSL https://raw.githubusercontent.com/Lance52259/hcloud-cli-storage/master/install.sh | bash -s -- -v debug
```

| 参数 | 说明 | 默认 |
| --- | --- | --- |
| `-h` | 显示帮助 | |
| `-v`, `--version` | `latest`、Release 标签，或 `debug` | `latest` |

`latest` 下载 `releases/latest/download/hcloud-cli-linux-<arch>.tgz`。指定标签时下载 `releases/download/<标签>/` 下的同名文件。`-v debug` 下载 `debug/huaweicloud-cli-linux-<arch>.tar.gz` 并解压出 `hcloud`。

可用环境变量改安装位置或下载根地址：`HCLOUD_INSTALL_DIR`、`HCLOUD_RELEASE_DOWNLOAD_BASE`、`HCLOUD_DEBUG_BASE`。
