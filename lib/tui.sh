#!/usr/bin/env bash
#==============================================================================
# LX-Music-Shell TUI 渲染模块 (v2.2)
#
# 设计参考:
#   - references/go-musicfox : vim 风格键盘 (jkhl/gG/Space/n/p/...)
#   - references/bilibili-tui  : 多区块自适应布局 + kitty 图片协议
#
# 关键改进 (相对 v2.0/v2.1):
#   - 自适应三区块布局 (搜索框 / 列表 / 详情)
#   - vim-style 键盘映射函数 (tui_op_*) 供 main() 调度
#   - kitty/iTerm2/Sixel 三协议图片渲染
#   - 真彩色主题 (dark 默认可切)
#   - 实时进度条 (后台 tick)
#   - 输入面板焦点 (搜索框 / 列表 / 详情 三态)
#
# 状态接口 (供 main 和其它模块调用):
#   LXMS_STATE_TITLE      - 标题
#   LXMS_STATE_VERSION    - 版本号
#   LXMS_STATE_NETWORK    - connected | disconnected | checking
#   LXMS_STATE_VOLUME     - 0-100
#   LXMS_STATE_PLAYLIST   - 关联数组 (track_id -> "name|artist|album|duration|song_id|quality|cover_url")
#   LXMS_STATE_SELECTED   - 当前选中项索引
#   LXMS_STATE_PLAYING    - 当前播放索引 (无播放时 -1)
#   LXMS_STATE_PROGRESS_C - 播放进度秒
#   LXMS_STATE_PROGRESS_T - 总时长秒
#==============================================================================

[[ -n "${LXMS_TUI_LOADED:-}" ]] && return 0
readonly LXMS_TUI_LOADED=1

#==============================================================================
# ANSI 常量
#==============================================================================
readonly _T_ESC=$'\033'

# 光标
readonly TUI_CURSOR_HIDE="${_T_ESC}[?25l"
readonly TUI_CURSOR_SHOW="${_T_ESC}[?25h"
readonly TUI_ALT_ON="${_T_ESC}[?1049h"
readonly TUI_ALT_OFF="${_T_ESC}[?1049l"
readonly TUI_CLEAR="${_T_ESC}[2J${_T_ESC}[H"
readonly TUI_CLR_LINE="${_T_ESC}[2K"

# 基础样式
readonly TUI_RESET="${_T_ESC}[0m"
readonly TUI_BOLD="${_T_ESC}[1m"
readonly TUI_DIM="${_T_ESC}[2m"
readonly TUI_INVERT="${_T_ESC}[7m"

# 前景色
readonly TUI_FG_BLACK="${_T_ESC}[30m"
readonly TUI_FG_RED="${_T_ESC}[31m"
readonly TUI_FG_GREEN="${_T_ESC}[32m"
readonly TUI_FG_YELLOW="${_T_ESC}[33m"
readonly TUI_FG_BLUE="${_T_ESC}[34m"
readonly TUI_FG_MAGENTA="${_T_ESC}[35m"
readonly TUI_FG_CYAN="${_T_ESC}[36m"
readonly TUI_FG_WHITE="${_T_ESC}[37m"
readonly TUI_FG_GRAY="${_T_ESC}[90m"

# 背景色
readonly TUI_BG_BLUE="${_T_ESC}[44m"
readonly TUI_BG_CYAN="${_T_ESC}[46m"

#==============================================================================
# 主题 (默认 dark)
#
# 切换主题: tui_set_theme dark/green/light/mono
#==============================================================================
TUI_THEME_NAME="dark"

# 主题色定义: bg_fg accent sub
_tui_get_theme_colors() {
    case "${TUI_THEME_NAME:-dark}" in
        green)
            printf 'cyan|green|cyan'
            ;;
        light)
            printf 'black|blue|red'
            ;;
        mono)
            printf 'white|gray|gray'
            ;;
        dark|*)
            printf 'white|cyan|magenta'
            ;;
    esac
}

tui_set_theme() {
    case "$1" in
        dark|green|light|mono) TUI_THEME_NAME="$1" ;;
        *) return 1 ;;
    esac
}

#==============================================================================
# 光标定位
#==============================================================================
tui_goto() {
    printf '%s[%d;%dH' "${_T_ESC}" "$1" "$2"
}

tui_clear_screen() {
    printf '%s%s' "${TUI_ALT_ON}" "${TUI_CLEAR}"
}

#==============================================================================
# 图片渲染 (kitty / iTerm2 / Sixel)
#
# 用法: tui_render_image <url> <row> <col> [width_chars]
# 返回: 0 成功 (输出多行 ANSI 序列), 1 不支持
#==============================================================================
_tui_image_protocol=""  # kitty | iTerm | sixel | none

tui_render_image() {
    local url="$1" row="$2" col="$3" size="${4:-medium}"

    if [[ -z "$url" || "$url" == "null" ]]; then
        return 1
    fi

    # 探测协议 (探测一次并缓存)
    if [[ -z "$_tui_image_protocol" ]]; then
        case "${TERM:-}${TERM_PROGRAM:-}" in
            *kitty*|xterm-kitty*)
                _tui_image_protocol="kitty" ;;
            *iTerm*|*WezTerm*)
                _tui_image_protocol="iTerm" ;;
            *mlterm*|*foot*|*contour*)
                _tui_image_protocol="sixel" ;;
            *)
                _tui_image_protocol="none" ;;
        esac
    fi

    tui_goto "${row}" "${col}"

    case "$_tui_image_protocol" in
        kitty)
            # Kitty 图形协议 (URL 直传)
            printf '\033_Ga=T,f=100,t=f;%s\033\\' "$url"
            ;;
        iTerm)
            # iTerm2 inline image (base64)
            local b64
            b64=$(printf '%s' "$url" | base64 2>/dev/null || true)
            printf '\033]1337;File=inline=1;preserveAspectRatio=1:%s\a' "$b64"
            ;;
        sixel)
            # Sixel 占位 (实际项目难在纯 shell)
            printf '%s[image]%s' "${TUI_DIM}" "${TUI_RESET}"
            ;;
        *)
            # 协议不支持, 返回失败让调用方渲染占位符
            return 1
            ;;
    esac
}

tui_render_cover_placeholder() {
    local row="${1:-1}"
    local col="${2:-1}"
    local w="${3:-20}"
    local h="${4:-8}"

    tui_goto "${row}" "${col}"
    printf '%s╔%s┓%s\n' "${TUI_FG_CYAN}" "$(printf '═%.0s' $(seq 1 $((w-2))))" "${TUI_RESET}"
    for ((i = 0; i < h - 2; i++)); do
        tui_goto $((row + 1 + i)) "$col"
        printf '%s║%*s%s\n' "${TUI_FG_CYAN}" "$((w - 1))" "${TUI_RESET}"
    done
    tui_goto $((row + h - 1)) "$col"
    printf '%s╚%s┛%s\n' "${TUI_FG_CYAN}" "$(printf '═%.0s' $(seq 1 $((w-2))))" "${TUI_RESET}"
    tui_goto $((row + h / 2)) "$((col + w / 2 - 3))"
    printf '%s♪ ♪ ♪%s' "${TUI_DIM}" "${TUI_RESET}"
}

#==============================================================================
# 头部状态条
#==============================================================================
tui_render_header() {
    local cols lines
    cols=$(get_cols)
    lines=$(get_lines)

    # 行 1: 标题 + 网络 + 音量
    tui_goto 1 1
    printf '%s' "${TUI_CLR_LINE}"
    printf '%s%s%s ♪ %sLX-Music-Shell%s %s' \
        "${TUI_FG_MAGENTA}" "${TUI_BOLD}" "${TUI_FG_WHITE}" \
        "${TUI_BOLD}" "${TUI_RESET}" \
        "${TUI_FG_GRAY}"
    printf 'v%s%s  ' "$(_tui_get_theme_colors | cut -d'|' -f1)" \
        "${LXMS_STATE_VERSION:-2.2}"
    # 网络状态
    case "${LXMS_STATE_NETWORK:-connected}" in
        connected)
            printf '%s●%s %s已连接%s  ' \
                "${TUI_FG_GREEN}" "${TUI_RESET}" "${TUI_DIM}" "${TUI_RESET}" ;;
        disconnected)
            printf '%s●%s %s已断开%s  ' \
                "${TUI_FG_RED}" "${TUI_RESET}" "${TUI_DIM}" "${TUI_RESET}" ;;
        checking)
            printf '%s○%s %s检测中%s  ' \
                "${TUI_FG_YELLOW}" "${TUI_RESET}" "${TUI_DIM}" "${TUI_RESET}" ;;
    esac
    # 音量
    local vol="${LXMS_STATE_VOLUME:-80}"
    local filled=$((vol / 10))
    printf '%s音量%s ' "${TUI_FG_GRAY}" "${TUI_RESET}"
    local i
    for ((i = 0; i < filled; i++)); do printf '%s▰%s' "${TUI_FG_CYAN}" "${TUI_RESET}"; done
    for ((i = filled; i < 10; i++)); do printf '%s▱%s' "${TUI_FG_GRAY}" "${TUI_RESET}"; done
    printf ' %d%%' "$vol"

    # 行 2: 分隔
    tui_goto 2 1
    printf '%s' "${TUI_CLR_LINE}"
    local sep=""
    for ((i = 0; i < cols; i++)); do sep+="─"; done
    printf '%s%s%s' "${TUI_DIM}" "$sep" "${TUI_RESET}"
}

#==============================================================================
# 搜索框 (聚焦于搜索面板时)
#==============================================================================
tui_render_search_box() {
    local cols
    cols=$(get_cols)
    local query="${LXMS_STATE_SEARCH_QUERY:-}"

    tui_goto 3 1
    printf '%s' "${TUI_CLR_LINE}"

    # 焦点状态
    local focus_marker="  "
    if [[ "${TUI_FOCUS_PANEL:-list}" == "search" ]]; then
        focus_marker="${TUI_FG_CYAN}▸ ${TUI_RESET}"
    fi

    printf '%s%s🔍 搜索: %s' \
        "$focus_marker" "${TUI_BOLD}${TUI_FG_CYAN}" "${TUI_RESET}"

    # 输入框
    if [[ -n "$query" ]]; then
        printf '%s%s%s' "${TUI_BG_BLUE}${TUI_FG_WHITE}" "$query" "${TUI_RESET}"
        printf '%s│%s' "${TUI_FG_CYAN}" "${TUI_RESET}"
    else
        printf '%s(按 / 输入关键词)%s' "${TUI_DIM}" "${TUI_RESET}"
    fi

    # 源和音质
    printf '  %s源:%s%s%s  ' \
        "${TUI_DIM}" "${TUI_RESET}" \
        "${TUI_FG_CYAN}" "${CURRENT_SOURCE:-netease}"
    printf '%s音:%s%s%s  ' \
        "${TUI_DIM}" "${TUI_RESET}" \
        "${TUI_FG_CYAN}" "${DEFAULT_QUALITY:-flac}"
}

#==============================================================================
# 列表渲染
#
# 状态变量:
#   LXMS_PLAYLIST        - 歌曲数组 (元素 "name|artist|album|duration|song_id|quality|cover|quals|play_url")
#   LXMS_SELECTED_INDEX  - 当前选中项
#   LXMS_PLAYING_INDEX   - 当前播放项 (-1 表示无)
#==============================================================================
tui_render_list() {
    local start_row="${1:-4}"
    local height="${2:-18}"
    local cols="${3:-$(get_cols)}"
    local list_w="${4:-48}"

    # 标题
    tui_goto "${start_row}" 1
    printf '%s' "${TUI_CLR_LINE}"
    local total="${#LXMS_PLAYLIST[@]}"
    printf '%s%s搜索结果 (%d 首)%s' \
        "${TUI_BOLD}" "${TUI_FG_CYAN}" "$total" "${TUI_RESET}"

    # 列宽自适应
    if [[ "$cols" -ge 100 ]]; then
        list_w=$((cols * 45 / 100))
    else
        list_w=$cols
    fi

    local count=0
    local i
    for ((i = 0; i < total && count < height - 2; i++)); do
        local track="${LXMS_PLAYLIST[i]}"
        local item row
        # 格式: "name|artist|album|duration|song_id|quality|cover|quals|play_url"
        IFS='|' read -r name artist album duration song_id quality cover quals play_url <<< "$track"
        # 反转义前翻未显示的序号
        if [[ -z "$name" ]]; then continue; fi

        row=$((start_row + 1 + count))
        count=$((count + 1))
        tui_goto "${row}" 1
        printf '%s' "${TUI_CLR_LINE}"

        # 播放标记 / 高亮
        local prefix="  "
        if [[ "$i" == "${LXMS_PLAYING_INDEX:--1}" ]]; then
            prefix="${TUI_FG_GREEN}▶ ${TUI_RESET}"
        fi

        local highlight=""
        local unhighlight=""
        if [[ "$i" == "${LXMS_SELECTED_INDEX:-0}" ]]; then
            highlight="${TUI_INVERT}${TUI_BG_BLUE}${TUI_FG_WHITE}"
            unhighlight="${TUI_RESET}"
        fi

        # 序号
        printf '%s%s%s%s ' "$prefix" "$highlight" \
            "$(printf '%2d' "$i")" "$unhighlight"

        # 标题 (截断到 fit)
        local display_name="$name"
        local max_name=$((list_w - 14))
        if [[ ${#display_name} -gt $max_name && $max_name -gt 3 ]]; then
            display_name="${display_name:0:$((max_name - 1))}…"
        fi

        # 歌手
        local display_artist="$artist"
        local max_artist=$((max_name / 2))
        if [[ ${#display_artist} -gt $max_artist && $max_artist -gt 3 ]]; then
            display_artist="${display_artist:0:$((max_artist - 1))}…"
        fi

        printf '%s%s%s%s - %s%s%s ' \
            "$highlight" "$display_name" "$unhighlight" \
            "$highlight" "$display_artist" "$unhighlight"

        # 音质标签 (右对齐)
        local q_label
        case "${quality:-}" in
            hires) q_label="${TUI_FG_YELLOW}HRes${TUI_RESET}" ;;
            flac)  q_label="${TUI_FG_CYAN}FLAC${TUI_RESET}" ;;
            320)   q_label="${TUI_FG_GREEN}HQ${TUI_RESET}" ;;
            128)   q_label="${TUI_FG_GRAY}SQ${TUI_RESET}" ;;
            *)     q_label="${TUI_FG_GRAY}---${TUI_RESET}" ;;
        esac
        printf '%s\n' "$q_label"
    done

    # 底部提示
    if [[ $count -gt 0 ]]; then
        tui_goto $((start_row + height - 1)) 1
        printf '%s' "${TUI_CLR_LINE}"
        printf '%s↑↓:移动 Enter:播放 Space:暂停 /:搜索 q:退出%s' \
            "${TUI_DIM}" "${TUI_RESET}"
    fi
}

#==============================================================================
# 详情区 (右侧)
#==============================================================================
tui_render_detail() {
    local start_row="${1:-4}"
    local cols="${2:-$(get_cols)}"
    local detail_w="${3:-48}"

    local playing="${LXMS_PLAYING_INDEX:--1}"

    # 封面区
    if [[ "$playing" -ge 0 ]] && [[ "${LXMS_SHOW_COVER:-1}" == "1" ]]; then
        local track="${LXMS_PLAYLIST[playing]}"
        local cover
        IFS='|' read -r _ _ _ _ _ _ cover _ _ <<< "$track"
        if [[ -n "$cover" ]] && [[ "$cover" != "null" ]]; then
            if ! tui_render_image "$cover" "${start_row}" 1 medium 2>/dev/null; then
                tui_render_cover_placeholder "${start_row}" 1 20 8
            fi
        else
            tui_render_cover_placeholder "${start_row}" 1 20 8
        fi
    fi

    local row=$((start_row + 8))

    # 元数据
    if [[ "$playing" -ge 0 ]]; then
        local track="${LXMS_PLAYLIST[playing]}"
        local name artist album duration quality
        IFS='|' read -r name artist album duration _ quality _ _ <<< "$track"

        tui_goto "${row}" 1
        printf '%s%s%s%s' "${TUI_BOLD}${TUI_FG_WHITE}" "$name" "${TUI_RESET}" ""
        row=$((row + 1))

        if [[ -n "$artist" ]]; then
            tui_goto "${row}" 1
            printf '%s歌手:%s %s%s\n' "${TUI_DIM}" "${TUI_RESET}" "$artist"
            row=$((row + 1))
        fi

        if [[ -n "${album:-}" ]]; then
            tui_goto "${row}" 1
            printf '%s专辑:%s %s\n' "${TUI_DIM}" "${TUI_RESET}" "$album"
            row=$((row + 1))
        fi

        if [[ -n "${duration:-}" ]]; then
            tui_goto "${row}" 1
            printf '%s时长:%s %s\n' "${TUI_DIM}" "${TUI_RESET}" "$duration"
            row=$((row + 1))
        fi

        # 音质
        tui_goto "${row}" 1
        printf '%s音质:%s ' "${TUI_DIM}" "${TUI_RESET}"
        local q_full
        case "${quality:-}" in
            hires) q_full="${TUI_FG_YELLOW}Hi-Res 24bit${TUI_RESET}" ;;
            flac)  q_full="${TUI_FG_CYAN}FLAC 无损${TUI_RESET}" ;;
            320)   q_full="${TUI_FG_GREEN}HQ 320kbps${TUI_RESET}" ;;
            128)   q_full="${TUI_FG_GRAY}SQ 128kbps${TUI_RESET}" ;;
            *)     q_full="${TUI_FG_GRAY}未知${TUI_RESET}" ;;
        esac
        printf '%s\n' "$q_full"
        row=$((row + 1))
    fi

    # 进度条
    tui_goto "${row}" 1
    printf '%s进度%s ' "${TUI_DIM}" "${TUI_RESET}"
    local current="${LXMS_STATE_PROGRESS_C:-0}"
    local total="${LXMS_STATE_PROGRESS_T:-0}"
    local percent=0
    if [[ "$total" -gt 0 ]]; then
        percent=$((current * 100 / total))
    fi
    local bar_w=20
    local filled=$((percent * bar_w / 100))
    printf '%s[' "${TUI_FG_GRAY}"
    local j
    for ((j = 0; j < filled; j++)); do printf '%s▰%s' "${TUI_FG_GREEN}" "${TUI_RESET}"; done
    for ((j = filled; j < bar_w; j++)); do printf ' '; done
    printf '%s] ' "${TUI_FG_GRAY}"
    printf '%s%02d:%02d%s / %s%02d:%02d%s' \
        "${TUI_BOLD}" "$((current/60))" "$((current%60))" "${TUI_RESET}" \
        "${TUI_DIM}" "$((total/60))" "$((total%60))" "${TUI_RESET}"
}

#==============================================================================
# vim-style 键盘操作接口 (供主事件循环调用)
#
# 每个操作函数返回:
#   0 = 已处理 (重新渲染)
#   1 = 未处理
#   2 = 退出
#==============================================================================
tui_op_quit() { return 2; }
tui_op_back() { return 2; }

tui_op_move_up() {
    local n=${#LXMS_PLAYLIST[@]}
    local sel=${LXMS_SELECTED_INDEX:-0}
    sel=$((sel - 1))
    [[ $sel -lt 0 ]] && sel=0
    LXMS_SELECTED_INDEX=$sel
    return 0
}

tui_op_move_down() {
    local n=${#LXMS_PLAYLIST[@]}
    local sel=${LXMS_SELECTED_INDEX:-0}
    sel=$((sel + 1))
    [[ $n -gt 0 && $sel -ge $n ]] && sel=$((n - 1))
    [[ $n -eq 0 ]] && sel=0
    LXMS_SELECTED_INDEX=$sel
    return 0
}

tui_op_move_top() { LXMS_SELECTED_INDEX=0; return 0; }
tui_op_move_bottom() {
    local n=${#LXMS_PLAYLIST[@]}
    [[ $n -gt 0 ]] && LXMS_SELECTED_INDEX=$((n - 1))
    return 0
}

tui_op_play_selected() {
    # 触发主循环处理: do_play from CLi-side
    return 1
}

tui_op_rerender() { tui_render; return 0; }

#==============================================================================
# 主渲染函数
#
# 布局 (宽屏 cols >= 100):
#   行 1     : 标题 + 网络 + 音量
#   行 2     : 分隔
#   行 3     : 搜索框 (focus 时显示)
#   行 4-(n-2): 列表 (左 45%) + 详情 (右 55%)
#   行 (n-1) : 提示
#
# 布局 (窄屏 cols < 100):
#   行 1     : 标题 + 状态
#   行 2     : 搜索框
#   行 3-(n-1): 列表 (全宽)
#   底部     : 详情 (横向压缩)
#==============================================================================
tui_render() {
    local cols lines
    cols=$(get_cols)
    lines=$(get_lines)

    tui_clear_screen
    tui_goto 1 1

    # 隐藏光标
    printf '%s' "${TUI_CURSOR_HIDE}"

    # 头部 (2 行)
    tui_render_header

    # 搜索框 (1 行)
    tui_render_search_box

    # 主区域 (从第 4 行到最后)
    local main_start=4
    local main_height=$((lines - main_start - 1))

    if [[ "$cols" -ge 100 ]]; then
        # 宽屏: 左右分栏
        local list_w=$((cols * 45 / 100))
        local detail_w=$((cols - list_w - 1))

        # 注册区域供鼠标命中
        input_clear_regions
        input_register_region "list" "${main_start}" 1 "${main_height}" "${list_w}"
        input_register_region "detail" "${main_start}" "$((list_w + 1))" "${main_height}" "${detail_w}"

        tui_render_list "${main_start}" "${main_height}" "${cols}" "${list_w}"
        tui_render_detail "${main_start}" "${detail_w}"
    else
        # 窄屏: 列表占 60%, 详情占 40%
        local list_h=$((main_height * 6 / 10))
        local detail_h=$((main_height - list_h))

        input_clear_regions
        input_register_region "list" "${main_start}" 1 "${list_h}" "${cols}"
        input_register_region "detail" $((main_start + list_h)) 1 "${detail_h}" "${cols}"

        tui_render_list "${main_start}" "${list_h}" "${cols}" "${cols}"
        tui_render_detail $((main_start + list_h)) "${cols}" "${cols}"
    fi

    # 底部提示行
    tui_goto "${lines}" 1
    printf '%s' "${TUI_CLR_LINE}"
    printf '%s%s%s 主题:%s | q:退出 ?:帮助' \
        "${TUI_DIM}" "${LXMS_HELP_HINT:-按 / 搜索}" "${TUI_RESET}" \
        "${TUI_THEME_NAME}"
}

#==============================================================================
# 清理 (退出 TUI 模式)
#==============================================================================
tui_cleanup() {
    printf '%s%s%s' "${TUI_ALT_OFF}" "${TUI_CURSOR_SHOW}" "${TUI_RESET}"
    # 把 LXMS_PLAYING_INDEX 暴露给 lx-music-shell (从 TUI 主循环)
}

#==============================================================================
# 应用主题初始化 (默认 dark)
#==============================================================================
tui_init_theme() {
    if [[ "${LXMS_TUI_THEME:-}" =~ ^(dark|green|light|mono)$ ]]; then
        TUI_THEME_NAME="${BASH_REMATCH[1]}"
    fi
}

tui_init_theme