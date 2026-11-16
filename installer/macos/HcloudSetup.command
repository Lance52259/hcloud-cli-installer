#!/bin/bash
# 华为云命令行工具的 macOS 图形安装器。
# 安装器不包含 CLI 本体。
# 发给用户的启动文件是 huaweicloud-cli-setup-macos.pkg，由 pkg/build.sh 在 macOS 上生成。
# 本脚本是向导入口，开发时可以直接运行；打进 .app 后从 Contents/MacOS 启动。

set -euo pipefail

if [ -d "$(dirname "$0")/../Resources/actions" ]; then
  ROOT=$(cd "$(dirname "$0")/../Resources" && pwd)
else
  ROOT=$(cd "$(dirname "$0")" && pwd)
fi
# shellcheck disable=SC1091
source "$ROOT/actions/common.sh"
# shellcheck disable=SC1091
source "$ROOT/actions/release.sh"
# shellcheck disable=SC1091
source "$ROOT/actions/path.sh"
# shellcheck disable=SC1091
source "$ROOT/actions/elevate.sh"
# shellcheck disable=SC1091
source "$ROOT/detect/find-hcloud.sh"
# shellcheck disable=SC1091
source "$ROOT/actions/setup.sh"
# shellcheck disable=SC1091
source "$ROOT/ui/wizard.sh"

wizard_main "$@"
