#!/bin/bash
# 开发时可以直接运行的 macOS 向导。
# 发给用户的安装包由 pkg/build.sh 生成，安装过程不启动本脚本。

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
