# 向导保持打开，只把需要管理员权限的命令交给系统授权框。

run_root_script() {
  local script="$1"
  local result
  result=$(osascript - "$script" <<'EOF'
on run argv
  try
    do shell script "bash " & quoted form of (item 1 of argv) with administrator privileges
    return "ok"
  on error errMsg number errNum
    return "ERR " & errNum & " " & errMsg
  end try
end run
EOF
)
  result=$(printf '%s' "$result" | tr -d '\r')
  case "$result" in
    ok) return 0 ;;
    ERR\ -128*)
      printf '用户取消了授权。已下载的文件会保留，可以重试。\n' >&2
      return 1
      ;;
    ERR\ *)
      printf '授权操作失败：%s\n' "${result#ERR }" >&2
      return 1
      ;;
    *)
      printf '授权操作失败：%s\n' "$result" >&2
      return 1
      ;;
  esac
}

shell_quote() {
  printf '%q' "$1"
}

write_root_install_script() {
  local file="$1"
  local source="$2"
  local destination="$3"
  local dir="$4"
  local scope="$5"
  local record_source="$6"
  local record_target="$7"
  {
    printf '%s\n' '#!/bin/bash' 'set -euo pipefail'
    printf 'mkdir -p %s\n' "$(shell_quote "$dir")"
    printf 'cp %s %s\n' "$(shell_quote "$source")" "$(shell_quote "$destination")"
    printf 'chmod 755 %s\n' "$(shell_quote "$destination")"
    printf 'xattr -d com.apple.quarantine %s 2>/dev/null || true\n' "$(shell_quote "$destination")"
    if [ "$scope" = "paths.d" ]; then
      printf 'mkdir -p /etc/paths.d\n'
      printf 'printf %%s\\\\n %s > %s\n' "$(shell_quote "$dir")" "$(shell_quote "$PATHS_D_FILE")"
      printf 'chmod 644 %s\n' "$(shell_quote "$PATHS_D_FILE")"
    fi
    if [ -n "$record_target" ]; then
      printf 'mkdir -p %s\n' "$(shell_quote "$(dirname "$record_target")")"
      printf 'cp %s %s\n' "$(shell_quote "$record_source")" "$(shell_quote "$record_target")"
      printf 'chmod 644 %s\n' "$(shell_quote "$record_target")"
    fi
  } >"$file"
  chmod 700 "$file"
}

write_root_remove_script() {
  local file="$1"
  local executable="$2"
  local remove_paths_d="$3"
  local remove_system_record="$4"
  {
    printf '%s\n' '#!/bin/bash' 'set -euo pipefail'
    if [ -n "$executable" ]; then
      printf 'rm -f %s\n' "$(shell_quote "$executable")"
    fi
    if [ "$remove_paths_d" = "yes" ]; then
      printf 'rm -f %s\n' "$(shell_quote "$PATHS_D_FILE")"
    fi
    if [ "$remove_system_record" = "yes" ]; then
      printf 'rm -f %s\n' "$(shell_quote "/Library/Application Support/hcloud/install.json")"
    fi
  } >"$file"
  chmod 700 "$file"
}
