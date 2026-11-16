#!/bin/bash
# 在 macOS 上生成用户打开的安装包。
# 产物：
#   dist/huaweicloud-cli-setup-macos.pkg
#   dist/huaweicloud-cli-setup-macos.dmg
# pkg 是安装器。dmg 只是装有这个 pkg 的磁盘镜像。
# 这两个文件不放入 installer/ 或 debug/。签名和公证不在本脚本内完成。

set -euo pipefail

if [ "$(uname -s)" != "Darwin" ]; then
  printf '请在 macOS 上运行本脚本。当前系统没有 pkgbuild 和 hdiutil。\n' >&2
  exit 1
fi

PKG_DIR=$(cd "$(dirname "$0")" && pwd)
SOURCE=$(cd "$PKG_DIR/.." && pwd)
REPO=$(cd "$SOURCE/../.." && pwd)
DIST="$REPO/dist"
STAGE=$(mktemp -d)
COMPONENT="$STAGE/hcloud-setup-component.pkg"
trap 'rm -rf "$STAGE"' EXIT

app="$STAGE/root/HcloudSetup.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$PKG_DIR/Info.plist" "$app/Contents/Info.plist"
cp "$SOURCE/setup.command" "$app/Contents/MacOS/HcloudSetup"
chmod 755 "$app/Contents/MacOS/HcloudSetup"
cp -R "$SOURCE/actions" "$SOURCE/detect" "$SOURCE/ui" "$app/Contents/Resources/"

chmod 755 "$PKG_DIR/scripts/postinstall"
pkgbuild \
  --root "$STAGE/root" \
  --identifier com.huaweicloud.hcloud.setup \
  --version 1.0.0 \
  --install-location /Applications \
  --scripts "$PKG_DIR/scripts" \
  "$COMPONENT"

mkdir -p "$DIST" "$STAGE/resources"
cp "$PKG_DIR/welcome.html" "$STAGE/resources/welcome.html"
cp "$PKG_DIR/distribution.xml" "$STAGE/distribution.xml"
productbuild \
  --distribution "$STAGE/distribution.xml" \
  --resources "$STAGE/resources" \
  --package-path "$STAGE" \
  "$DIST/huaweicloud-cli-setup-macos.pkg"

image_root="$STAGE/image"
mkdir -p "$image_root"
cp "$DIST/huaweicloud-cli-setup-macos.pkg" "$image_root/"
rm -f "$DIST/huaweicloud-cli-setup-macos.dmg"
hdiutil create \
  -volname "华为云命令行工具安装程序" \
  -srcfolder "$image_root" \
  -ov \
  -format UDZO \
  "$DIST/huaweicloud-cli-setup-macos.dmg"

printf '已生成 %s\n' "$DIST/huaweicloud-cli-setup-macos.pkg"
printf '已生成 %s\n' "$DIST/huaweicloud-cli-setup-macos.dmg"
