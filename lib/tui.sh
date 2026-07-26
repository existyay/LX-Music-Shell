#!/usr/bin/env bash
#==============================================================================
# LX-Music-Shell TUI 渲染模块
#
# 实现简化分栏 TUI 界面:
#   - 顶部状态条 (Logo + 网络 + 音量)
#   - 主区(列表 + 详情)
#   - 自适应 (cols >= 100: 左右, cols < 100: 上下)
#   - 可选封面图渲染 (kitty / iTerm / sixel)
#
# 用法:
#   . lib/capability.sh
#   . lib/input.sh
#   . lib/tui.sh
#   detect_capability
#   tui_render state_json
#
# state_json 字段:
#   title, version, network, volume
#   playlist[], selected, playing
#   current_song: {name, artist, album, duration, quality, cover_url}
#   progress: {current, total}
#==============================================================================

# 防止重复加载
[[ -n "${LXMS_TUI_LOADED:-}" ]] && return 0
readonly LXMS_TUI_LOADED=1

#==============================================================================
# ANSI 常量
#==============================================================================
readonly TUI_ESC=$'\033'
readonly TUI_SAVE_CURSOR="${TUI_ESC}[s"
readonly TUI_RESTORE_CURSOR="${TUI_ESC}[u"
readonly TUI_CLEAR_SCREEN="${TUI_ESC}[2J${TUI_ESC}[H"
readonly TUI_HIDE_CURSOR="${TUI_ESC}[?25l"
readonly TUI_SHOW_CURSOR="${TUI_ESC}[?25h"
readonly TUI_ALT_SCREEN_ON="${TUI_ESC}[?1049h"
readonly TUI_ALT_SCREEN_OFF="${TUI_ESC}[?1049l"
readonly TUI_RESET="${TUI_ESC}[0m"
readonly TUI_BOLD="${TUI_ESC}[1m"
readonly TUI_DIM="${TUI_ESC}[2m"
readonly TUI_REVERSE="${TUI_ESC}[7m"
readonly TUI_CLEAR_LINE="${TUI_ESC}[2K"

# 颜色
readonly TUI_FG_BLACK="${TUI_ESC}[30m"
readonly TUI_FG_RED="${TUI_ESC}[31m"
readonly TUI_FG_GREEN="${TUI_ESC}[32m"
readonly TUI_FG_YELLOW="${TUI_ESC}[33m"
readonly TUI_FG_BLUE="${TUI_ESC}[34m"
readonly TUI_FG_MAGENTA="${TUI_ESC}[35m"
readonly TUI_FG_CYAN="${TUI_ESC}[36m"
readonly TUI_FG_WHITE="${TUI_ESC}[37m"
readonly TUI_FG_GRAY="${TUI_ESC}[90m"

readonly TUI_BG_BLUE="${TUI_ESC}[44m"
readonly TUI_BG_CYAN="${TUI_ESC}[46m"

#==============================================================================
# 光标定位辅助
#==============================================================================
tui_goto() {
    local row="$1"
    local col="$2"
    printf '%s[%d;%dH' "$TUI_ESC" "$row" "$col"
}

tui_clear_screen() {
    printf '%s%s' "$TUI_CLEAR_SCREEN" "$TUI_ALT_SCREEN_ON"
    # shellcheck disable=SC2034
    TUI_ALT_SCREEN_ACTIVE=1
}

#==============================================================================
# 顶部状态条
#
#   参数: state 字符串(可选)
#   输出: 状态条并保持在行 1
#==============================================================================
tui_render_status_bar() {
    local state="${1:-}"
    local cols
    cols=$(get_cols)

    # 跳到 row 1 并清行
    tui_goto 1 1
    printf '%s' "$TUI_CLEAR_LINE"

    # Logo 区 (左)
    printf '%b%s%b ♪ %bLX-Music-Shell%b  ' \
        "$TUI_FG_MAGENTA" "${TUI_BOLD}" \
        "${TUI_FG_WHITE}" "${TUI_BOLD}" \
        "${TUI_RESET}" "${TUI_RESET}"

    # 版本号
    local version="${LXMS_VERSION:-v2.0}"
    printf '%bv%b  ' "${TUI_FG_GRAY}" "${TUI_FG_GRAY}${version}${TUI_RESET}"

    # 网络状态 (中间)
    local network="${LXMS_NETWORK:-connected}"
    case "$network" in
        connected)
            printf '%s●%s %s已连接%s  ' \
                "$TUI_FG_GREEN" "$TUI_RESET" \
                "${TUI_DIM}" "${TUI_RESET}"
            ;;
        disconnected)
            printf '%s●%s %s已断开%s  ' \
                "$TUI_FG_RED" "$TUI_RESET" \
                "${TUI_DIM}" "${TUI_RESET}"
            ;;
        checking)
            printf '%s○%s %s检测中%s  ' \
                "$TUI_FG_YELLOW" "$TUI_RESET" \
                "${TUI_DIM}" "${TUI_RESET}"
            ;;
    esac

    # 音量条 (右)
    local volume="${LXMS_VOLUME:-80}"
    local vol_bars=$((volume / 10))
    local vol_empty=$((10 - vol_bars))

    printf '%s音量%s ' "${TUI_FG_GRAY}" "${TUI_RESET}"
    local i
    for ((i = 0; i < vol_bars; i++)); do
        printf '%s▰%s' "$TUI_FG_CYAN" "$TUI_RESET"
    done
    for ((i = 0; i < vol_empty; i++)); do
        printf '%s▱%s' "$TUI_FG_GRAY" "$TUI_RESET"
    done
    printf ' %d%%' "$volume"

    # 填满右侧
    local cur_len=$((10 + 14 + ${#version} + 12 + vol_bars + vol_empty + 5))
    local pad=$((cols - cur_len))
    if [[ $pad -gt 0 ]]; then
        printf '%*s' "$pad" ''
    fi

    # 底部分隔
    tui_goto 2 1
    printf '%s' "$TUI_CLEAR_LINE"
    local sep=''
    for ((i = 0; i < cols; i++)); do sep+='─'; done
    printf '%s%s%s' "${TUI_DIM}" "$sep" "${TUI_RESET}"
}

#==============================================================================
# 布局计算
#==============================================================================
tui_calculate_layout() {
    local cols="${1:-80}"
    local lines="${2:-24}"

    if [[ "$cols" -ge 100 ]] && [[ "$lines" -ge 24 ]]; then
        # 左右分栏
        TUI_LAYOUT_MODE="split"
        TUI_LEFT_COLS=$((cols * 40 / 100))
        TUI_RIGHT_COLS=$((cols - TUI_LEFT_COLS - 1))
    elif [[ "$lines" -ge 24 ]]; then
        # 上下堆叠
        TUI_LAYOUT_MODE="stack"
        TUI_LIST_LINES=$((lines / 2))
        TUI_DETAIL_LINES=$((lines - TUI_LIST_LINES - 3))
    else
        # 最小化布局
        TUI_LAYOUT_MODE="minimal"
    fi
}

#==============================================================================
# 列表区 (左侧或上侧)
#
# state 字段 (passed as arguments or globals):
#   PLAYLIST array - 歌曲条目
#   SELECTED_INDEX - 选中项
#   PLAYING_INDEX  - 当前播放项
#==============================================================================
tui_render_list() {
    local cols="${1:-40}"
    local start_row="${2:-3}"
    local height="${3:-20}"
    local playlist=("${LXMS_PLAYLIST[@]:-}")
    local selected="${LXMS_SELECTED_INDEX:-0}"
    local playing="${LXMS_PLAYING_INDEX:--1}"

    # 标题
    tui_goto "$start_row" 1
    printf '%s' "$TUI_CLEAR_LINE"
    printf '%b搜索结果 (%d 首)%b' \
        "${TUI_BOLD}${TUI_FG_CYAN}" \
        "${#playlist[@]}" \
        "${TUI_RESET}"

    # 列表
    local i
    for ((i = 0; i < height - 2; i++)); do
        local row=$((start_row + 1 + i))
        if [[ "$row" -gt $((start_row + height)) ]]; then
            break
        fi
        tui_goto "$row" 1
        printf '%s' "$TUI_CLEAR_LINE"

        if [[ "$i" -lt "${#playlist[@]}" ]]; then
            local track="${playlist[$i]}"
            # 解析条目: 序号|歌名|歌手|时长|song_id|quality|cover|quals|url
            IFS='|' read -r num name artist duration sid q cover quals url <<< "$track"

            local marker='  '
            if [[ "$i" == "$playing" ]]; then
                marker="${TUI_FG_GREEN}▶ ${TUI_RESET}"
            fi

            local highlight=""
            local reset_highlight=""
            if [[ "$i" == "$selected" ]]; then
                highlight="${TUI_REVERSE}"
                reset_highlight="${TUI_RESET}"
            fi

            local display_name="$name"
            local max_name_len=$((cols - 14))
            if [[ "${#display_name}" -gt "$max_name_len" ]]; then
                display_name="${display_name:0:$((max_name_len - 1))}…"
            fi

            # 音质标签
            local q_label
            case "${q:-}" in
                hires) q_label="${TUI_FG_YELLOW}HRes${TUI_RESET}" ;;
                flac)  q_label="${TUI_FG_CYAN}FLAC${TUI_RESET}" ;;
                320)   q_label="${TUI_FG_GREEN}HQ${TUI_RESET}" ;;
                128)   q_label="${TUI_FG_GRAY}SQ${TUI_RESET}" ;;
                *)     q_label="${TUI_FG_GRAY}---${TUI_RESET}" ;;
            esac

            printf '%s%s %2d. %s %s%s' \
                "$marker" "$highlight" "$i" "$display_name" \
                "$q_label" "$reset_highlight"
        fi
    done

    # 底部提示
    local hint_row=$((start_row + height))
    if [[ "$hint_row" -lt $((start_row + height + 1)) ]]; then
        tui_goto "$hint_row" 1
        printf '%s' "$TUI_CLEAR_LINE"
        printf '%s↑↓ 移动  Enter 播放  Tab 切换面板%s' \
            "${TUI_DIM}" "${TUI_RESET}"
    fi
}

#==============================================================================
# 详情区 (右侧或下侧)
#==============================================================================
tui_render_detail() {
    local cols="${1:-60}"
    local start_row="${2:-3}"
    local playing="${LXMS_PLAYING_INDEX:--1}"
    local playlist=("${LXMS_PLAYLIST[@]:-}")

    if [[ "$playing" -lt 0 ]] || [[ "$playing" -ge "${#playlist[@]}" ]]; then
        # 无播放
        tui_goto "$start_row" "$((cols / 2 - 5))"
        printf '%s♪ 暂无播放%s' "${TUI_DIM}" "${TUI_RESET}"
        return 0
    fi

    local track="${playlist[$playing]}"
    IFS='|' read -r num name artist album duration sid q cover quals url <<< "$track"

    local row="$start_row"

    # 封面 (如果支持)
    if supports_images && [[ -n "$cover" ]] && [[ "${LXMS_SHOW_COVER:-1}" == "1" ]]; then
        tui_render_cover "$cover" "$row" 1
        # 封面占 8 行
        row=$((row + 8))
    else
        # ASCII 占位符
        tui_goto "$row" 1
        printf '%s╔════════════════╗%s' "${TUI_FG_CYAN}" "${TUI_RESET}"
        tui_goto $((row + 1)) 1
        printf '%s║   ♪ ♪ ♪    ║%s' "${TUI_FG_CYAN}" "${TUI_RESET}"
        tui_goto $((row + 2)) 1
        printf '%s║   (无封面)    ║%s' "${TUI_DIM}" "${TUI_RESET}"
        tui_goto $((row + 3)) 1
        printf '%s╚════════════════╝%s' "${TUI_FG_CYAN}" "${TUI_RESET}"
        row=$((row + 5))
    fi

    # 元数据
    tui_goto "$row" 1
    printf '%s%s%s' "${TUI_BOLD}" "$name" "${TUI_RESET}"
    row=$((row + 1))

    if [[ -n "$artist" ]]; then
        tui_goto "$row" 1
        printf '%s歌手: %s%s' "${TUI_DIM}" "$artist" "${TUI_RESET}"
        row=$((row + 1))
    fi

    if [[ -n "${album:-}" ]]; then
        tui_goto "$row" 1
        printf '%s专辑: %s%s' "${TUI_DIM}" "$album" "${TUI_RESET}"
        row=$((row + 1))
    fi

    if [[ -n "${duration:-}" ]]; then
        tui_goto "$row" 1
        printf '%s时长: %s%s' "${TUI_DIM}" "$duration" "${TUI_RESET}"
        row=$((row + 1))
    fi

    # 音质标签
    tui_goto "$row" 1
    local q_label_full
    case "${q:-}" in
        hires) q_label_full="${TUI_FG_YELLOW}Hi-Res (24bit/96kHz+)${TUI_RESET}" ;;
        flac)  q_label_full="${TUI_FG_CYAN}FLAC 无损${TUI_RESET}" ;;
        320)   q_label_full="${TUI_FG_GREEN}HQ (320k MP3)${TUI_RESET}" ;;
        128)   q_label_full="${TUI_FG_GRAY}SQ (128k MP3)${TUI_RESET}" ;;
        *)     q_label_full="${TUI_FG_GRAY}未知${TUI_RESET}" ;;
    esac
    printf '%s音质: %s' "${TUI_DIM}" "${TUI_RESET}"
    printf '%s\n' "$q_label_full"
    row=$((row + 1))

    # 进度条
    local current="${LXMS_PLAYBACK_CURRENT:-0}"
    local total="${LXMS_PLAYBACK_TOTAL:-100}"
    local percent=0
    if [[ "$total" -gt 0 ]]; then
        percent=$((current * 100 / total))
    fi
    tui_goto "$row" 1
    printf '%s进度: %s' "${TUI_DIM}" "${TUI_RESET}"
    local bar_w=$((cols - 14))
    if [[ "$bar_w" -lt 5 ]]; then bar_w=20; fi
    local filled=$((percent * bar_w / 100))
    printf '%s[' "${TUI_FG_GRAY}"
    local j
    for ((j = 0; j < filled; j++)); do
        printf '%s▰%s' "${TUI_FG_GREEN}" "${TUI_RESET}"
    done
    for ((j = filled; j < bar_w; j++)); do
        printf ' '
    done
    printf '%s] %s%d%%%s' \
        "${TUI_FG_GRAY}" "${TUI_BOLD}" "$percent" "${TUI_RESET}"
}

#==============================================================================
# 封面渲染
#==============================================================================
tui_render_cover() {
    local url="$1"
    local row="${2:-1}"
    local col="${3:-1}"

    tui_goto "$row" "$col"

    case "${LXMS_TERM_IMAGES:-none}" in
        kitty)
            # Kitty 图形协议: \033_Ga=T,f=100,t=f,FILE_PATH\033\\
            # 直接 URL 形式: \033_Ga=T,f=100,t=f;URL\033\\
            printf '\033_Ga=T,f=100,t=f;%s\033\\' "$url"
            ;;
        iTerm)
            # iTerm2 inline image: \033]1337;File=inline=1:<base64>\a
            # 这里简化:输出下载命令提示
            printf '\033]1337;File=inline=1;preserveAspectRatio=1:%s\a' \
                "$(printf '%s' "$url" | base64)"
            ;;
        sixel)
            # Sixel 格式 (简化版)
            printf '%s[image: %s]%s' "${TUI_DIM}" "$url" "${TUI_RESET}"
            ;;
        none|*)
            # 无图片协议 - 显示占位
            printf '%s[无封面 - 终端不支持图片]%s' \
                "${TUI_DIM}" "${TUI_RESET}"
            ;;
    esac
}

#==============================================================================
# 主渲染: tui_render state_json
#
# state 字段 (全局变量):
#   LXMS_VERSION, LXMS_NETWORK, LXMS_VOLUME
#   LXMS_PLAYLIST[], LXMS_SELECTED_INDEX, LXMS_PLAYING_INDEX
#   LXMS_PLAYBACK_CURRENT, LXMS_PLAYBACK_TOTAL
#   LXMS_SHOW_COVER
#==============================================================================
tui_render() {
    local cols lines
    cols=$(get_cols)
    lines=$(get_lines)

    tui_calculate_layout "$cols" "$lines"

    # 进入备用屏幕
    tui_clear_screen

    # 状态条
    tui_render_status_bar

    # 区域注册 (供鼠标命中)
    input_clear_regions
    case "$TUI_LAYOUT_MODE" in
        split)
            input_register_region "list" 3 1 $((lines - 5)) "$TUI_LEFT_COLS"
            input_register_region "detail" 3 $((TUI_LEFT_COLS + 2)) \
                $((lines - 5)) "$TUI_RIGHT_COLS"
            tui_render_list "$TUI_LEFT_COLS" 3 $((lines - 5))
            tui_render_detail "$TUI_RIGHT_COLS" 3
            ;;
        stack)
            tui_render_list "$cols" 3 "$TUI_LIST_LINES"
            tui_render_detail "$cols" $((3 + TUI_LIST_LINES))
            ;;
        minimal)
            tui_render_list "$cols" 3 "$((lines - 5))"
            ;;
    esac

    # 移动到末尾
    tui_goto "$lines" 1
    printf '%s' "$TUI_RESET"
}

#==============================================================================
# 清理
#==============================================================================
tui_cleanup() {
    # 退出备用屏幕
    printf '%s' "$TUI_ALT_SCREEN_OFF"
    # 显示光标
    printf '%s' "$TUI_SHOW_CURSOR"
    printf '%s' "$TUI_RESET"
}
