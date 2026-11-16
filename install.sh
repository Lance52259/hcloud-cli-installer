#!/usr/bin/env bash
# -v / --version 选择版本（默认 latest）。
# Linux 安装到 /usr/local/bin/hcloud。
# Windows（Git Bash / MSYS / Cygwin）安装到 %LOCALAPPDATA%\hcloud\hcloud.exe。
#
# 调试包和 Release 附件使用同一文件名：
#   Linux:   huaweicloud-cli-linux-<arch>.tar.gz
#   Windows: huaweicloud-cli-windows-amd64.zip
set -euo pipefail

RELEASE_BASE="${HCLOUD_RELEASE_DOWNLOAD_BASE:-https://github.com/Lance52259/hcloud-cli-storage/releases}"
DEBUG_BASE="${HCLOUD_DEBUG_BASE:-https://raw.githubusercontent.com/Lance52259/hcloud-cli-storage/master/debug}"
INSTALL_DIR="${HCLOUD_INSTALL_DIR:-/usr/local/bin}"
BIN_NAME="hcloud"

show_help() {
  cat <<'EOF'

HWCloudCLI installer

-h                     Show this help and exit
-v, --version VERSION  Version to install. Default is latest.
                       "debug" installs the current build from debug/.

Linux supports amd64 and arm64. Windows supports amd64.
On Windows, run this script from Git Bash.

Examples:
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
    if [[ "$OS_FAMILY" == "windows" ]]; then
      abort "cannot write to ${INSTALL_DIR}."
    fi
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
  if [[ "$OS_FAMILY" == "windows" ]]; then
    add_windows_user_path
  fi
}

add_windows_user_path() {
  local dir_win ps1
  if ! command -v powershell.exe >/dev/null 2>&1 || ! command -v cygpath >/dev/null 2>&1; then
    printf 'Open a new terminal, then run: hcloud version\n'
    return
  fi
  dir_win=$(cygpath -w "$INSTALL_DIR")
  ps1="${workdir}/add-path.ps1"
  cat >"$ps1" <<'EOF'
param([Parameter(Mandatory = $true)][string]$Dir)
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($null -eq $userPath) { $userPath = '' }
$normalized = $Dir.TrimEnd('\')
$exists = $false
foreach ($part in ($userPath -split ';')) {
  if ($part.TrimEnd('\') -ieq $normalized) {
    $exists = $true
    break
  }
}
if (-not $exists) {
  if ($userPath -eq '') {
    $updated = $Dir
  } else {
    $updated = $userPath.TrimEnd(';') + ';' + $Dir
  }
  [Environment]::SetEnvironmentVariable('Path', $updated, 'User')
  Write-Output "Added to user PATH: $Dir"
} else {
  Write-Output "User PATH already contains: $Dir"
}
Write-Output "This window still has the old PATH."
Write-Output "Open a new PowerShell window and run: hcloud version"
Write-Output "Or run this in the current window:"
Write-Output ('  $env:Path += ";' + $Dir + '"')
EOF
  powershell.exe -NoProfile -NonInteractive -File "$(cygpath -w "$ps1")" -Dir "$dir_win"
}

extract_zip() {
  local archive_path=$1
  local dest=$2
  if command -v unzip >/dev/null 2>&1; then
    unzip -oq "$archive_path" -d "$dest"
    return
  fi
  if command -v powershell.exe >/dev/null 2>&1 && command -v cygpath >/dev/null 2>&1; then
    powershell.exe -NoProfile -NonInteractive -Command "Expand-Archive -Force -LiteralPath '$(cygpath -w "$archive_path")' -DestinationPath '$(cygpath -w "$dest")'"
    return
  fi
  abort "unzip is required to extract the Windows archive."
}

install_archive() {
  local archive_url=$1
  local archive_name=$2
  fetch "$archive_url" "${workdir}/${archive_name}"
  case "$archive_name" in
    *.zip) extract_zip "${workdir}/${archive_name}" "$workdir" ;;
    *) tar zxf "${workdir}/${archive_name}" -C "$workdir" ;;
  esac
  if [[ ! -f "${workdir}/${BIN_NAME}" ]]; then
    abort "archive has no top-level ${BIN_NAME} executable."
  fi
  chmod +x "${workdir}/${BIN_NAME}"
  place_binary "${workdir}/${BIN_NAME}"
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
  Linux) OS_FAMILY="linux" ;;
  MINGW*|MSYS*|CYGWIN*) OS_FAMILY="windows" ;;
  *) abort "only Linux and Windows are supported." ;;
esac

machine=$(uname -m)
case "$machine" in
  x86_64|amd64) ARCH="amd64" ;;
  aarch64|arm64)
    if [[ "$OS_FAMILY" == "windows" ]]; then
      abort "only amd64 is supported on Windows, found: ${machine}"
    fi
    ARCH="arm64"
    ;;
  *) abort "only amd64 and arm64 are supported, found: ${machine}" ;;
esac

if [[ "$OS_FAMILY" == "windows" ]]; then
  BIN_NAME="hcloud.exe"
  if [[ -z "${HCLOUD_INSTALL_DIR:-}" ]]; then
    if [[ -n "${LOCALAPPDATA:-}" ]] && command -v cygpath >/dev/null 2>&1; then
      INSTALL_DIR="$(cygpath -u "$LOCALAPPDATA")/hcloud"
    else
      INSTALL_DIR="${HOME}/hcloud"
    fi
  fi
fi

if [[ "$VERSION" != "latest" && "$VERSION" != "debug" && ! "$VERSION" =~ ^[A-Za-z0-9._+-]+$ ]]; then
  abort "invalid version: ${VERSION}"
fi

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

if [[ "$OS_FAMILY" == "windows" ]]; then
  if [[ "$VERSION" == "debug" ]]; then
    archive="huaweicloud-cli-windows-${ARCH}.zip"
    archive_url="${DEBUG_BASE}/${archive}"
  else
    archive="huaweicloud-cli-windows-${ARCH}.zip"
    if [[ "$VERSION" == "latest" ]]; then
      archive_url="${RELEASE_BASE}/latest/download/${archive}"
    else
      archive_url="${RELEASE_BASE}/download/${VERSION}/${archive}"
    fi
  fi
elif [[ "$VERSION" == "debug" ]]; then
  archive="huaweicloud-cli-linux-${ARCH}.tar.gz"
  archive_url="${DEBUG_BASE}/${archive}"
else
  archive="huaweicloud-cli-linux-${ARCH}.tar.gz"
  if [[ "$VERSION" == "latest" ]]; then
    archive_url="${RELEASE_BASE}/latest/download/${archive}"
  else
    archive_url="${RELEASE_BASE}/download/${VERSION}/${archive}"
  fi
fi

printf 'Installing HWCloudCLI (%s, %s/%s)...\n' "$VERSION" "$OS_FAMILY" "$ARCH"
install_archive "$archive_url" "$archive"
