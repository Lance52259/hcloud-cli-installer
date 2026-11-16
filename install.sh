#!/usr/bin/env bash
# -v / --version 选择版本（默认 latest）。
# 按架构下载 .tgz，解压出顶层可执行文件，安装到 /usr/local/bin。
#
# 临时发布包（GitHub Releases）:
#   hcloud-cli-linux-<arch>.tgz
# 仓库内调试包（-v debug）:
#   debug/huaweicloud-cli-linux-<arch>.tar.gz
set -euo pipefail

RELEASE_BASE="${HCLOUD_RELEASE_DOWNLOAD_BASE:-https://github.com/Lance52259/hcloud-cli-storage/releases}"
DEBUG_BASE="${HCLOUD_DEBUG_BASE:-https://raw.githubusercontent.com/Lance52259/hcloud-cli-storage/master/debug}"
INSTALL_DIR="${HCLOUD_INSTALL_DIR:-/usr/local/bin}"
BIN_NAME="hcloud"

show_help() {
  cat <<'EOF'

华为云命令行工具安装程序

-h                     显示帮助并退出
-v, --version VERSION  指定版本，默认 latest
                       debug 表示安装本仓库 debug/ 中的当前调试二进制

示例:
  install.sh
  install.sh -v v0.1.0
  install.sh --version debug

EOF
}

abort() {
  printf '%s\n' "$@" >&2
  exit 1
}

need_value() {
  local flag=$1
  local value=${2:-}
  if [[ -z "$value" || "$value" == -* ]]; then
    abort "${flag} 需要一个参数"
  fi
}

VERSION="latest"
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h)
      show_help
      exit 0
      ;;
    -v|--version)
      need_value "$@"
      VERSION=$2
      shift 2
      ;;
    --version=*)
      VERSION=${1#--version=}
      if [[ -z "$VERSION" ]]; then
        abort "--version 需要一个参数"
      fi
      shift
      ;;
    *)
      abort "未知参数: $1"
      ;;
  esac
done

if [[ "$(uname)" != "Linux" ]]; then
  abort "目前仅支持 Linux。"
fi

case "$(uname -m)" in
  x86_64|amd64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) abort "目前仅支持 amd64 与 arm64，检测到: $(uname -m)" ;;
esac

if [[ "$VERSION" != "latest" && "$VERSION" != "debug" && ! "$VERSION" =~ ^[A-Za-z0-9._+-]+$ ]]; then
  abort "版本号无效: ${VERSION}"
fi

fetch() {
  local url=$1
  local dest=$2
  if ! command -v curl >/dev/null 2>&1; then
    abort "需要 curl。"
  fi
  curl -fsSL --retry 3 --retry-delay 1 -o "$dest" "$url" || abort "下载失败: ${url}"
}

place_binary() {
  local src=$1
  local dest="${INSTALL_DIR}/${BIN_NAME}"
  local use_sudo=0

  if [[ -d "$INSTALL_DIR" ]]; then
    if [[ ! -w "$INSTALL_DIR" ]]; then
      use_sudo=1
    fi
  else
    local parent
    parent=$(dirname "$INSTALL_DIR")
    if [[ ! -d "$parent" || ! -w "$parent" ]]; then
      use_sudo=1
    fi
  fi

  if [[ "$use_sudo" -eq 1 ]]; then
    if ! command -v sudo >/dev/null 2>&1; then
      abort "无法写入 ${INSTALL_DIR}，请使用 sudo 重新执行。"
    fi
    sudo mkdir -p "$INSTALL_DIR"
    sudo cp "$src" "$dest"
    sudo chmod 755 "$dest"
  else
    mkdir -p "$INSTALL_DIR"
    cp "$src" "$dest"
    chmod 755 "$dest"
  fi
  printf '已安装: %s\n' "$dest"
}

install_archive() {
  local archive_url=$1
  local archive_name=$2
  fetch "$archive_url" "${workdir}/${archive_name}"
  tar zxf "${workdir}/${archive_name}" -C "$workdir"
  if [[ ! -f "${workdir}/${BIN_NAME}" ]]; then
    abort "压缩包顶层未找到 ${BIN_NAME}。请确认解压后当前目录下直接是可执行文件 ${BIN_NAME}。"
  fi
  chmod +x "${workdir}/${BIN_NAME}"
  place_binary "${workdir}/${BIN_NAME}"
}

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

if [[ "$VERSION" == "debug" ]]; then
  archive="huaweicloud-cli-linux-${ARCH}.tar.gz"
  printf '正在安装 HWCloudCLI（debug，linux/%s）...\n' "$ARCH"
  install_archive "${DEBUG_BASE}/${archive}" "$archive"
  exit 0
fi

archive="hcloud-cli-linux-${ARCH}.tgz"
if [[ "$VERSION" == "latest" ]]; then
  archive_url="${RELEASE_BASE}/latest/download/${archive}"
else
  archive_url="${RELEASE_BASE}/download/${VERSION}/${archive}"
fi

printf '正在安装 HWCloudCLI（%s，linux/%s）...\n' "$VERSION" "$ARCH"
install_archive "$archive_url" "$archive"
