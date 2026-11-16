# 日志、路径比较和安装记录。供 macOS 安装器各步骤共用。

HCLOUD_LOG_FILE="${TMPDIR:-/tmp}/hcloud-setup.log"

log_line() {
  local message="$1"
  local line
  line="$(date '+%Y-%m-%d %H:%M:%S') ${message}"
  printf '%s\n' "$line" >>"$HCLOUD_LOG_FILE" 2>/dev/null || true
  printf '%s\n' "$line"
}

json_escape() {
  local value="$1"
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  printf '%s' "$value"
}

normalize_dir() {
  local path="$1"
  path=${path%/}
  printf '%s' "$path"
}

path_key() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's:/*$::'
}

same_dir() {
  [ "$(path_key "$1")" = "$(path_key "$2")" ]
}

under_home() {
  local dir home
  dir=$(path_key "$1")
  home=$(path_key "$HOME")
  case "$dir" in
    "$home"|"$home"/*) return 0 ;;
    *) return 1 ;;
  esac
}

dir_is_listed() {
  local dir="$1"
  local entry
  local key
  key=$(path_key "$dir")
  local old_ifs="$IFS"
  IFS=':'
  for entry in $PATH; do
    if [ "$(path_key "$entry")" = "$key" ]; then
      IFS="$old_ifs"
      return 0
    fi
  done
  IFS="$old_ifs"
  local file
  for file in /etc/paths /etc/paths.d/*; do
    [ -f "$file" ] || continue
    while IFS= read -r entry; do
      if [ "$(path_key "$entry")" = "$key" ]; then
        return 0
      fi
    done <"$file"
  done
  return 1
}

json_get() {
  local file="$1"
  local key="$2"
  [ -f "$file" ] || return 0
  osascript -l JavaScript - "$file" "$key" <<'EOF'
function run(argv) {
  ObjC.import("Foundation");
  var text = $.NSString.stringWithContentsOfFileEncodingError(argv[0], $.NSUTF8StringEncoding, null);
  if (!text) return "";
  var value;
  try {
    value = JSON.parse(ObjC.unwrap(text))[argv[1]];
  } catch (error) {
    return "";
  }
  if (value === undefined || value === null) return "";
  return String(value);
}
EOF
}

write_install_record() {
  local file="$1"
  local dir="$2"
  local executable="$3"
  local tag="$4"
  local scope="$5"
  local path_file="$6"
  mkdir -p "$(dirname "$file")"
  cat >"$file" <<EOF
{
  "installDir": "$(json_escape "$dir")",
  "executablePath": "$(json_escape "$executable")",
  "releaseTag": "$(json_escape "$tag")",
  "pathScope": "$(json_escape "$scope")",
  "pathFile": "$(json_escape "$path_file")",
  "installedAt": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}
EOF
}
