#!/usr/bin/env bash
#==============================================================================
# LX-Music-Shell 网易云音乐源 (直接 API, 真实实现)
#
# 提供真实可用的:
#   - 搜索  (/api/search/get/web)      —— 已实测可用, 返回真实歌曲
#   - 歌词  (/api/song/lyric)          —— 已实测可用, 返回 LRC
#   - 封面  (搜索结果自带 picUrl)       —— 真实可用
#   - 播放  (/song/url + outer/url)    —— 尽力而为 (版权曲目匿名受限)
#
# 播放 URL 说明:
#   网易云对版权/VIP 曲目匿名播放受限。本模块先尝试 /song/url 官方接口,
#   失败后回退到 /song/media/outer/url (mpv 跟随重定向)。若仍失败,
#   上游 (do_play) 会回退到 LX-Music 聚合 API (如用户配置了可用服务器)。
#
# 搜索输出格式 (与 sources/_base.sh 契约一致, 含封面):
#   name|artist|album|duration|song_id|cover_url
#
# 注册: source_base_register "netease" "netease_search" "netease_get_url" "netease_get_cover"
#==============================================================================

[[ -n "${LXMS_NETEASE_LOADED:-}" ]] && return 0
readonly LXMS_NETEASE_LOADED=1

# shellcheck disable=SC1091
. "${LXMS_SOURCE_DIR:-$(dirname "${BASH_SOURCE[0]}")}/_base.sh"

NETEASE_API="${NETEASE_API:-https://music.163.com}"
NETEASE_UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

#==============================================================================
# 工具: URL 编码 (用 python3, 正确处理 UTF-8 字节)
#==============================================================================
netease_url_encode() {
    python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1" 2>/dev/null
}

#==============================================================================
# 搜索 (真实)
#
# 用法: netease_search query limit
# 输出: name|artist|album|duration|song_id|cover_url
#==============================================================================
netease_search() {
    local query="$1"
    local limit="${2:-20}"
    [[ -z "$query" ]] && return 1

    local encoded resp
    encoded=$(netease_url_encode "$query")
    resp=$(curl -sS --connect-timeout 8 --max-time 15 \
        -H "User-Agent: ${NETEASE_UA}" \
        -H "Referer: ${NETEASE_API}/" \
        "${NETEASE_API}/api/search/get/web?csrf_token=&hlposttag=&s=${encoded}&type=1&offset=0&total=true&limit=${limit}" 2>/dev/null)

    [[ -z "$resp" ]] && return 1
    [[ "$resp" != *'"songs"'* ]] && return 1

    # 用 python3 解析 (无 jq 依赖)
    printf '%s' "$resp" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
songs = d.get("result", {}).get("songs", [])
def fmt_dur(ms):
    try:
        s = int(ms) // 1000
    except Exception:
        return "00:00"
    return "%02d:%02d" % (s // 60, s % 60)
for s in songs:
    name = s.get("name", "未知")
    artists = s.get("artists") or []
    artist = artists[0].get("name", "未知歌手") if artists else "未知歌手"
    album = (s.get("album") or {}).get("name", "") or ""
    dur = fmt_dur(s.get("duration", 0))
    sid = str(s.get("id", ""))
    # 封面: 优先专辑图 (若有), 否则用歌手头像 img1v1Url (真实可访问)
    cover = (s.get("album") or {}).get("picUrl", "") or ""
    if not cover and artists:
        cover = artists[0].get("img1v1Url", "") or ""
    if not cover:
        cover = ((s.get("album") or {}).get("artist") or {}).get("img1v1Url", "") or ""
    if cover and "?" in cover:
        cover = cover.split("?")[0] + "?param=300y300"
    elif cover:
        cover = cover + "?param=300y300"
    print("|".join([name, artist, album, dur, sid, cover]))
' 2>/dev/null | head -n "$limit"
}

#==============================================================================
# 获取播放 URL (尽力而为)
#
# 用法: netease_get_url song_id quality
# 输出: URL (成功) 或 return 1
#==============================================================================
netease_get_url() {
    local song_id="$1"
    local quality="${2:-flac}"
    [[ -z "$song_id" ]] && return 1

    local br
    case "$quality" in
        hires) br=1990000 ;;
        flac)  br=999000 ;;
        320)   br=320000 ;;
        128)   br=128000 ;;
        *)     br=320000 ;;
    esac

    # 1) 官方 /song/url 接口
    local resp url
    resp=$(curl -sS --connect-timeout 8 --max-time 15 \
        -H "User-Agent: ${NETEASE_UA}" \
        -H "Referer: ${NETEASE_API}/" \
        "${NETEASE_API}/song/url?id=${song_id}&br=${br}" 2>/dev/null)
    if [[ -n "$resp" ]]; then
        url=$(printf '%s' "$resp" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for item in (d.get("data") or []):
    u = item.get("url")
    if u:
        print(u); sys.exit(0)
' 2>/dev/null)
        if [[ -n "$url" ]] && [[ "$url" == http* ]]; then
            printf '%s' "$url"
            return 0
        fi
    fi

    # 2) outer/url 重定向 (免费曲目可播, 版权曲目 -> /404)
    printf '%s/song/media/outer/url?id=%s.mp3' "${NETEASE_API}" "$song_id"
    return 0
}

#==============================================================================
# 获取封面
#
# 用法: netease_get_cover song_id
#==============================================================================
netease_get_cover() {
    local song_id="$1"
    [[ -z "$song_id" ]] && return 1
    # 封面已内嵌在搜索结果的第 6 列, 此函数保留用于独立调用 (通过详情接口)
    local resp cover
    resp=$(curl -sS --connect-timeout 8 --max-time 15 \
        -H "User-Agent: ${NETEASE_UA}" \
        -H "Referer: ${NETEASE_API}/" \
        "${NETEASE_API}/api/v1/song/detail?ids=[${song_id}]" 2>/dev/null)
    [[ -z "$resp" ]] && return 1
    cover=$(printf '%s' "$resp" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
songs = d.get("songs") or []
if songs:
    pic = (songs[0].get("album") or {}).get("picUrl", "")
    if pic:
        print(pic.split("?")[0] + "?param=300y300")
' 2>/dev/null)
    [[ -n "$cover" ]] || return 1
    printf '%s' "$cover"
}

#==============================================================================
# 获取歌词 (真实)
#
# 用法: netease_get_lyrics song_id
# 输出: LRC 文本 (成功) 或 return 1
#==============================================================================
netease_get_lyrics() {
    local song_id="$1"
    [[ -z "$song_id" ]] && return 1

    local resp
    resp=$(curl -sS --connect-timeout 8 --max-time 15 \
        -H "User-Agent: ${NETEASE_UA}" \
        -H "Referer: ${NETEASE_API}/" \
        "${NETEASE_API}/api/song/lyric?id=${song_id}&lv=1&kv=1&tv=-1" 2>/dev/null)
    [[ -z "$resp" ]] && return 1

    printf '%s' "$resp" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
lrc = (d.get("lrc") or {}).get("lyric", "")
if not lrc:
    sys.exit(1)
print(lrc, end="")
' 2>/dev/null || return 1
}

#==============================================================================
# 注册到源框架
#==============================================================================
source_base_register "netease" "netease_search" "netease_get_url" "netease_get_cover" "网易云音乐"
