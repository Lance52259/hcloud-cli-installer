#!/usr/bin/env bash
# 为目录中的安装包生成 SHA256SUMS。
# 只收录该目录下一层的 .tar.gz、.tgz 和 .zip，不进入子目录。
# 结果写到同一目录的 SHA256SUMS，每行是 "<sha256>  <文件名>"。
# 发布 workflow 按同样格式为实际上传的压缩包生成 Release 附件。
set -euo pipefail

usage() {
  cat <<'EOF'
用法: gen-sha256sums.sh <目录>

为该目录中的 .tar.gz、.tgz 和 .zip 生成 SHA256SUMS。
EOF
}

if [[ $# -eq 1 && ( "$1" == "-h" || "$1" == "--help" ) ]]; then
  usage
  exit 0
fi

if [[ $# -ne 1 ]]; then
  usage >&2
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
archives=()
for pattern in '*.tar.gz' '*.tgz' '*.zip'; do
  for path in "$dir"/$pattern; do
    archives+=("$(basename -- "$path")")
  done
done

if [[ ${#archives[@]} -eq 0 ]]; then
  echo "目录中没有 .tar.gz、.tgz 或 .zip: $dir" >&2
  exit 1
fi

mapfile -t archives < <(printf '%s\n' "${archives[@]}" | sort)

(
  cd "$dir"
  sha256sum -- "${archives[@]}"
) >"$dir/SHA256SUMS"

echo "已写入 $dir/SHA256SUMS"
