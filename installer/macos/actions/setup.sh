# 安装、更新和卸载。下载留在当前用户进程，受保护位置交给授权短进程。

USER_RECORD="$HOME/Library/Application Support/hcloud/install.json"
SYSTEM_RECORD="/Library/Application Support/hcloud/install.json"

progress() {
  local percent="$1"
  local step="$2"
  local detail="$3"
  HCLOUD_STEP=$step
  printf '%s\n%s\n%s\n' "$percent" "$step" "$detail" >"$HCLOUD_STATUS_FILE"
  if [ -n "$detail" ]; then
    log_line "[$step] $detail"
  else
    log_line "[$step]"
  fi
}

fail_step() {
  HCLOUD_ERROR=$1
  printf '%s' "$HCLOUD_ERROR" >"$HCLOUD_WORK/error.txt"
  log_line "失败步骤：${HCLOUD_STEP:-准备}。$HCLOUD_ERROR"
  exit 1
}

install_hcloud() {
  local version="$1"
  local install_dir="$2"
  local asset archive sums extract marker url sums_link source destination scope path_file
  asset=$(asset_name) || fail_step "当前 Mac 架构不受支持。"
  archive="$HCLOUD_WORK/$asset"
  sums="$HCLOUD_WORK/SHA256SUMS"
  extract="$HCLOUD_WORK/extract"
  marker="$HCLOUD_WORK/version.txt"
  install_dir=$(normalize_dir "$install_dir")
  destination="$install_dir/hcloud"
  scope=$(choose_path_scope "$install_dir")
  path_file=$(path_file_for_scope "$scope")

  progress 5 "确定下载地址" ""
  url=$(asset_url "$version") || fail_step "无法得到下载地址。"
  progress 8 "确定下载地址" "$url"

  local saved=""
  if [ -f "$marker" ]; then
    saved=$(tr -d '[:space:]' <"$marker")
  fi
  if [ -f "$archive" ] && [ "$saved" = "$version" ]; then
    progress 40 "下载安装包" "使用上次已下载的安装包。"
  else
    rm -f "$archive"
    progress 10 "下载安装包" "正在下载安装包。"
    download_file "$url" "$archive" || fail_step "下载安装包失败：$url"
    printf '%s' "$version" >"$marker"
  fi

  progress 55 "校验安装包" "正在检查 SHA256SUMS。"
  sums_link=$(sums_url "$version")
  log_line "校验文件地址 $sums_link"
  local sums_ready=no
  if download_file "$sums_link" "$sums" && sums_file_is_real "$sums"; then
    sums_ready=yes
    log_line "SHA256SUMS 已下载，开始比对哈希。"
  else
    rm -f "$sums"
    log_line "SHA256SUMS 未取得，将跳过校验。"
    sums_ready=no
  fi
  if [ "$sums_ready" = "no" ]; then
    HCLOUD_NOTE="未取得 SHA256SUMS，已跳过校验。"
    printf '%s' "$HCLOUD_NOTE" >"$HCLOUD_WORK/note.txt"
    progress 68 "校验安装包" "$HCLOUD_NOTE"
  else
    local verify_code=0
    verify_sha256 "$archive" "$sums" "$asset" || verify_code=$?
    if [ "$verify_code" -eq 2 ]; then
      rm -f "$archive"
      fail_step "校验失败：安装包的 SHA256 与 SHA256SUMS 不一致。"
    elif [ "$verify_code" -ne 0 ]; then
      HCLOUD_NOTE="SHA256SUMS 中没有 $asset，已跳过校验。"
      printf '%s' "$HCLOUD_NOTE" >"$HCLOUD_WORK/note.txt"
      progress 68 "校验安装包" "$HCLOUD_NOTE"
    else
      HCLOUD_NOTE="已根据 SHA256SUMS 校验安装包。"
      printf '%s' "$HCLOUD_NOTE" >"$HCLOUD_WORK/note.txt"
      progress 68 "校验安装包" "$HCLOUD_NOTE"
    fi
  fi

  progress 74 "解压安装包" "正在解压并取出 hcloud。"
  if ! source=$(extract_hcloud "$archive" "$extract" 2>"$HCLOUD_WORK/extract.err"); then
    fail_step "$(tr '\n' ' ' <"$HCLOUD_WORK/extract.err")"
  fi

  local record_target="" record_source=""
  if under_home "$install_dir"; then
    record_target=""
  else
    record_target=$SYSTEM_RECORD
    record_source="$HCLOUD_WORK/install.json"
    write_install_record "$record_source" "$install_dir" "$destination" "$version" "$scope" "$path_file"
  fi

  local need_root=no
  if [ ! -w "$install_dir" ] && [ ! -w "$(dirname "$install_dir")" ]; then
    need_root=yes
  fi
  if [ -d "$install_dir" ] && [ ! -w "$install_dir" ]; then
    need_root=yes
  fi
  if [ "$scope" = "paths.d" ] || [ -n "$record_target" ]; then
    need_root=yes
  fi

  if [ "$need_root" = "yes" ]; then
    progress 82 "请求授权" "正在请求授权。向导会保持打开。"
    local root_script="$HCLOUD_WORK/root-install.sh"
    write_root_install_script "$root_script" "$source" "$destination" "$install_dir" "$scope" "$record_source" "$record_target"
    if ! auth_error=$(run_root_script "$root_script" 2>&1); then
      fail_step "${auth_error:-授权失败。}"
    fi
    progress 88 "复制程序" "已复制 hcloud。"
  else
    progress 86 "复制程序" "正在复制 hcloud。"
    mkdir -p "$install_dir"
    cp "$source" "$destination"
    chmod 755 "$destination"
    xattr -d com.apple.quarantine "$destination" 2>/dev/null || true
    progress 88 "复制程序" "已复制 hcloud。"
  fi

  if [ "$scope" = "zshrc" ]; then
    progress 92 "写入 PATH" "正在写入 $path_file。"
    write_zshrc_path "$path_file" "$install_dir"
  elif [ "$scope" = "paths.d" ]; then
    progress 92 "写入 PATH" "已写入 /etc/paths.d/hcloud。"
  else
    progress 92 "写入 PATH" "安装目录已在 PATH 中，未重复添加。"
  fi

  if under_home "$install_dir"; then
    progress 97 "写入安装记录" "正在写入当前用户安装记录。"
    write_install_record "$USER_RECORD" "$install_dir" "$destination" "$version" "$scope" "$path_file"
  else
    progress 97 "写入安装记录" "已写入系统安装记录。"
  fi

  HCLOUD_RESULT=$destination
  printf '%s' "$destination" >"$HCLOUD_WORK/result.txt"
  progress 100 "完成" "操作已完成。"
  printf 'DONE\n' >"$HCLOUD_STATUS_FILE"
}

uninstall_hcloud() {
  local executable="$1"
  local install_dir="$2"
  local scope="$3"
  local path_file="$4"
  local remove_config="$5"
  install_dir=$(normalize_dir "$install_dir")
  local remove_paths=no remove_system=no remove_file_as_root=no

  if [ "$scope" = "paths.d" ] || paths_d_matches "$install_dir"; then
    remove_paths=yes
  fi
  if [ -f "$SYSTEM_RECORD" ]; then
    local recorded
    recorded=$(json_get "$SYSTEM_RECORD" executablePath | tr -d '\r')
    if [ -n "$recorded" ] && same_dir "$recorded" "$executable"; then
      remove_system=yes
    fi
  fi
  if [ -n "$executable" ] && [ -f "$executable" ] && [ ! -w "$(dirname "$executable")" ]; then
    remove_file_as_root=yes
  fi

  if [ "$remove_paths" = "yes" ] || [ "$remove_system" = "yes" ] || [ "$remove_file_as_root" = "yes" ]; then
    progress 20 "请求授权" "正在请求授权。向导会保持打开。"
    local root_executable=""
    if [ "$remove_file_as_root" = "yes" ]; then
      root_executable=$executable
    fi
    local root_script="$HCLOUD_WORK/root-remove.sh"
    mkdir -p "$HCLOUD_WORK"
    write_root_remove_script "$root_script" "$root_executable" "$remove_paths" "$remove_system"
    if ! auth_error=$(run_root_script "$root_script" 2>&1); then
      fail_step "${auth_error:-授权失败。}"
    fi
  fi

  progress 55 "从 PATH 删除目录" ""
  if [ "$scope" = "zshrc" ] || [ -z "$scope" ]; then
    local zshrc="${path_file:-$HOME/.zshrc}"
    remove_zshrc_path "$zshrc"
  fi
  progress 60 "从 PATH 删除目录" "已检查安装器写入的 PATH 条目。"

  progress 75 "删除程序" ""
  if [ "$remove_file_as_root" != "yes" ] && [ -n "$executable" ] && [ -f "$executable" ]; then
    rm -f "$executable"
  fi

  progress 88 "删除安装记录" "正在删除安装记录。"
  rm -f "$USER_RECORD"

  if [ "$remove_config" = "yes" ]; then
    progress 95 "删除用户配置" "正在删除 .hcloud。"
    if [ -L "$HOME/.hcloud" ]; then
      fail_step "用户配置目录是链接，已停止删除。"
    fi
    if [ -e "$HOME/.hcloud" ]; then
      rm -rf "$HOME/.hcloud"
    fi
  fi

  HCLOUD_RESULT=$executable
  HCLOUD_KEPT=""
  progress 100 "完成" "操作已完成。"
  printf 'DONE\n' >"$HCLOUD_STATUS_FILE"
}
