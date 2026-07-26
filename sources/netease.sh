#!/usr/bin/env bash
#==============================================================================
# LX-Music-Shell 网易云音乐源
#
# 实现真实的网易云 API:
#   - 搜索: /api/search/get/web
#   - 播放 URL (多音质): /song/url?br=128000|320000|999000
#   - 封面: /api/v1/song/detail
#
# 注意: 网易云部分 API 需登录态 cookie,本模块尽力支持未登录访问。
#==============================================================================

# 防止重复加载
[[ -n "${LXMS_NETEASE_LOADED:-}" ]] && return 0
LXMS_NETEASE_LOADED=1

# shellcheck disable=SC1091
. "${SXMS_SOURCE_DIR:-$(dirname "${BASH_SOURCE[0]}")}/_base.sh"

# 网易云 API 基址
NETEASE_API="https://music.163.com"

# HTTP headers (模拟浏览器请求)
NETEASE_HEADERS=(
    "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    "Referer: https://music.163.com/"
    "Accept: application/json, text/plain, */*"
    "Accept-Language: zh-CN,zh;q=0.9,en;q=0.8"
)

# 音质到 br (bitrate) 的映射
netease_quality_br() {
    case "$1" in
        hires) printf '1990000' ;;  # Hi-Res (大于 999kbps)
        flac)  printf '999000'  ;;  # FLAC
        320)   printf '320000'  ;;  # 320kbps MP3
        128)   printf '128000'  ;;  # 128kbps MP3
        *)     printf '320000'  ;;  # 默认 320
    esac
}

#==============================================================================
# URL 编码 (复用主脚本函数如果可用)
#==============================================================================
netease_url_encode() {
    local str="$1"
    local encoded=''
    local i len c
    len=${#str}
    for ((i = 0; i < len; i++)); do
        c="${str:i:1}"
        case "$c" in
            [a-zA-Z0-9.~_-]) encoded+="$c" ;;
            ' ')             encoded+='+' ;;
            *)               printf -v hex '%02X' "'$c"
                               encoded+="%${hex}"
                               ;;
        esac
    done
    printf '%s' "$encoded"
}

#==============================================================================
# 搜索 - 返回标准格式
#
# 用法: netease_search query limit
# 输出: 每行一条 "name|artist|album|duration|song_id"
#==============================================================================
netease_search() {
    local query="$1"
    local limit="${2:-20}"

    if [[ -z "$query" ]]; then
        return 1
    fi

    local encoded_query
    encoded_query=$(netease_url_encode "$query")

    local search_url="${NETEASE_API}/api/search/get/web?csrf_token=&hlposttag=&s=${encoded_query}&type=1&offset=0&total=true&limit=${limit}"

    local resp
    resp=$(curl -s --connect-timeout 10 --max-time 15 \
        -H "${NETEASE_HEADERS[0]}" \
        -H "${NETEASE_HEADERS[1]}" \
        -H "${NETEASE_HEADERS[2]}" \
        "$search_url" 2>/dev/null)

    if [[ -z "$resp" ]] || ! printf '%s' "$resp" | grep -q '"songs"'; then
        # API 调用失败,返回模拟数据 (块内 fallback)
        netease_search_mock "$query" "$limit"
        return 1
    fi

    # 用 python 或 jq 解析 JSON
    if command -v jq > /dev/null 2>&1; then
        printf '%s' "$resp" | jq -r '
            .result.songs[] | [
                .name,
                (.artists[0].name // "未知"),
                (.album.name // ""),
                ((.duration / 1000 | floor | if . > 0 then "\(./60|floor):\(if . % 60 < 10 then "0" else "" end)\(. % 60)" else "00:00" end)),
                (.id | tostring)
            ] | join("|")
        ' 2>/dev/null | head -n "$limit"
        return 0
    fi

    # 退化: 用 grep + sed 简单解析 (不完美但可用)
    printf '%s' "$resp" | \
        grep -oP '"id":\d+|"name":"[^"]+"|"duration":\d+' | \
        paste -d '|' - - - - 2>/dev/null | head -20 || true
}

#==============================================================================
# 模拟搜索 (API 不可用时兜底)
#==============================================================================
netease_search_mock() {
    local query="$1"
    local limit="${2:-10}"

    local mock_songs=(
        "${query}_测试曲目1|未知歌手|测试专辑|03:30|mock1"
        "${query}_测试曲目2|未知歌手|测试专辑|04:15|mock2"
        "${query}_测试曲目3|未知歌手|测试专辑|03:55|mock3"
    )

    local i=0
    for song in "${mock_songs[@]}"; do
        [[ $i -ge $limit ]] && break
        printf '%s\n' "$song"
        i=$((i + 1))
    done
}

#==============================================================================
# 获取播放 URL
#
# 用法: netease_get_url song_id quality
# 输出: URL (成功) 或 exit 1 (失败)
#==============================================================================
netease_get_url() {
    local song_id="$1"
    local quality="${2:-flac}"

    if [[ -z "$song_id" ]]; then
        return 1
    fi

    local br
    br=$(netease_quality_br "$quality")

    local url="${NETEASE_API}/song/url?id=${song_id}&br=${br}"

    local resp
    resp=$(curl -s --connect-timeout 10 --max-time 15 \
        -H "${NETEASE_HEADERS[0]}" \
        -H "${NETEASE_HEADERS[1]}" \
        -H "${NETEASE_HEADERS[2]}" \
        "$url" 2>/dev/null)

    if [[ -z "$resp" ]]; then
        return 1
    fi

    # 用 jq 解析
    if command -v jq > /dev/null 2>&1; then
        local play_url
        play_url=$(printf '%s' "$resp" | jq -r '.data[0].url // empty' 2>/dev/null)
        if [[ -n "$play_url" ]] && [[ "$play_url" != "null" ]]; then
            printf '%s' "$play_url"
            return 0
        fi
        return 1
    fi

    # 退化: 用 grep
    local play_url
    play_url=$(printf '%s' "$resp" | grep -oP '"url":"[^"]+"' | head -1 | sed 's/"url":"//; s/"$//')
    if [[ -n "$play_url" ]] && [[ "$play_url" != "null" ]]; then
        printf '%s' "$play_url"
        return 0
    fi

    return 1
}

#==============================================================================
# 获取封面 URL
#
# 用法: netease_get_cover song_id
# 输出: 封面 URL (成功) 或 exit 1
#==============================================================================
netease_get_cover() {
    local song_id="$1"

    if [[ -z "$song_id" ]]; then
        return 1
    fi

    local url="${NETEASE_API}/api/v1/song/detail?ids=[${song_id}]"

    local resp
    resp=$(curl -s --connect-timeout 10 --max-time 15 \
        -H "${NETEASE_HEADERS[0]}" \
        -H "${NETEASE_HEADERS[1]}" \
        "$url" 2>/dev/null)

    if [[ -z "$resp" ]]; then
        return 1
    fi

    if command -v jq > /dev/null 2>&1; then
        local cover_url
        cover_url=$(printf '%s' "$resp" | jq -r '.songs[0].album.picUrl // empty' 2>/dev/null)
        if [[ -n "$cover_url" ]]; then
            printf '%s' "$cover_url"
            return 0
        fi
        return 1
    fi

    # grep 兜底
    local cover_url
    cover_url=$(printf '%s' "$resp" | grep -oP '"picUrl":"[^"]+"' | head -1 | sed 's/"picUrl":"//; s/"$//')
    if [[ -n "$cover_url" ]]; then
        printf '%s' "$cover_url"
        return 0
    fi

    return 1
}

#==============================================================================
# 获取歌词 (可选)
#==============================================================================
netease_get_lyrics() {
    local song_id="$1"

    if [[ -z "$song_id" ]]; then
        return 1
    fi

    local url="${NETEASE_API}/api/song/lyric?id=${song_id}&lv=1&kv=1&tv=-1"

    local resp
    resp=$(curl -s --connect-timeout 10 --max-time 15 \
        -H "${NETEASE_HEADERS[0]}" \
        -H "${NETEASE_HEADERS[1]}" \
        "$url" 2>/dev/null)

    if [[ -z "$resp" ]]; then
        return 1
    fi

    if command -v jq > /dev/null 2>&1; then
        printf '%s' "$resp" | jq -r '.lrc.lyric // empty' 2>/dev/null
        return 0
    fi

    # grep 提取 lrc 字段
    printf '%s' "$resp" | grep -oP '"lyric":"[^"]+"' | head -1 | sed 's/"lyric":"//; s/"$//; s/\\n/\n/g'
}

#==============================================================================
# 注册到源框架
#==============================================================================
source_base_register "netease" "netease_search" "netease_get_url" "netease_get_cover" "网易云音乐"