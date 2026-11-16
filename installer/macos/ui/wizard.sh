# 五步图形向导：介绍、操作、分支、进度、结果。

alert() {
  osascript - "$@" <<'EOF' >/dev/null
on run argv
  display dialog (item 2 of argv) with title (item 1 of argv) buttons {"确定"} default button "确定"
end run
EOF
}

dialog_buttons() {
  osascript - "$@" <<'EOF'
on run argv
  set dialogTitle to item 1 of argv
  set dialogMessage to item 2 of argv
  set buttonCount to (count of argv) - 2
  if buttonCount is 2 then
    set buttonList to {item 3 of argv, item 4 of argv}
    set defaultName to item 4 of argv
    set cancelName to item 3 of argv
  else
    set buttonList to {item 3 of argv, item 4 of argv, item 5 of argv}
    set defaultName to item 5 of argv
    set cancelName to item 3 of argv
  end if
  try
    set picked to display dialog dialogMessage with title dialogTitle buttons buttonList default button defaultName cancel button cancelName
    return button returned of picked
  on error number -128
    return cancelName
  end try
end run
EOF
}

ask_text() {
  osascript - "$@" <<'EOF'
on run argv
  try
    set picked to display dialog (item 2 of argv) with title (item 1 of argv) default answer (item 3 of argv) buttons {item 4 of argv, item 5 of argv} default button (item 5 of argv) cancel button (item 4 of argv)
    return "ok:" & text returned of picked
  on error number -128
    return "back"
  end try
end run
EOF
}

choose_item() {
  osascript - "$@" <<'EOF'
on run argv
  set dialogTitle to item 1 of argv
  set dialogPrompt to item 2 of argv
  set choices to {}
  repeat with index from 3 to (count of argv)
    set end of choices to item index of argv
  end repeat
  set picked to choose from list choices with title dialogTitle with prompt dialogPrompt default items {item 1 of choices}
  if picked is false then
    return "back"
  end if
  return item 1 of picked
end run
EOF
}

start_progress_window() {
  osascript - "$HCLOUD_STATUS_FILE" >/dev/null 2>&1 <<'EOF' &
on run argv
  set statusFile to item 1 of argv
  set progress total steps to 100
  set progress completed steps to 0
  set progress description to "准备开始"
  repeat
    try
      set content to do shell script "cat " & quoted form of statusFile
    on error
      exit repeat
    end try
    if content starts with "DONE" then exit repeat
    set parts to paragraphs of content
    if (count of parts) >= 1 then
      try
        set progress completed steps to (item 1 of parts) as integer
      end try
    end if
    if (count of parts) >= 2 then set progress description to item 2 of parts
    if (count of parts) >= 3 then set progress additional description to item 3 of parts
    delay 0.3
  end repeat
end run
EOF
  HCLOUD_PROGRESS_PID=$!
}

stop_progress_window() {
  printf 'DONE\n' >"$HCLOUD_STATUS_FILE"
  sleep 0.4
  if [ -n "${HCLOUD_PROGRESS_PID:-}" ]; then
    kill "$HCLOUD_PROGRESS_PID" >/dev/null 2>&1 || true
  fi
}

show_intro() {
  local message
  message=$(cat <<'EOF'
华为云命令行工具（hcloud）用于在命令行中访问和管理华为云服务。

1. 本安装器不包含命令行程序本身。进入进度步骤后，才会从 GitHub Releases 下载所选版本的 macOS 安装包。
2. 默认安装到 /usr/local/bin。该目录已在 PATH 中时不会重复添加；安装到其他目录时，写入 ~/.zshrc 或 /etc/paths.d/hcloud。
3. 卸载会删除程序和安装记录，并删除安装器写入的 PATH 条目。不会因为路径里出现 hcloud 就删除其他软件的目录。
4. ~/.hcloud 默认保留，只有卸载时选择删除配置才会去掉。
5. 安装到个人目录时不需要管理员密码。写入 /usr/local/bin、/etc/paths.d 或系统安装记录时，进度中会请求授权，向导保持打开。
6. 完成后请新开一个终端，再执行 hcloud version。
EOF
)
  local choice
  choice=$(dialog_buttons "欢迎" "$message" "退出" "下一步")
  choice=$(printf '%s' "$choice" | tr -d '\r')
  [ "$choice" = "下一步" ]
}

show_operation() {
  local version_text="${HCLOUD_VERSION:-未知}"
  [ -n "$version_text" ] || version_text="未知"
  if [ "$HCLOUD_FOUND" != "yes" ]; then
    local choice
    choice=$(dialog_buttons "选择操作" "这台 Mac 上没有找到 hcloud。可以开始安装。" "上一步" "安装")
    choice=$(printf '%s' "$choice" | tr -d '\r')
    case "$choice" in
      安装) HCLOUD_OPERATION=install; return 0 ;;
      *) return 1 ;;
    esac
  fi
  local prompt choice
  prompt=$(printf '已找到 hcloud。\n路径：%s\n版本：%s' "$HCLOUD_EXECUTABLE" "$version_text")
  choice=$(choose_item "选择操作" "$prompt" "更新" "卸载")
  choice=$(printf '%s' "$choice" | tr -d '\r')
  case "$choice" in
    更新) HCLOUD_OPERATION=update; return 0 ;;
    卸载) HCLOUD_OPERATION=uninstall; return 0 ;;
    *) return 1 ;;
  esac
}

show_install_branch() {
  local answer choice dir
  answer=$(ask_text "选择安装目录" "默认安装到 /usr/local/bin。个人目录（例如 ~/bin）不需要管理员密码。/usr/local/bin 和其他受保护目录会在进度中请求授权。" "/usr/local/bin" "上一步" "下一步")
  answer=$(printf '%s' "$answer" | tr -d '\r')
  case "$answer" in
    back) return 1 ;;
    ok:*)
      dir=${answer#ok:}
      dir=${dir/#\~/$HOME}
      if [ -z "$dir" ]; then
        alert "无法继续" "请填写安装目录。"
        return 2
      fi
      HCLOUD_TARGET_DIR=$(normalize_dir "$dir")
      HCLOUD_VERSION_CHOICE=${HCLOUD_LATEST_TAG:-latest}
      return 0
      ;;
    *) return 1 ;;
  esac
}

show_update_branch() {
  local latest_label="升级到指定版本"
  local choice tag url
  if [ -n "$HCLOUD_LATEST_TAG" ]; then
    choice=$(choose_item "选择版本" "选择要安装的 Release。" "升级到最新版本（$HCLOUD_LATEST_TAG）" "升级到指定版本")
  else
    choice=$(choose_item "选择版本" "暂时无法查询最新版本，请输入指定版本。" "升级到指定版本")
  fi
  choice=$(printf '%s' "$choice" | tr -d '\r')
  case "$choice" in
    back) return 1 ;;
    升级到指定版本) ;;
    *)
      HCLOUD_VERSION_CHOICE=$HCLOUD_LATEST_TAG
      HCLOUD_TARGET_DIR=$HCLOUD_INSTALL_DIR
      return 0
      ;;
  esac
  local answer
  answer=$(ask_text "指定版本" "输入 Release 标签，例如 1.2.0。不要加 v 前缀。" "" "上一步" "下一步")
  answer=$(printf '%s' "$answer" | tr -d '\r')
  case "$answer" in
    back) return 2 ;;
    ok:*) tag=${answer#ok:} ;;
    *) return 1 ;;
  esac
  tag=$(printf '%s' "$tag" | tr -d '[:space:]')
  if ! valid_tag "$tag"; then
    alert "版本无效" "版本号只能包含字母、数字、点、下划线、加号和减号。"
    return 2
  fi
  url=$(asset_url "$tag") || {
    alert "无法继续" "当前 Mac 架构不受支持。"
    return 2
  }
  if ! asset_exists "$url"; then
    alert "没有这个版本" "Release $tag 没有当前架构的安装包。"
    return 2
  fi
  HCLOUD_VERSION_CHOICE=$tag
  HCLOUD_TARGET_DIR=$HCLOUD_INSTALL_DIR
  return 0
}

show_uninstall_branch() {
  local choice
  choice=$(dialog_buttons "卸载" "默认保留 ~/.hcloud。选择“删除配置”才会删除该目录。程序、安装记录，以及安装器写入的 PATH 条目都会删除。" "上一步" "保留配置" "删除配置")
  choice=$(printf '%s' "$choice" | tr -d '\r')
  case "$choice" in
    保留配置) HCLOUD_REMOVE_CONFIG=no; return 0 ;;
    删除配置) HCLOUD_REMOVE_CONFIG=yes; return 0 ;;
    *) return 1 ;;
  esac
}

run_with_progress() {
  local action="$1"
  HCLOUD_ERROR=""
  HCLOUD_NOTE=""
  HCLOUD_RESULT=""
  HCLOUD_KEPT=""
  HCLOUD_STATUS_FILE="$HCLOUD_WORK/status.txt"
  printf '0\n准备开始\n\n' >"$HCLOUD_STATUS_FILE"
  start_progress_window
  set +e
  (
    set -e
    if [ "$action" = "uninstall" ]; then
      uninstall_hcloud "$HCLOUD_EXECUTABLE" "$HCLOUD_INSTALL_DIR" "$HCLOUD_RECORD_SCOPE" "$HCLOUD_RECORD_PATH_FILE" "$HCLOUD_REMOVE_CONFIG"
    else
      install_hcloud "$HCLOUD_VERSION_CHOICE" "$HCLOUD_TARGET_DIR"
    fi
  )
  local code=$?
  set -e
  if [ -f "$HCLOUD_WORK/error.txt" ]; then
    HCLOUD_ERROR=$(cat "$HCLOUD_WORK/error.txt")
  fi
  if [ -f "$HCLOUD_WORK/note.txt" ]; then
    HCLOUD_NOTE=$(cat "$HCLOUD_WORK/note.txt")
  fi
  if [ -f "$HCLOUD_WORK/result.txt" ]; then
    HCLOUD_RESULT=$(cat "$HCLOUD_WORK/result.txt")
  fi
  stop_progress_window
  if [ "$code" -ne 0 ]; then
    local archive
    archive=$(asset_name 2>/dev/null || true)
    if [ -n "$archive" ] && [ -f "$HCLOUD_WORK/$archive" ]; then
      HCLOUD_KEPT="$HCLOUD_WORK/$archive"
    fi
    return 1
  fi
  return 0
}

show_failure() {
  local message
  message="失败步骤：${HCLOUD_STEP:-准备}
${HCLOUD_ERROR:-操作失败。}"
  if [ -n "$HCLOUD_KEPT" ]; then
    message="$message
已保留安装包：$HCLOUD_KEPT"
  fi
  message="$message
调试日志：$HCLOUD_LOG_FILE"
  local choice
  choice=$(dialog_buttons "未能完成" "$message" "退出" "上一步" "重试")
  choice=$(printf '%s' "$choice" | tr -d '\r')
  printf '%s' "$choice"
}

show_success() {
  local message action_name="安装"
  if [ "$HCLOUD_OPERATION" = "update" ]; then
    action_name="更新"
  fi
  if [ "$HCLOUD_OPERATION" = "uninstall" ]; then
    message="卸载完成。

已删除程序，并已删除安装器写入的 PATH 条目。
目录：$HCLOUD_INSTALL_DIR"
    if [ "$HCLOUD_REMOVE_CONFIG" = "yes" ]; then
      message="$message
用户配置目录 .hcloud 已删除。"
    else
      message="$message
用户配置目录 .hcloud 已保留。"
    fi
  else
    local shown="$HCLOUD_VERSION_CHOICE"
    [ "$shown" = "latest" ] && shown="最新版本"
    message="$action_name 完成。

程序路径：$HCLOUD_RESULT
版本：$shown"
    if [ -n "$HCLOUD_NOTE" ]; then
      message="$message
$HCLOUD_NOTE"
    fi
    message="$message

请新开一个终端，再执行 hcloud version。已经打开的终端看不到刚修改的 PATH。"
  fi
  message="$message
调试日志：$HCLOUD_LOG_FILE"
  dialog_buttons "完成" "$message" "完成" "完成" >/dev/null || true
}

wizard_main() {
  if [ "$(uname -s)" != "Darwin" ]; then
    printf '这个安装器只能在 macOS 上运行。\n' >&2
    return 1
  fi
  if [ -z "$(host_arch)" ]; then
    printf '只支持 amd64 和 arm64。\n' >&2
    return 1
  fi
  log_line "---- 向导已打开。日志 $HCLOUD_LOG_FILE"
  HCLOUD_LATEST_TAG=""
  HCLOUD_WORK=$(mktemp -d "${TMPDIR:-/tmp}/hcloud-setup.XXXXXX")
  local page=intro
  while true; do
    case "$page" in
      intro)
        show_intro || return 0
        find_hcloud
        HCLOUD_LATEST_TAG=$(fetch_latest_tag || true)
        page=operation
        ;;
      operation)
        if show_operation; then
          page=branch
        else
          page=intro
        fi
        ;;
      branch)
        local branch_code=0
        case "$HCLOUD_OPERATION" in
          install) show_install_branch || branch_code=$? ;;
          update) show_update_branch || branch_code=$? ;;
          uninstall) show_uninstall_branch || branch_code=$? ;;
        esac
        if [ "$branch_code" -eq 0 ]; then
          page=progress
        elif [ "$branch_code" -eq 2 ]; then
          page=branch
        else
          page=operation
        fi
        ;;
      progress)
        if run_with_progress "$HCLOUD_OPERATION"; then
          rm -rf "$HCLOUD_WORK"
          page=result
        else
          local failure
          failure=$(show_failure)
          case "$failure" in
            重试) page=progress ;;
            上一步) page=branch ;;
            *) return 1 ;;
          esac
        fi
        ;;
      result)
        show_success
        return 0
        ;;
    esac
  done
}
