#!/usr/bin/env bash
# 安装 Linux 上的华为云命令行工具。
# -v / --version 选择 Release 标签，默认 latest。
# 安装到 /usr/local/bin/hcloud。
# 发布文件名是 hcloud-linux-<arch>-<标签>.tar.gz。
set -euo pipefail

RELEASE_BASE="${HCLOUD_RELEASE_DOWNLOAD_BASE:-https://github.com/Lance52259/hcloud-cli-installer/releases}"
INSTALL_DIR="${HCLOUD_INSTALL_DIR:-/usr/local/bin}"
BIN_NAME="hcloud"

show_help() {
  cat <<'EOF'

HWCloudCLI installer

-h                     Show this help and exit
-v, --version VERSION  Release tag to install. Default is latest.

Linux supports amd64 and arm64.
Windows and macOS use the offline installers from the same Release.

Examples:
  install.sh
  install.sh -v 1.2.0
  install.sh --version latest

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
    abort "${flag} requires a value"
  fi
}

fetch() {
  local url=$1
  local dest=$2
  if ! command -v curl >/dev/null 2>&1; then
    abort "curl is required."
  fi
  printf 'Downloading %s\n' "$url"
  curl -fsSL --retry 3 --retry-delay 1 -o "$dest" "$url" || abort "download failed: ${url}"
}

file_sha256() {
  local path=$1
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{ print $1 }'
    return
  fi
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{ print $1 }'
    return
  fi
  abort "sha256sum or shasum is required."
}

resolve_latest_tag() {
  local base owner repo api body tag
  base=${RELEASE_BASE%/}
  case "$base" in
    https://github.com/*/*/releases)
      owner=$(printf '%s' "$base" | cut -d/ -f4)
      repo=$(printf '%s' "$base" | cut -d/ -f5)
      ;;
    *)
      abort "cannot resolve latest from ${base}; pass -v with a release tag."
      ;;
  esac
  api="https://api.github.com/repos/${owner}/${repo}/releases/latest"
  body=$(curl -fsSL --retry 3 --retry-delay 1 -H 'Accept: application/vnd.github+json' "$api") \
    || abort "cannot query the latest release."
  tag=$(printf '%s' "$body" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  if [[ ! "$tag" =~ ^[A-Za-z0-9._+-]+$ ]]; then
    abort "invalid latest release tag."
  fi
  printf '%s' "$tag"
}

verify_archive() {
  local archive_path=$1
  local sums_path=$2
  local name=$3
  local expected actual
  expected=$(awk -v name="$name" '$2 == name { print $1; exit }' "$sums_path")
  if [[ -z "$expected" ]]; then
    abort "SHA256SUMS does not list ${name}."
  fi
  actual=$(file_sha256 "$archive_path")
  if [[ "$actual" != "$expected" ]]; then
    abort "SHA256 mismatch for ${name}."
  fi
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
      abort "cannot write to ${INSTALL_DIR}; rerun with sudo."
    fi
    sudo mkdir -p "$INSTALL_DIR"
    sudo cp "$src" "$dest"
    sudo chmod 755 "$dest"
  else
    mkdir -p "$INSTALL_DIR"
    cp "$src" "$dest"
    chmod 755 "$dest"
  fi
  printf 'installed: %s\n' "$dest"
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
        abort "--version requires a value"
      fi
      shift
      ;;
    *)
      abort "unknown argument: $1"
      ;;
  esac
done

kernel=$(uname -s)
case "$kernel" in
  Linux) ;;
  MINGW*|MSYS*|CYGWIN*)
    abort "On Windows, run the offline installer hcloudSetup-windows-x64-<version>.exe from the Release."
    ;;
  Darwin)
    abort "On macOS, open the offline installer hcloudsetup-darwin-<arch>-<version>.pkg from the Release."
    ;;
  *) abort "only Linux is supported by this script." ;;
esac

machine=$(uname -m)
case "$machine" in
  x86_64|amd64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) abort "only amd64 and arm64 are supported, found: ${machine}" ;;
esac

if [[ "$VERSION" != "latest" && ! "$VERSION" =~ ^[A-Za-z0-9._+-]+$ ]]; then
  abort "invalid version: ${VERSION}"
fi
if [[ "$VERSION" == "latest" ]]; then
  VERSION=$(resolve_latest_tag)
fi

archive="hcloud-linux-${ARCH}-${VERSION}.tar.gz"
archive_url="${RELEASE_BASE%/}/download/${VERSION}/${archive}"
sums_url="${RELEASE_BASE%/}/download/${VERSION}/SHA256SUMS"

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

printf 'Installing HWCloudCLI (%s, linux/%s)...\n' "$VERSION" "$ARCH"
fetch "$archive_url" "${workdir}/${archive}"
fetch "$sums_url" "${workdir}/SHA256SUMS"
verify_archive "${workdir}/${archive}" "${workdir}/SHA256SUMS" "$archive"
tar zxf "${workdir}/${archive}" -C "$workdir"
if [[ ! -f "${workdir}/${BIN_NAME}" ]]; then
  abort "archive has no top-level ${BIN_NAME} executable."
fi
chmod +x "${workdir}/${BIN_NAME}"
place_binary "${workdir}/${BIN_NAME}"
