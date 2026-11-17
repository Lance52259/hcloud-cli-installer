#!/usr/bin/env bash
# 在 macOS 上生成离线安装包。
# 用法：HCLOUD_RELEASE_TAG=1.2.0 bash installer/macos/pkg/build.sh
# 产物在仓库 dist/ 下，文件名带版本号。签名和公证不在本脚本内完成。

set -euo pipefail

if [ "$(uname -s)" != "Darwin" ]; then
  printf '请在 macOS 上运行本脚本。当前系统没有 pkgbuild 和 hdiutil。\n' >&2
  exit 1
fi

tag=${HCLOUD_RELEASE_TAG:-}
if [[ ! "$tag" =~ ^[A-Za-z0-9._+-]+$ ]]; then
  printf '需要有效的 HCLOUD_RELEASE_TAG，例如 1.2.0。\n' >&2
  exit 1
fi

pkg_dir=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$pkg_dir/../../.." && pwd)
dist="$repo/dist"
arm_src="$repo/debug/huaweicloud-cli-darwin-arm64.tar.gz"
x64_src="$repo/debug/huaweicloud-cli-darwin-amd64.tar.gz"

file_sha256() {
  shasum -a 256 "$1" | awk '{ print $1 }'
}

build_variant() {
  local variant=$1
  local archs=$2
  shift 2
  local stage scripts component welcome distribution image_root sums
  stage=$(mktemp -d)
  scripts="$stage/scripts"
  mkdir -p "$scripts" "$dist"
  cp "$pkg_dir/scripts/postinstall" "$scripts/postinstall"
  chmod 755 "$scripts/postinstall"
  printf '%s\n' "$variant" >"$scripts/variant"
  printf '%s\n' "$tag" >"$scripts/version"
  : >"$scripts/SHA256SUMS"
  local source name
  for source in "$@"; do
    name=$(basename "$source")
    cp "$source" "$scripts/$name"
    printf '%s  %s\n' "$(file_sha256 "$source")" "$name" >>"$scripts/SHA256SUMS"
  done

  component="$stage/hcloud-component.pkg"
  pkgbuild \
    --nopayload \
    --identifier com.huaweicloud.hcloud \
    --version "$tag" \
    --install-location / \
    --scripts "$scripts" \
    "$component"

  welcome="$stage/welcome.html"
  sed "s/__VERSION__/${tag}/g" "$pkg_dir/welcome.html" >"$welcome"
  distribution="$stage/distribution.xml"
  sed -e "s/__VERSION__/${tag}/g" -e "s/__ARCHS__/${archs}/g" "$pkg_dir/distribution.xml" >"$distribution"
  mkdir -p "$stage/resources"
  cp "$welcome" "$stage/resources/welcome.html"

  local pkg_name="hcloudsetup-darwin-${variant}-${tag}.pkg"
  local dmg_name="hcloudsetup-darwin-${variant}-${tag}.dmg"
  productbuild \
    --distribution "$distribution" \
    --resources "$stage/resources" \
    --package-path "$stage" \
    "$dist/$pkg_name"

  image_root="$stage/image"
  mkdir -p "$image_root"
  cp "$dist/$pkg_name" "$image_root/"
  rm -f "$dist/$dmg_name"
  hdiutil create \
    -volname "华为云命令行工具安装程序" \
    -srcfolder "$image_root" \
    -ov \
    -format UDZO \
    "$dist/$dmg_name"
  rm -rf "$stage"
  printf '已生成 %s\n' "$dist/$pkg_name"
  printf '已生成 %s\n' "$dist/$dmg_name"
}

missing=0
if [ ! -f "$arm_src" ]; then
  printf '缺少 %s\n' "$arm_src" >&2
  missing=1
fi
if [ ! -f "$x64_src" ]; then
  printf '缺少 %s\n' "$x64_src" >&2
  missing=1
fi
if [ "$missing" -ne 0 ]; then
  exit 1
fi

build_variant arm64 arm64 "$arm_src"
build_variant x64 x86_64 "$x64_src"
build_variant universal "x86_64,arm64" "$arm_src" "$x64_src"
