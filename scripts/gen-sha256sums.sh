#!/usr/bin/env bash
# 为准备上传到 GitHub Releases 的目录生成 SHA256SUMS（只收录该目录下的 .tgz）。
set -euo pipefail

if [[ $# -ne 1 || "$1" == "-h" || "$1" == "--help" ]]; then
  echo "用法: $0 <包含 .tgz 的目录>" >&2
  exit 1
fi

dir=$1
if [[ ! -d "$dir" ]]; then
  echo "目录不存在: $dir" >&2
  exit 1
fi

if ! command -v sha256sum >/dev/null 2>&1; then
  echo "需要 sha256sum" >&2
  exit 1
fi

shopt -s nullglob
files=("$dir"/*.tgz)
if [[ ${#files[@]} -eq 0 ]]; then
  echo "目录中没有 .tgz: $dir" >&2
  exit 1
fi

(
  cd "$dir"
  for archive in *.tgz; do
    sha256sum "$archive"
  done
) >"$dir/SHA256SUMS"

echo "已写入 $dir/SHA256SUMS"
