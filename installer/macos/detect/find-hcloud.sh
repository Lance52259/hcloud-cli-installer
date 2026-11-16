# 探测本机 hcloud。顺序：用户安装记录、系统安装记录、默认目录、PATH。

USER_RECORD="$HOME/Library/Application Support/hcloud/install.json"
SYSTEM_RECORD="/Library/Application Support/hcloud/install.json"

embedded_version() {
  local executable="$1"
  [ -f "$executable" ] || return 1
  local match
  match=$(tail -c 8388608 "$executable" | LC_ALL=C grep -a -o 'util\.CliVersion=[0-9][0-9.]*' | tail -1 || true)
  match=${match#util.CliVersion=}
  printf '%s' "$match" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || return 1
  printf '%s' "$match"
}

command_version() {
  local executable="$1"
  local text number
  text=$(perl -e 'alarm 8; exec @ARGV' "$executable" version 2>/dev/null || true)
  number=$(printf '%s' "$text" | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
  [ -n "$number" ] || return 1
  printf '%s' "$number"
}

hcloud_version() {
  local executable="$1"
  local version
  version=$(embedded_version "$executable" || true)
  if [ -n "$version" ]; then
    printf '%s' "$version"
    return 0
  fi
  command_version "$executable" || true
}

record_executable() {
  local file="$1"
  local executable
  executable=$(json_get "$file" executablePath | tr -d '\r')
  if [ -n "$executable" ] && [ -f "$executable" ]; then
    printf '%s' "$executable"
  fi
}

find_hcloud() {
  local executable=""
  executable=$(record_executable "$USER_RECORD")
  if [ -z "$executable" ]; then
    executable=$(record_executable "$SYSTEM_RECORD")
  fi
  if [ -z "$executable" ] && [ -f /usr/local/bin/hcloud ]; then
    executable=/usr/local/bin/hcloud
  fi
  if [ -z "$executable" ] && [ -f /opt/homebrew/bin/hcloud ]; then
    executable=/opt/homebrew/bin/hcloud
  fi
  if [ -z "$executable" ] && [ -f "$HOME/bin/hcloud" ]; then
    executable="$HOME/bin/hcloud"
  fi
  if [ -z "$executable" ]; then
    local found
    found=$(command -v hcloud 2>/dev/null || true)
    if [ -n "$found" ] && [ -f "$found" ]; then
      executable=$found
    fi
  fi
  if [ -z "$executable" ]; then
    HCLOUD_FOUND=no
    HCLOUD_EXECUTABLE=""
    HCLOUD_INSTALL_DIR=""
    HCLOUD_VERSION=""
    HCLOUD_RECORD_SCOPE=""
    HCLOUD_RECORD_PATH_FILE=""
    HCLOUD_RECORD_TAG=""
    return 0
  fi
  HCLOUD_FOUND=yes
  HCLOUD_EXECUTABLE=$executable
  HCLOUD_INSTALL_DIR=$(dirname "$executable")
  HCLOUD_VERSION=$(hcloud_version "$executable" || true)
  HCLOUD_RECORD_SCOPE=""
  HCLOUD_RECORD_PATH_FILE=""
  HCLOUD_RECORD_TAG=""
  local record
  for record in "$USER_RECORD" "$SYSTEM_RECORD"; do
    local recorded
    recorded=$(record_executable "$record")
    if [ -n "$recorded" ] && same_dir "$recorded" "$executable"; then
      HCLOUD_RECORD_SCOPE=$(json_get "$record" pathScope | tr -d '\r')
      HCLOUD_RECORD_PATH_FILE=$(json_get "$record" pathFile | tr -d '\r')
      HCLOUD_RECORD_TAG=$(json_get "$record" releaseTag | tr -d '\r')
      HCLOUD_INSTALL_DIR=$(json_get "$record" installDir | tr -d '\r')
      [ -n "$HCLOUD_INSTALL_DIR" ] || HCLOUD_INSTALL_DIR=$(dirname "$executable")
      break
    fi
  done
}
