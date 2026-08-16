#!/usr/bin/env bash
#==============================================================================
# LX-Music-Shell 音源管理模块 (yinyuan)
#
# 提供「自动添加音源」能力:
#   - 音源配置存储在 yinyuan 目录 (默认 ~/.config/lx-music-shell/yinyuan)
#   - 内容做混淆加密 (XOR + base64), 不落盘明文 URL
#   - 支持两种添加方式:
#       1) 输入 GitHub 链接 (raw.githubusercontent.com / .github) 自动拉取配置
#       2) 选择式: 内置精选源列表, 选中后输入 URL/链接
#   - yinyuan 目录已列入 .gitignore, 不上传到 GitHub
#
# 命令 (接入 /source):
#   /source list           列出内置精选源 + 已配置的 yinyuan 源
#   /source add <name> <url|github链接>   添加音源 (自动识别 GitHub 链接)
#   /source remove <name>  移除音源
#
# 存储格式: yinyuan/<name>  (内容 = 混淆后的搜索 URL 模板)
#==============================================================================

[[ -n "${LXMS_YINYUAN_LOADED:-}" ]] && return 0
readonly LXMS_YINYUAN_LOADED=1

YINYUAN_DIR="${YINYUAN_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/lx-music-shell/yinyuan}"
YINYUAN_KEY="lxms-yinyuan-v3"

#==============================================================================
# 混淆加密 (XOR + base64, 可逆; 用于避免明文落盘, 非高强度加密)
#==============================================================================
yinyuan_obf() {
    python3 -c '
import base64, sys
key = b"'"${YINYUAN_KEY}"'"
d = sys.argv[1].encode("utf-8")
out = bytes(b ^ key[i % len(key)] for i, b in enumerate(d))
print(base64.urlsafe_b64encode(out).decode(), end="")
' "$1" 2>/dev/null
}

yinyuan_deobf() {
    python3 -c '
import base64, sys
key = b"'"${YINYUAN_KEY}"'"
try:
    d = base64.urlsafe_b64decode(sys.argv[1].encode("ascii"))
except Exception:
    sys.exit(1)
out = bytes(b ^ key[i % len(key)] for i, b in enumerate(d))
print(out.decode("utf-8", "replace"), end="")
' "$1" 2>/dev/null
}

#==============================================================================
# 路径与基础操作
#==============================================================================
yinyuan_dir() { printf '%s' "$YINYUAN_DIR"; }

yinyuan_path() { printf '%s/%s' "$YINYUAN_DIR" "$1"; }

yinyuan_add() {
    local name="$1" url="$2"
    [[ -z "$name" || -z "$url" ]] && return 1
    [[ "$name" =~ [^a-zA-Z0-9_-] ]] && return 1
    mkdir -p "$YINYUAN_DIR"
    local obf
    obf=$(yinyuan_obf "$url")
    [[ -z "$obf" ]] && return 1
    printf '%s' "$obf" > "$(yinyuan_path "$name")"
    return 0
}

yinyuan_remove() {
    rm -f "$(yinyuan_path "$1")" 2>/dev/null
}

yinyuan_exists() {
    [[ -f "$(yinyuan_path "$1")" ]]
}

yinyuan_list() {
    [[ -d "$YINYUAN_DIR" ]] || return 0
    local f name
    for f in "$YINYUAN_DIR"/*; do
        [[ -f "$f" ]] || continue
        name=$(basename "$f")
        printf '%s\n' "$name"
    done
}

# 读取并解混淆 URL
yinyuan_get_url() {
    local name="$1" f
    f="$(yinyuan_path "$name")"
    [[ -f "$f" ]] || return 1
    yinyuan_deobf "$(<"$f")"
}

#==============================================================================
# 内置精选源列表 (仅名称+说明, 不含明文敏感 URL)
#==============================================================================
yinyuan_curated() {
    cat <<'EOF'
netease|网易云音乐|https://raw.githubusercontent.com/yourname/lx-yinyuan/main/netease.txt
kugou|酷狗音乐|https://raw.githubusercontent.com/yourname/lx-yinyuan/main/kugou.txt
kuwo|酷我音乐|https://raw.githubusercontent.com/yourname/lx-yinyuan/main/kuwo.txt
qq|QQ音乐|https://raw.githubusercontent.com/yourname/lx-yinyuan/main/qq.txt
migu|咪咕音乐|https://raw.githubusercontent.com/yourname/lx-yinyuan/main/migu.txt
EOF
}

#==============================================================================
# GitHub 链接拉取
#
# 输入: raw 链接 (内容为纯文本搜索 URL 模板, 或 JSON {"search_url":...})
# 输出: 纯文本搜索 URL (成功) 或 return 1
#==============================================================================
yinyuan_fetch_github() {
    local raw_url="$1"
    [[ -z "$raw_url" ]] && return 1

    local content
    content=$(curl -sL --connect-timeout 10 --max-time 25 "$raw_url" 2>/dev/null)
    [[ -z "$content" ]] && return 1

    # JSON 配置 -> 提取 search_url/url 字段
    if [[ "$content" == "{"* ]]; then
        content=$(printf '%s' "$content" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
u = d.get("search_url") or d.get("searchUrl") or d.get("url") or ""
print(u, end="")
' 2>/dev/null)
    fi
    [[ -z "$content" ]] && return 1
    printf '%s' "$content"
}

# 判断 URL 是否为 GitHub 链接
yinyuan_is_github_url() {
    [[ "$1" == *raw.githubusercontent.com* || "$1" == *github.com* || "$1" == *githubusercontent* ]]
}
