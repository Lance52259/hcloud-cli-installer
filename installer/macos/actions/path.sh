# 用户 shell 配置和 /etc/paths.d/hcloud。只处理安装器自己写入的条目。

ZSHRC_BEGIN='# >>> hcloud-setup >>>'
ZSHRC_END='# <<< hcloud-setup <<<'
PATHS_D_FILE='/etc/paths.d/hcloud'

choose_path_scope() {
  local dir="$1"
  if dir_is_listed "$dir"; then
    printf 'none'
    return 0
  fi
  if under_home "$dir"; then
    printf 'zshrc'
    return 0
  fi
  printf 'paths.d'
}

path_file_for_scope() {
  case "$1" in
    zshrc) printf '%s' "$HOME/.zshrc" ;;
    paths.d) printf '%s' "$PATHS_D_FILE" ;;
    *) printf '' ;;
  esac
}

zshrc_block() {
  local dir="$1"
  printf '%s\nexport PATH="%s:$PATH"\n%s\n' "$ZSHRC_BEGIN" "$dir" "$ZSHRC_END"
}

write_zshrc_path() {
  local file="$1"
  local dir="$2"
  touch "$file"
  if grep -F "$ZSHRC_BEGIN" "$file" >/dev/null 2>&1; then
    remove_zshrc_path "$file"
  fi
  {
    printf '\n'
    zshrc_block "$dir"
  } >>"$file"
}

remove_zshrc_path() {
  local file="$1"
  [ -f "$file" ] || return 0
  local tmp
  tmp=$(mktemp)
  awk -v begin="$ZSHRC_BEGIN" -v end="$ZSHRC_END" '
    $0 == begin { skip = 1; next }
    $0 == end { skip = 0; next }
    skip != 1 { print }
  ' "$file" >"$tmp"
  mv "$tmp" "$file"
}

paths_d_matches() {
  local dir="$1"
  [ -f "$PATHS_D_FILE" ] || return 1
  local line
  line=$(head -1 "$PATHS_D_FILE" | sed 's/[[:space:]]*$//')
  same_dir "$line" "$dir"
}
