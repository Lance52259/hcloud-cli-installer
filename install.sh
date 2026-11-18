#!/usr/bin/env bash
# 在 Linux 上安装华为云命令行工具。
# -v / --version 选择 Release 标签，默认 latest。
# 安装到 /usr/local/bin/hcloud。
# 发布文件名是 hcloud-linux-<arch>-<标签>.tar.gz。
# 状态行走 stdout，错误走 stderr。仅在全部步骤完成后打印 Successfully。
set -euo pipefail

export LC_ALL=C

RELEASE_BASE="${HCLOUD_RELEASE_DOWNLOAD_BASE:-https://github.com/Lance52259/hcloud-cli-installer/releases}"
INSTALL_DIR="${HCLOUD_INSTALL_DIR:-/usr/local/bin}"
BIN_NAME="hcloud"

say() {
  printf '==> %s\n' "$*"
}

abort() {
  local first=1
  local line
  for line in "$@"; do
    if [[ "$first" -eq 1 ]]; then
      printf 'Error: %s\n' "$line" >&2
      first=0
    else
      printf '%s\n' "$line" >&2
    fi
  done
  exit 1
}

show_help() {
  cat <<'EOF'

HWCloudCLI installer

-h, --help             Show this help and exit
-v, --version VERSION  Release tag to install. Default is latest.

Linux supports amd64 and arm64.
Windows and macOS use the offline installers from the same release.

Environment:
  HCLOUD_INSTALL_DIR             Install directory. Default: /usr/local/bin
  HCLOUD_RELEASE_DOWNLOAD_BASE   Release download root

Examples:
  install.sh
  install.sh -v 1.2.0
  install.sh --version latest

EOF
}

need_value() {
  local flag=$1
  local value=${2:-}
  if [[ -z "$value" || "$value" == -* ]]; then
    abort "${flag} requires a value."
  fi
}

require_cmd() {
  local cmd=$1
  local hint=$2
  if ! command -v "$cmd" >/dev/null 2>&1; then
    abort "$hint"
  fi
}

curl_common() {
  curl -fsSL --connect-timeout 30 --retry 3 --retry-delay 1 "$@" || return $?
}

run_or_abort() {
  local message=$1
  shift
  local err
  if ! err=$("$@" 2>&1); then
    if [[ -n "$err" ]]; then
      abort "$message" "$err"
    fi
    abort "$message"
  fi
}

download() {
  local url=$1
  local dest=$2
  local name err
  name=$(basename -- "$url")
  say "Downloading ${url}"
  if ! err=$(curl_common -o "$dest" "$url" 2>&1); then
    rm -f -- "$dest"
    if [[ -n "$err" ]]; then
      abort "failed to download ${name}." "$err"
    fi
    abort "failed to download ${name}."
  fi
  if [[ ! -s "$dest" ]]; then
    rm -f -- "$dest"
    abort "downloaded file is empty: ${name}."
  fi
}

file_sha256() {
  local path=$1
  local sum
  if command -v sha256sum >/dev/null 2>&1; then
    sum=$(sha256sum "$path" | awk '{ print $1 }') || abort "failed to calculate SHA256 for $(basename -- "$path")."
  elif command -v shasum >/dev/null 2>&1; then
    sum=$(shasum -a 256 "$path" | awk '{ print $1 }') || abort "failed to calculate SHA256 for $(basename -- "$path")."
  else
    abort "sha256sum or shasum is required."
  fi
  printf '%s' "$sum" | tr '[:upper:]' '[:lower:]'
}

resolve_latest_tag() {
  local base owner repo api body tag err
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
  if ! body=$(curl_common \
    -H 'Accept: application/vnd.github+json' \
    -H 'User-Agent: hcloud-cli-installer' \
    "$api" 2>&1); then
    err=$body
    if printf '%s' "$err" | grep -Eq '403|429|rate limit'; then
      abort "failed to query the latest release." "$err" "Pass -v with a release tag and try again."
    fi
    if [[ -n "$err" ]]; then
      abort "failed to query the latest release." "$err"
    fi
    abort "failed to query the latest release."
  fi
  tag=$(printf '%s' "$body" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
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
  expected=$(awk -v name="$name" '
    {
      file = $2
      sub(/\r$/, "", file)
      sub(/^\*/, "", file)
      if (file == name) {
        print tolower($1)
        exit
      }
    }
  ' "$sums_path")
  if [[ -z "$expected" ]]; then
    abort "SHA256SUMS does not list ${name}."
  fi
  if [[ ! "$expected" =~ ^[0-9a-f]{64}$ ]]; then
    abort "SHA256SUMS has an invalid checksum for ${name}."
  fi
  actual=$(file_sha256 "$archive_path")
  if [[ "$actual" != "$expected" ]]; then
    abort "SHA256 mismatch for ${name}." "expected: ${expected}" "actual:   ${actual}"
  fi
}

reject_unsafe_paths() {
  local archive_path=$1
  local list=$2
  local err detail entry part rest
  if ! err=$(tar -tzf "$archive_path" 2>&1 >"$list"); then
    detail=$(printf '%s\n' "$err" | sed -n '/[^[:space:]]/p' | head -n 1)
    if [[ -n "$detail" ]]; then
      abort "failed to read $(basename -- "$archive_path")." "$detail"
    fi
    abort "failed to read $(basename -- "$archive_path")."
  fi
  while IFS= read -r entry || [[ -n "$entry" ]]; do
    entry=${entry%$'\r'}
    [[ -z "$entry" ]] && continue
    case "$entry" in
      /*)
        abort "archive contains an unsafe path: ${entry}."
        ;;
    esac
    rest=$entry
    while [[ "$rest" == */* ]]; do
      part=${rest%%/*}
      if [[ "$part" == ".." ]]; then
        abort "archive contains an unsafe path: ${entry}."
      fi
      rest=${rest#*/}
    done
    if [[ "$rest" == ".." ]]; then
      abort "archive contains an unsafe path: ${entry}."
    fi
  done <"$list"
}

place_binary() {
  local src=$1
  local dest="${INSTALL_DIR}/${BIN_NAME}"
  local use_sudo=0
  local probe parent

  probe=$INSTALL_DIR
  while true; do
    if [[ -d "$probe" ]]; then
      if [[ ! -w "$probe" ]]; then
        use_sudo=1
      fi
      break
    fi
    if [[ -e "$probe" ]]; then
      abort "${probe} exists and is not a directory."
    fi
    parent=$(dirname -- "$probe")
    if [[ "$parent" == "$probe" ]]; then
      abort "cannot create ${INSTALL_DIR}."
    fi
    probe=$parent
  done

  say "Installing ${BIN_NAME} to ${dest}"
  if [[ -e "$dest" || -L "$dest" ]]; then
    say "Replacing the existing ${BIN_NAME} executable"
  fi

  if [[ "$use_sudo" -eq 1 ]]; then
    if ! command -v sudo >/dev/null 2>&1; then
      abort "sudo is required to write to ${INSTALL_DIR}."
    fi
    say "sudo is required to write to ${INSTALL_DIR}"
    run_or_abort "failed to create ${INSTALL_DIR}." sudo mkdir -p "$INSTALL_DIR"
    run_or_abort "failed to install ${dest}." sudo cp "$src" "$dest"
    run_or_abort "failed to set permissions on ${dest}." sudo chmod 755 "$dest"
  else
    run_or_abort "failed to create ${INSTALL_DIR}." mkdir -p "$INSTALL_DIR"
    run_or_abort "failed to install ${dest}." cp "$src" "$dest"
    run_or_abort "failed to set permissions on ${dest}." chmod 755 "$dest"
  fi

  case ":${PATH}:" in
    *":${INSTALL_DIR}:"*) ;;
    *)
      say "${INSTALL_DIR} is not listed in PATH"
      ;;
  esac
}

normalize_install_dir() {
  while [[ "$INSTALL_DIR" == */ ]]; do
    INSTALL_DIR=${INSTALL_DIR%/}
  done
  if [[ -z "$INSTALL_DIR" || "$INSTALL_DIR" == "/" ]]; then
    abort "HCLOUD_INSTALL_DIR must be a directory other than /."
  fi
}

VERSION="latest"
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
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
        abort "--version requires a value."
      fi
      shift
      ;;
    *)
      abort "unknown argument: ${1}."
      ;;
  esac
done

normalize_install_dir

kernel=$(uname -s)
case "$kernel" in
  Linux) ;;
  MINGW*|MSYS*|CYGWIN*)
    abort "On Windows, run the offline installer hcloudSetup-windows-x64-<version>.exe from the release."
    ;;
  Darwin)
    abort "On macOS, open the offline installer hcloudsetup-darwin-<arch>-<version>.pkg from the release."
    ;;
  *)
    abort "this script supports Linux only."
    ;;
esac

machine=$(uname -m)
case "$machine" in
  x86_64|amd64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) abort "only amd64 and arm64 are supported, found: ${machine}." ;;
esac

if [[ "$VERSION" != "latest" && ! "$VERSION" =~ ^[A-Za-z0-9._+-]+$ ]]; then
  abort "invalid version: ${VERSION}."
fi

require_cmd curl "curl is required."
require_cmd tar "tar is required."

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

if [[ "$VERSION" == "latest" ]]; then
  say "Resolving latest release"
  VERSION=$(resolve_latest_tag) || exit 1
fi

say "Installing HWCloudCLI ${VERSION} (linux/${ARCH})"

archive="hcloud-linux-${ARCH}-${VERSION}.tar.gz"
archive_url="${RELEASE_BASE%/}/download/${VERSION}/${archive}"
sums_url="${RELEASE_BASE%/}/download/${VERSION}/SHA256SUMS"

download "$archive_url" "${workdir}/${archive}"
download "$sums_url" "${workdir}/SHA256SUMS"

say "Verifying checksum"
verify_archive "${workdir}/${archive}" "${workdir}/SHA256SUMS" "$archive"

say "Extracting ${archive}"
reject_unsafe_paths "${workdir}/${archive}" "${workdir}/archive-files"
run_or_abort "failed to extract ${archive}." tar -xzf "${workdir}/${archive}" -C "$workdir"
if [[ ! -f "${workdir}/${BIN_NAME}" || -L "${workdir}/${BIN_NAME}" || ! -s "${workdir}/${BIN_NAME}" ]]; then
  abort "archive has no top-level ${BIN_NAME} executable."
fi

place_binary "${workdir}/${BIN_NAME}"
say "Successfully installed HWCloudCLI ${VERSION} to ${INSTALL_DIR}/${BIN_NAME}"
