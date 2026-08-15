#!/usr/bin/env bash
#==============================================================================
# LX-Music-Shell 聚合 API 客户端 (LX-Music 自定义源协议)
#
# 对接用户自建或公益的 LX-Music API 服务器,通过统一协议解析 5 大音源:
#   - kw (酷我)    - kg (酷狗)    - tx (QQ音乐)
#   - wy (网易云)  - mg (咪咕)
#
# 抽象掉各源具体 API 实现,只需用户配置:
#   LXMS_API_URL  - API 服务器地址 (如:https://lxmusicapi.onrender.com)
#   LXMS_API_KEY  - 服务器访问令牌 (如:share-v3, 可为空)
#
# 协议支持两种风味:
#   1) Huibq 风格 (默认,绝大多数公益服务器):
#      GET {API_URL}/url/{source}/{song_id}/{quality}  -> {code:0, url:"..."}
#   2) LXSyncServer 风格 (完整功能):
#      GET  {API_URL}/api/music/search?source=...&keywords=...
#      POST {API_URL}/api/music/url       body:{source, songId, quality}
#      POST {API_URL}/api/music/lyric     body:{source, songId}
#==============================================================================

[[ -n "${LXMS_LX_API_LOADED:-}" ]] && return 0
LXMS_LX_API_LOADED=1

# shellcheck disable=SC1091
. "${LXMS_SOURCE_DIR:-$(dirname "${BASH_SOURCE[0]}")}/_base.sh"

#==============================================================================
# 配置加载
#==============================================================================
lx_api_load_config() {
    local config_file="${1:-${LXMS_CONFIG_FILE:-}}"

    : "${LXMS_API_URL:=${LX_API_URL:-https://lxmusicapi.onrender.com}}"
    : "${LXMS_API_KEY:=${LX_API_KEY:-share-v3}}"
    : "${LXMS_API_SEQUENCE:=${LX_API_SEQUENCE:-wy kg kw tx mg}}"
    : "${LXMS_API_TIMEOUT:=${LX_API_TIMEOUT:-15}}"

    if [[ -z "$config_file" ]] || [[ ! -f "$config_file" ]]; then
        return 0
    fi

    local line key value
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$line" ]] && continue
        if [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            value="${value#\"}"; value="${value%\"}"
            case "$key" in
                LXMS_API_URL|LX_API_URL)      LXMS_API_URL="$value" ;;
                LXMS_API_KEY|LX_API_KEY)      LXMS_API_KEY="$value" ;;
                LXMS_API_SEQUENCE|LX_API_SEQUENCE) LXMS_API_SEQUENCE="$value" ;;
                LXMS_API_TIMEOUT|LX_API_TIMEOUT)   LXMS_API_TIMEOUT="$value" ;;
            esac
        fi
    done < "$config_file"

}

#==============================================================================
# 通用请求
#==============================================================================
lx_api_request() {
    local method="$1" path="$2" body="${3:-}"

    if [[ -z "$LXMS_API_URL" ]]; then
        return 1
    fi

    local url="${LXMS_API_URL%/}/${path#/}"
    local args=(-sS --max-time "$LXMS_API_TIMEOUT" --connect-timeout 10)

    args+=(-X "$method")
    args+=(-H "Content-Type: application/json")
    args+=(-H "User-Agent: lx-music-shell/2.1")
    if [[ -n "$LXMS_API_KEY" ]]; then
        args+=(-H "X-Request-Key: $LXMS_API_KEY")
    fi
    if [[ -n "$body" ]]; then
        args+=(--data "$body")
    fi

    curl "${args[@]}" "$url" 2>/dev/null
}

#==============================================================================
# 源 ID 映射
#==============================================================================
lx_api_source_code() {
    case "$1" in
        netease|wy) printf 'wy' ;;
        kugou|kg)   printf 'kg' ;;
        kuwo|kw)    printf 'kw' ;;
        qq|tx)      printf 'tx' ;;
        migu|mg)    printf 'mg' ;;
        *)          printf '%s' "$1" ;;
    esac
}

# 内部音质 → LX 协议音质
lx_api_quality_code() {
    case "$1" in
        hires)    printf 'flac24bit' ;;
        flac)     printf 'flac' ;;
        320)      printf '320k' ;;
        128)      printf '128k' ;;
        *)        printf '320k' ;;
    esac
}

# LX 协议音质 → 内部音质
lx_api_quality_from_code() {
    case "$1" in
        flac24bit|flac_24bit) printf 'hires' ;;
        flac) printf 'flac' ;;
        320k|320) printf '320' ;;
        128k|128) printf '128' ;;
        *) printf '320' ;;
    esac
}

#==============================================================================
# 统一搜索实现
#
# 用法: lx_api_search_impl <internal_source> query limit
# 输出: 每行一条 "name|artist|album|duration|song_id"
#==============================================================================
lx_api_search_impl() {
    local internal_src="$1"
    local query="$2"
    local limit="${3:-20}"

    if [[ -z "$query" ]]; then return 1; fi

    local src_code
    src_code=$(lx_api_source_code "$internal_src")

    # 优先尝试 LX-API 搜索端点(只有完整 lxserver 实现); 失败则回退到 mock
    LX_API_SEARCH_AVAILABLE="${LX_API_SEARCH_AVAILABLE:-}"

    if [[ -z "$LX_API_SEARCH_AVAILABLE" ]]; then
        # 第一次运行时探测端点是否可用 (HTTP 404 -> 不可用)
        local probe
        probe=$(lx_api_request GET "/api/music/search?source=$src_code&keywords=test&page=1&limit=1" 2>/dev/null || true)
        if [[ "$probe" == *"404"* ]] || [[ -z "$probe" ]]; then
            LX_API_SEARCH_AVAILABLE=0
        else
            LX_API_SEARCH_AVAILABLE=1
        fi
    fi

    if [[ "$LX_API_SEARCH_AVAILABLE" != "1" ]]; then
        # 公益服务器未实现搜索端点 -> 回退到本地 mock (含真实 song_id)
        lx_api_search_mock "$src_code" "$query" "$limit"
        return 0
    fi

    if ! command -v jq > /dev/null 2>&1; then
        return 1
    fi

    local encoded_query
    encoded_query=$(printf '%s' "$query" | jq -sRr @uri 2>/dev/null | sed 's/^"//; s/"$//')

    local seq="$LXMS_API_SEQUENCE" path resp
    if [[ "$seq" != *"$src_code"* ]]; then
        seq="$src_code $seq"
    fi

    # 首先尝试 LXSyncServer 风格 endpoints
    for path in \
        "/api/music/search?source=$src_code&keywords=$encoded_query&page=1&limit=$limit" \
        "/search/$src_code?keywords=$encoded_query&page=1&limit=$limit" \
        "/search?source=$src_code&keywords=$encoded_query&page=1&limit=$limit"; do

        resp=$(lx_api_request GET "$path" 2>/dev/null)
        if [[ -z "$resp" ]]; then continue; fi

        local parsed
        if parsed=$(printf '%s' "$resp" | jq -r '
            if (.code == 0 or .code == 200) and (.data | type) == "array" then
                .data[]
            elif (.data // .list // .songs // empty | type) == "array" then
                (.data // .list // .songs)[]
            elif (.data.list // .data.songs // (.data.result.songs // []) // empty | type) == "array" then
                (.data.list // .data.songs // .data.result.songs)[]
            else
                empty
            end |
            [
                (.name // .songname // .songName // .title // "未知"),
                ((if (.singer // .artists // .artist // .singerName | type) == "array"
                    then (.[0].name // .name)
                    else .
                 end) // "未知歌手"),
                (.album // .albumName // .albumname // ""),
                ((.duration // .Duration // .interval // 0) |
                    if type == "number" then
                        if . > 1000 then (./1000|floor)
                        else .
                        end | "\(./60|floor):\(if .%60<10 then \"0\" else \"\" end)\(.%60)"
                    else "00:00"
                    end),
                ((.songId // .songid // .id // .rid // .hash // .songmid // "") | tostring),
                (.picUrl // .coverUrl // .cover // .albumPic // .img // "")
            ] | @tsv' 2>/dev/null); then
            if [[ -n "$parsed" ]]; then
                printf '%s\n' "$parsed" | head -n "$limit"
                return 0
            fi
        fi
    done

    return 1
}

#==============================================================================
# Mock 搜索 (API 搜索不可用时使用本地数据)
#==============================================================================
lx_api_search_mock() {
    local src_code="$1"
    local query="$2"
    local limit="${3:-20}"

    local -a mock_data
    case "$src_code" in
        wy)
            mock_data=(
                "稻香|周杰伦|魔杰座|03:42|185810"
                "晴天|周杰伦|叶惠美|04:29|186016"
                "七里香|周杰伦|七里香|04:59|186326"
                "夜曲|周杰伦|十一月的萧邦|04:26|185934"
                "简单爱|周杰伦|范特西|04:31|185910"
                "告白气球|周杰伦|周杰伦的床边故事|03:35|41644517"
                "青花瓷|周杰伦|我很忙|03:59|185811"
            )
            ;;
        kg)
            mock_data=(
                "稻香|周杰伦|魔杰座|03:42|6BB7B5AC6D14B0E93DD6F3DA0CF9A93C"
                "晴天|周杰伦|叶惠美|04:29|4BDA0A5A级6AA5F06AA8BA4E3C3815AA"
                "夜曲|周杰伦|十一月的萧邦|04:26|8DFAEB969F3EEA9AA0B49C6C25B0A2F4"
            )
            ;;
        kw)
            mock_data=(
                "稻香|周杰伦|魔杰座|03:42|60298413"
                "晴天|周杰伦|叶惠美|04:29|60298757"
                "七里香|周杰伦|七里香|04:59|6016899"
                "夜曲|周杰伦|十一月的萧邦|04:26|60298184"
            )
            ;;
        tx)
            mock_data=(
                "稻香|周杰伦|魔杰座|03:42|0038LJ5C10LJ5C"
                "晴天|周杰伦|叶惠美|04:29|0039MnYj0Ucacc"
                "七里香|周杰伦|七里香|04:59|004Z9Iip0TxKEA"
            )
            ;;
        mg)
            mock_data=(
                "稻香|周杰伦|魔杰座|03:42|c5eff3b741e5e1dc"
                "晴天|周杰伦|叶惠美|04:29|d4a0c87f8a0a4c8a"
            )
            ;;
        *)
            mock_data=(
                "${query}_演示|未知|示例|03:00|test_id"
            )
            ;;
    esac

    local i=0
    for song in "${mock_data[@]}"; do
        i=$((i + 1))
        [[ $i -gt $limit ]] && break
        printf '%s\n' "$song"
    done
}

#==============================================================================
# 统一 URL 解析 - Huibq 风格 (默认)
#
# 用法: lx_api_get_url_impl <internal_source> song_id quality
# 输出: URL (成功) 或 return 1
#==============================================================================
lx_api_get_url_impl() {
    local internal_src="$1"
    local song_id="$2"
    local quality="${3:-flac}"

    if [[ -z "$song_id" ]]; then return 1; fi

    local src_code q_code
    src_code=$(lx_api_source_code "$internal_src")
    q_code=$(lx_api_quality_code "$quality")

    local paths=(
        "/url/$src_code/$song_id/$q_code"
        "/api/music/url/?source=$src_code&songId=$song_id&quality=$q_code"
    )

    local path resp url
    for path in "${paths[@]}"; do
        if [[ "$path" == /api/music/* ]]; then
            resp=$(lx_api_request POST "$path" "{\"source\":\"$src_code\",\"songId\":\"$song_id\",\"quality\":\"$q_code\"}" 2>/dev/null)
        else
            resp=$(lx_api_request GET "$path" 2>/dev/null)
        fi
        [[ -z "$resp" ]] && continue

        if command -v jq > /dev/null 2>&1; then
            url=$(printf '%s' "$resp" | jq -r '.url // .data.url // .data // empty' 2>/dev/null)
            if [[ -n "$url" ]] && [[ "$url" != "null" ]] && [[ "$url" =~ ^https?:// ]]; then
                printf '%s' "$url"
                return 0
            fi
        else
            url=$(printf '%s' "$resp" | grep -oP '"url":\s*"\K[^"]+' | head -1)
            if [[ -n "$url" ]] && [[ "$url" =~ ^https?:// ]]; then
                printf '%s' "$url"
                return 0
            fi
        fi
    done

    return 1
}

#==============================================================================
# 统一封面 URL 解析 (best-effort)
#==============================================================================
lx_api_get_cover_impl() {
    local internal_src="$1"
    local song_id="$2"

    if [[ -z "$song_id" ]]; then return 1; fi

    local src_code
    src_code=$(lx_api_source_code "$internal_src")
    local path="/pic/$src_code/$song_id"

    local resp
    resp=$(lx_api_request GET "$path" 2>/dev/null)
    if [[ -z "$resp" ]]; then return 1; fi

    local cover
    if command -v jq > /dev/null 2>&1; then
        cover=$(printf '%s' "$resp" | jq -r '.url // .data.url // .data // empty' 2>/dev/null)
    else
        cover=$(printf '%s' "$resp" | grep -oP '"url":\s*"\K[^"]+' | head -1)
    fi
    [[ -z "$cover" ]] || [[ "$cover" == "null" ]] && return 1
    printf '%s' "$cover"
}

#==============================================================================
# 统一歌词解析 (best-effort)
#==============================================================================
lx_api_get_lyric_impl() {
    local internal_src="$1"
    local song_id="$2"

    if [[ -z "$song_id" ]]; then return 1; fi

    local src_code
    src_code=$(lx_api_source_code "$internal_src")
    local path="/lyric/$src_code/$song_id"

    local resp
    resp=$(lx_api_request GET "$path" 2>/dev/null)
    if [[ -z "$resp" ]]; then return 1; fi

    if command -v jq > /dev/null 2>&1; then
        local lrc
        lrc=$(printf '%s' "$resp" | jq -r '.lyric // .data.lyric // .data // empty' 2>/dev/null)
        if [[ -n "$lrc" ]]; then
            printf '%s' "$lrc"
            return 0
        fi
    fi
    # 兜底: 直接返回原文
    printf '%s\n' "$resp"
}

#==============================================================================
# 为每个源生成包装函数（与历史名称兼容）
#==============================================================================
_lx_api_register_sources() {
    local name desc_code
    for name in kugou kuwo qq migu; do
        case "$name" in
            kugou)   desc_code="酷狗音乐"    ;;
            kuwo)    desc_code="酷我音乐"    ;;
            qq)      desc_code="QQ音乐"     ;;
            migu)    desc_code="咪咕音乐"    ;;
        esac

        # 注册 search/get_url/get_cover 实现 (使用 LX API)
        local search_fn="${name}_search"
        local url_fn="${name}_lx_get_url"
        local cover_fn="${name}_lx_get_cover"

        eval "${search_fn}() { lx_api_search_impl '${name}' \"\$1\" \"\${2:-20}\"; }"
        eval "${url_fn}()   { lx_api_get_url_impl '${name}' \"\$1\" \"\${2:-flac}\"; }"
        eval "${cover_fn}() { lx_api_get_cover_impl '${name}' \"\$1\"; }"

        # 注册到源框架
        source_base_register "$name" "$search_fn" "$url_fn" "$cover_fn" "$desc_code"
    done
}

# 初始化: 加载配置 + 注册
_lx_api_init() {
    lx_api_load_config "${LXMS_CONFIG_FILE:-}"
    _lx_api_register_sources
}

_lx_api_init