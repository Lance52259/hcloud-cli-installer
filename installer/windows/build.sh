#!/usr/bin/env bash
# 把 debug 中的 Windows x64 压缩包写入安装器。
# 用法：HCLOUD_RELEASE_TAG=1.2.0 bash installer/windows/build.sh
set -euo pipefail

tag=${HCLOUD_RELEASE_TAG:-}
if [[ ! "$tag" =~ ^[A-Za-z0-9._+-]+$ ]]; then
  printf '需要有效的 HCLOUD_RELEASE_TAG，例如 1.2.0。\n' >&2
  exit 1
fi

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
source="$repo/debug/huaweicloud-cli-windows-amd64.zip"
if [[ ! -f "$source" ]]; then
  printf '缺少 %s\n' "$source" >&2
  exit 1
fi

hash=$(sha256sum "$source" | awk '{print $1}')
mkdir -p "$here/payload"
cp "$source" "$here/payload/huaweicloud-cli-windows-amd64.zip"

(
  cd "$here"
  CGO_ENABLED=0 GOOS=windows GOARCH=amd64 go build \
    -ldflags "-H windowsgui -s -w -X main.releaseTag=${tag} -X main.payloadSHA256=${hash}" \
    -o "hcloudSetup-windows-x64-${tag}.exe" .
)

printf '已生成 %s\n' "$here/hcloudSetup-windows-x64-${tag}.exe"
