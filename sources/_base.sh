#!/usr/bin/env bash
#==============================================================================
# LX-Music-Shell 源基础模块
#
# 为所有音乐源提供统一的接口和音质保底回退逻辑。
#
# 用法 (在每个 source_*.sh 中):
#   . "$LIB_DIR/sources/_base.sh"
#   source_base_register "netease" "netease_search" "netease_get_url" "netease_get_cover"
#
# 接口契约:
#   <id>_search query limit         -> 输出 "id|name|artist|duration|song_id" 行
#   <id>_get_url song_id quality    -> 输出 URL 字符串,失败返回 1
#   <id>_get_cover song_id          -> 输出封面 URL,失败返回 1
#==============================================================================

# 防止重复加载 (不使用 readonly 以便测试可重复加载)
if [[ -n "${LXMS_SOURCE_BASE_LOADED:-}" ]]; then
    return 0
fi
LXMS_SOURCE_BASE_LOADED=1

#==============================================================================
# 源注册表
# 用 declare -gA 显式声明为全局关联数组 (避免在 sourced 函数内被局部化)
#==============================================================================
unset SOURCE_SEARCH_FUNCS SOURCE_URL_FUNCS SOURCE_COVER_FUNCS SOURCE_NAMES 2>/dev/null || true
declare -gA SOURCE_SEARCH_FUNCS
declare -gA SOURCE_URL_FUNCS
declare -gA SOURCE_COVER_FUNCS
declare -gA SOURCE_NAMES

source_base_register() {
    local id="$1"
    local search_func="$2"
    local url_func="$3"
    local cover_func="$4"
    local display_name="${5:-${id}}"

    SOURCE_SEARCH_FUNCS["$id"]="$search_func"
    SOURCE_URL_FUNCS["$id"]="$url_func"
    SOURCE_COVER_FUNCS["$id"]="$cover_func"
    SOURCE_NAMES["$id"]="$display_name"
}

#==============================================================================
# 音质定义
#==============================================================================

# 完整的回退链
source_base_quality_chain_full="hires flac 320 128"
# 平衡模式 (跳过 hires)
source_base_quality_chain_balanced="flac 320 128"
# 快速模式 (只用 320)
source_base_quality_chain_fast="320 128"

#==============================================================================
# 音质配置加载
#==============================================================================
source_base_load_config() {
    local config_file="${1:-${LXMS_CONFIG_FILE:-}}"

    SOURCE_BASE_DEFAULT_QUALITY="flac"
    SOURCE_BASE_QUALITY_MODE="highest"
    SOURCE_BASE_SKIP_UNAVAILABLE="1"

    if [[ -z "$config_file" ]] || [[ ! -f "$config_file" ]]; then
        source_base_compute_chain
        return 0
    fi

    # 解析配置 (避免 source 整个文件的安全风险)
    local line key value
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$line" ]] && continue

        if [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            value="${value#\"}"
            value="${value%\"}"

            case "$key" in
                DEFAULT_QUALITY) SOURCE_BASE_DEFAULT_QUALITY="$value" ;;
                QUALITY_MODE)    SOURCE_BASE_QUALITY_MODE="$value" ;;
                SKIP_UNAVAILABLE_QUALITY) SOURCE_BASE_SKIP_UNAVAILABLE="$value" ;;
            esac
        fi
    done < "$config_file"

    source_base_compute_chain
}

# 根据 QUALITY_MODE 计算回退链
source_base_compute_chain() {
    case "${SOURCE_BASE_QUALITY_MODE:-highest}" in
        highest)
            source_base_quality_chain="$source_base_quality_chain_full"
            ;;
        balanced)
            source_base_quality_chain="$source_base_quality_chain_balanced"
            ;;
        fast|fastest)
            source_base_quality_chain="$source_base_quality_chain_fast"
            ;;
        *)
            source_base_quality_chain="$source_base_quality_chain_full"
            ;;
    esac

    # 把 DEFAULT_QUALITY 放到链首
    if [[ -n "${SOURCE_BASE_DEFAULT_QUALITY:-}" ]]; then
        local dq="${SOURCE_BASE_DEFAULT_QUALITY}"
        local rest="$source_base_quality_chain"
        rest="${rest#${dq} }"
        rest="${rest% ${dq}}"
        source_base_quality_chain="$dq $rest"
    fi
}

#==============================================================================
# 音质标签 (用于 UI 显示)
#==============================================================================
quality_label() {
    case "$1" in
        hires) printf 'HiRes' ;;
        flac)  printf 'FLAC' ;;
        320)   printf 'HQ' ;;
        128)   printf 'SQ' ;;
        *)     printf '%s' '---' ;;
    esac
}

quality_colored_label() {
    case "$1" in
        hires) printf '%sHiRes%s' "${LXMS_FG_YELLOW:-}" "${LXMS_RESET:-}" ;;
        flac)  printf '%sFLAC%s' "${LXMS_FG_CYAN:-}" "${LXMS_RESET:-}" ;;
        320)   printf '%sHQ%s' "${LXMS_FG_GREEN:-}" "${LXMS_RESET:-}" ;;
        128)   printf '%sSQ%s' "${LXMS_FG_GRAY:-}" "${LXMS_RESET:-}" ;;
        *)     printf '%s---%s' "${LXMS_FG_GRAY:-}" "${LXMS_RESET:-}" ;;
    esac
}

quality_bitrate() {
    case "$1" in
        hires) printf '~3200+ kbps' ;;
        flac)  printf '~1000 kbps' ;;
        320)   printf '320 kbps' ;;
        128)   printf '128 kbps' ;;
        *)     printf 'unknown' ;;
    esac
}

#==============================================================================
# 核心: source_base_get_play_url
#
# 用法:
#   source_base_get_play_url "netease" "123456" "flac"
#
# 输入:
#   source_id, song_id, quality (可选, 默认 DEFAULT_QUALITY)
#
# 输出:
#   "quality:url" 成功
#   exit 1 失败
#==============================================================================
source_base_get_play_url() {
    local source_id="$1"
    local song_id="$2"
    local requested="${3:-${SOURCE_BASE_DEFAULT_QUALITY:-flac}}"

    local url_func="${SOURCE_URL_FUNCS[$source_id]:-}"
    if [[ -z "$url_func" ]]; then
        return 1
    fi

    # 按回退链尝试
    local quality
    for quality in $requested $source_base_quality_chain; do
        local url
        if url=$("$url_func" "$song_id" "$quality" 2>/dev/null); then
            [[ -n "$url" ]] && {
                printf '%s\n' "${quality}:${url}"
                return 0
            }
        fi
    done

    return 1
}

#==============================================================================
# 批量搜索
#
# source_base_search_all query limit
# 输出格式: "id|name|artist|duration|song_id|quality|cover_url"
#==============================================================================
source_base_search_all() {
    local query="$1"
    local limit="${2:-20}"
    local id

    for id in "${!SOURCE_SEARCH_FUNCS[@]}"; do
        local search_func="${SOURCE_SEARCH_FUNCS[$id]}"
        if [[ -n "$search_func" ]] && declare -f "$search_func" > /dev/null; then
            # 输出源名作为前缀 (用于调试)
            "$search_func" "$query" "$limit" 2>/dev/null | while IFS= read -r line; do
                if [[ -n "$line" ]]; then
                    printf '%s|%s\n' "$id" "$line"
                fi
            done
        fi
    done
}

#==============================================================================
# 列出已注册的源
#==============================================================================
source_base_list() {
    local id
    for id in "${!SOURCE_NAMES[@]}"; do
        printf '%s\t%s\n' "$id" "${SOURCE_NAMES[$id]}"
    done
}

#==============================================================================
# 健康检查 - 测试所有源
#==============================================================================
source_base_check_health() {
    local id
    for id in "${!SOURCE_URL_FUNCS[@]}"; do
        local url_func="${SOURCE_URL_FUNCS[$id]}"
        if [[ -n "$url_func" ]] && declare -f "$url_func" > /dev/null; then
            printf '%s:%s\n' "$id" "$([ -n "$("$url_func" "test_id" "flac" 2>/dev/null)" ] && echo "ok" || echo "fail")"
        fi
    done
}
