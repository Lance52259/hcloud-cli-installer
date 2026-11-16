# 从 GitHub Releases 查询、下载并校验 macOS 安装包。不读取 debug/。

release_base() {
  local base="${HCLOUD_RELEASE_DOWNLOAD_BASE:-https://github.com/Lance52259/hcloud-cli-installer/releases}"
  base=${base%/}
  printf '%s' "$base"
}

host_arch() {
  case "$(uname -m)" in
    x86_64|amd64) printf 'amd64' ;;
    arm64|aarch64) printf 'arm64' ;;
    *) printf '' ;;
  esac
}

asset_name() {
  local arch
  arch=$(host_arch)
  [ -n "$arch" ] || return 1
  printf 'huaweicloud-cli-darwin-%s.tar.gz' "$arch"
}

valid_tag() {
  printf '%s' "$1" | grep -Eq '^[A-Za-z0-9._+-]+$'
}

asset_url() {
  local version="$1"
  local asset
  asset=$(asset_name) || return 1
  local base
  base=$(release_base)
  if [ "$version" = "latest" ]; then
    printf '%s/latest/download/%s' "$base" "$asset"
  else
    printf '%s/download/%s/%s' "$base" "$version" "$asset"
  fi
}

sums_url() {
  local asset
  asset=$(asset_url "$1") || return 1
  printf '%s/SHA256SUMS' "${asset%/*}"
}

latest_api_url() {
  local base
  base=$(release_base)
  case "$base" in
    https://github.com/*/*/releases)
      local owner repo
      owner=$(printf '%s' "$base" | cut -d/ -f4)
      repo=$(printf '%s' "$base" | cut -d/ -f5)
      printf 'https://api.github.com/repos/%s/%s/releases/latest' "$owner" "$repo"
      ;;
    *)
      return 1
      ;;
  esac
}

fetch_latest_tag() {
  local api body tag
  api=$(latest_api_url) || return 1
  body=$(curl -fsSL --connect-timeout 15 --max-time 20 -A hcloud-setup \
    -H 'Accept: application/vnd.github+json' "$api" 2>/dev/null) || return 1
  tag=$(printf '%s' "$body" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  valid_tag "$tag" || return 1
  printf '%s' "$tag"
}

asset_exists() {
  local url="$1"
  curl -fL --connect-timeout 15 --max-time 20 -A hcloud-setup -r 0-0 -o /dev/null "$url" >/dev/null 2>&1
}

download_file() {
  local url="$1"
  local destination="$2"
  local partial="${destination}.partial"
  rm -f "$partial"
  if curl -fL --connect-timeout 20 --max-time 300 -A hcloud-setup -o "$partial" "$url"; then
    mv "$partial" "$destination"
    return 0
  fi
  rm -f "$partial"
  return 1
}

sums_file_is_real() {
  local file="$1"
  [ -f "$file" ] || return 1
  grep -Eq '^[[:space:]]*[0-9a-fA-F]{64}[[:space:]]+[^[:space:]]+' "$file"
}

verify_sha256() {
  local file="$1"
  local sums="$2"
  local asset="$3"
  local actual expected name line
  actual=$(shasum -a 256 "$file" | awk '{print tolower($1)}')
  while IFS= read -r line; do
    printf '%s' "$line" | grep -Eq '^[[:space:]]*[0-9a-fA-F]{64}[[:space:]]+' || continue
    expected=$(printf '%s' "$line" | awk '{print tolower($1)}')
    name=$(printf '%s' "$line" | awk '{print $2}' | sed 's/^\*//')
    name=${name##*/}
    if [ "$name" = "$asset" ]; then
      if [ "$expected" != "$actual" ]; then
        return 2
      fi
      return 0
    fi
  done <"$sums"
  return 1
}

extract_hcloud() {
  local archive="$1"
  local destination="$2"
  local entry
  rm -rf "$destination"
  mkdir -p "$destination"
  while IFS= read -r entry; do
    case "$entry" in
      /*|\\*|..|../*|*/..|*/../*|*\\..|*\\..\\*)
        printf '压缩包包含不安全路径：%s\n' "$entry" >&2
        return 1
        ;;
    esac
  done <<EOF
$(tar -tzf "$archive")
EOF
  tar -xzf "$archive" -C "$destination"
  local found="" depth best_depth=9999 candidate
  while IFS= read -r candidate; do
    [ -n "$candidate" ] || continue
    depth=$(printf '%s' "$candidate" | awk -F/ '{print NF}')
    if [ "$depth" -lt "$best_depth" ]; then
      best_depth=$depth
      found=$candidate
    fi
  done <<EOF
$(find "$destination" -type f -name hcloud)
EOF
  if [ -z "$found" ]; then
    printf '压缩包中没有找到 hcloud。\n' >&2
    return 1
  fi
  chmod 755 "$found"
  printf '%s' "$found"
}
