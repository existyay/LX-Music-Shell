#!/usr/bin/env bash
#==============================================================================
# LX-Music-Shell TUI 渲染模块 (v2.3 - 美化版)
#
# 设计参考:
#   - references/go-musicfox : vim 风格键盘 + 视觉设计语言
#   - references/bilibili-tui  : 面板布局 + 颜色主题
#
# v2.3 改进:
#   - 圆角 / 双线 / 单线 三套边框 (按区域语义选择)
#   - 顶部 2 行标题区 (Logo + 状态条 分开)
#   - 整齐对齐的列表 (歌名用粗体,歌手用小灰)
#   - 彩色音质芯片 (背景色块)
#   - 3D 边框封面占位符
#   - 双色进度条 + 当前时间标记
#   - 用户级别标题 (大号颜色) + 状态图标
#==============================================================================

[[ -n "${LXMS_TUI_LOADED:-}" ]] && return 0
readonly LXMS_TUI_LOADED=1

#==============================================================================
# ANSI 常量
#==============================================================================
readonly _T_ESC=$'\033'

# 光标与屏幕
readonly TUI_CURSOR_HIDE="${_T_ESC}[?25l"
readonly TUI_CURSOR_SHOW="${_T_ESC}[?25h"
readonly TUI_ALT_ON="${_T_ESC}[?1049h"
readonly TUI_ALT_OFF="${_T_ESC}[?1049l"
readonly TUI_CLEAR="${_T_ESC}[2J${_T_ESC}[H"
readonly TUI_CLR_LINE="${_T_ESC}[2K"

# 基础样式
# 基础样式
# shellcheck disable=SC2034  # 这些是常量,供后续扩展用
readonly TUI_RESET="${_T_ESC}[0m"
readonly TUI_BOLD="${_T_ESC}[1m"
readonly TUI_DIM="${_T_ESC}[2m"
readonly TUI_ITALIC="${_T_ESC}[3m"
readonly TUI_UNDERLINE="${_T_ESC}[4m"
readonly TUI_INVERT="${_T_ESC}[7m"

# 前景色 (256色 + 调色板)
# shellcheck disable=SC2034
readonly TUI_FG_BLACK="${_T_ESC}[30m"
readonly TUI_FG_RED="${_T_ESC}[31m"
readonly TUI_FG_GREEN="${_T_ESC}[32m"
readonly TUI_FG_YELLOW="${_T_ESC}[33m"
readonly TUI_FG_BLUE="${_T_ESC}[34m"
readonly TUI_FG_MAGENTA="${_T_ESC}[35m"
readonly TUI_FG_CYAN="${_T_ESC}[36m"
readonly TUI_FG_WHITE="${_T_ESC}[37m"
readonly TUI_FG_GRAY="${_T_ESC}[90m"
readonly TUI_FG_ORANGE="${_T_ESC}[38;5;214m"
readonly TUI_FG_PINK="${_T_ESC}[38;5;205m"
readonly TUI_FG_LAVENDER="${_T_ESC}[38;5;183m"

# 背景色
readonly TUI_BG_BLACK="${_T_ESC}[40m"
readonly TUI_BG_BLUE="${_T_ESC}[44m"
readonly TUI_BG_CYAN="${_T_ESC}[46m"
readonly TUI_BG_GRAY="${_T_ESC}[100m"
readonly TUI_BG_ORANGE="${_T_ESC}[48;5;214m"
readonly TUI_BG_GREEN="${_T_ESC}[42m"

# 边框字符 (Unicode Box Drawing)
readonly TUI_BOX_TL_CORNER='╭'  # 圆角左上
readonly TUI_BOX_TR_CORNER='╮'
readonly TUI_BOX_BL_CORNER='╰'
readonly TUI_BOX_BR_CORNER='╯'
readonly TUI_BOX_H_LINE='─'
readonly TUI_BOX_V_LINE='│'
readonly TUI_BOX_T_DOWN='┬'
readonly TUI_BOX_T_UP='┴'
readonly TUI_BOX_T_RIGHT='├'
readonly TUI_BOX_T_LEFT='┤'
readonly TUI_BOX_CROSS='┼'

# 双线边框
readonly TUI_BOX2_TL='╔'
readonly TUI_BOX2_TR='╗'
readonly TUI_BOX2_BL='╚'
readonly TUI_BOX2_BR='╝'
readonly TUI_BOX2_H='═'
readonly TUI_BOX2_V='║'

#==============================================================================
# 主题系统 (dark 默认)
#==============================================================================
TUI_THEME_NAME="${LXMS_TUI_THEME:-dark}"
TUI_USE_24BIT_COLOR=0

# 检测 24bit 真彩色支持
tui_init_color_mode() {
    if [[ "${COLORTERM:-}" == *truecolor* ]] || \
       [[ "${COLORTERM:-}" == *24bit* ]]; then
        TUI_USE_24BIT_COLOR=1
    fi
}
tui_init_color_mode

# 主题色定义 (返回 bg_color|fg_color|accent|muted|highlight)
_tui_get_theme_colors() {
    case "${TUI_THEME_NAME:-dark}" in
        green)
            printf '45|39|36|90|42'  # 黑底/青/亮/灰/绿
            ;;
        light)
            printf '47;37|30|35|90|44'  # 白底/黑字
            ;;
        mono)
            printf '40;100|37|37;90|90;107'  # 单色
            ;;
        dark|*)
            printf '40;100|255;255;255|44;255;255;255|99;255;255;255|45;255;255;255'
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
# 工具: 光标定位 + 字符宽度计算
#==============================================================================
tui_goto() {
    printf '%s[%d;%dH' "${_T_ESC}" "$1" "$2"
}

tui_clear_screen() {
    printf '%s%s' "${TUI_ALT_ON}" "${TUI_CLEAR}"
}

# 在指定 (row, col) 打印一行填充到指定宽度 (处理中文双宽)
tui_print_row() {
    local row="$1" col="$2" text="$3" width="$4"
    tui_goto "$row" "$col"
    printf '%s' "$text"
    # 不强制对齐 (因为中文宽度计算复杂)
}

# 计算字符串终端显示宽度 (纯 bash, 快)
# ASCII=1 列; CJK 统一表意文字/全角/emoji=2 列; 其他多字节=1 列
tui_str_width() {
    local text="$1"
    local width=0 i cp
    for ((i = 0; i < ${#text}; i++)); do
        printf -v cp '%d' "'${text:i:1}" 2>/dev/null || cp=0
        if ((cp < 128)); then
            ((width += 1))
        elif ((cp >= 0x2E80 && cp <= 0x9FFF)) || \
             ((cp >= 0xF900 && cp <= 0xFAFF)) || \
             ((cp >= 0xFF00 && cp <= 0xFF60)) || \
             ((cp >= 0x20000)) || \
             ((cp >= 0x1F300 && cp <= 0x1FAFF)); then
            ((width += 2))
        else
            ((width += 1))
        fi
    done
    printf '%d' "$width"
}

# 右侧填充空格到显示宽度 N (不截断)
tui_pad() {
    local text="$1" target="$2"
    local w
    w=$(tui_str_width "$text")
    printf '%s' "$text"
    if ((w < target)); then
        printf '%*s' $((target - w)) ''
    fi
}

# 截断到显示宽度 N (超出加 …), 返回新字符串
tui_trunc() {
    local text="$1" target="$2"
    local w
    w=$(tui_str_width "$text")
    if ((w <= target)); then
        printf '%s' "$text"
        return
    fi
    local out="" cw=0 i cp ch
    for ((i = 0; i < ${#text}; i++)); do
        ch="${text:i:1}"
        printf -v cp '%d' "'$ch" 2>/dev/null || cp=0
        if ((cp < 128)); then cw=$((cw + 1)); else cw=$((cw + 2)); fi
        ((cw > target - 1)) && break
        out+="$ch"
    done
    printf '%s…' "$out"
}

#==============================================================================
# 图片渲染 (kitty / iTerm2 / Sixel)
#==============================================================================
_tui_image_protocol=""

tui_render_image() {
    local url="$1" row="${2:-1}" col="${3:-1}"

    if [[ -z "$url" || "$url" == "null" ]]; then
        return 1
    fi

    # 探测协议
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
            printf '\033_Ga=T,f=100,t=f;%s\033\\' "$url"
            ;;
        iTerm)
            local b64
            b64=$(printf '%s' "$url" | base64 2>/dev/null || true)
            printf '\033]1337;File=inline=1;preserveAspectRatio=1:%s\a' "$b64"
            ;;
        sixel)
            printf '%s[image: %s]%s' "${TUI_DIM}" "$url" "${TUI_RESET}"
            ;;
        *)
            return 1
            ;;
    esac
}

# 3D 阴影立体封面占位符
tui_render_cover_placeholder() {
    local row="${1:-1}"
    local col="${2:-1}"
    local w="${3:-22}"
    local h="${4:-10}"

    # 上边框 (圆角)
    tui_goto "${row}" "${col}"
    printf '%s%s' "${TUI_FG_CYAN}" "${TUI_BOX_TL_CORNER}"
    for ((i = 0; i < w - 2; i++)); do
        printf '%s' "${TUI_BOX_H_LINE}"
    done
    printf '%s%s\n' "${TUI_BOX_TR_CORNER}" "${TUI_RESET}"

    # 中间行
    for ((i = 1; i < h - 1; i++)); do
        tui_goto $((row + i)) "${col}"
        printf '%s%s' "${TUI_FG_CYAN}" "${TUI_BOX_V_LINE}"
        # 内容 (居中显示 ♪♫♪)
        if [[ $i -eq $((h / 2 - 1)) ]]; then
            # ♪ 为宽字符, label 实际宽度 ~11
            local label="♪ Music ♪"
            local pad_left=$(( (w - 2 - 11) / 2 ))
            [[ $pad_left -lt 0 ]] && pad_left=0
            local pad_right=$(( w - 2 - pad_left - 11 ))
            [[ $pad_right -lt 0 ]] && pad_right=0
            printf '%*s' "$pad_left" ''
            printf '%s%s%s' "${TUI_FG_MAGENTA}" "$label" "${TUI_RESET}"
            printf '%*s' "$pad_right" ''
        elif [[ $i -eq $((h / 2)) ]]; then
            # "♫ album cover ♫" 显示宽 17
            local label2="♫ album cover ♫"
            local left_pad=$(( (w - 2 - 17) / 2 ))
            [[ $left_pad -lt 0 ]] && left_pad=0
            local right_pad=$(( w - 2 - left_pad - 17 ))
            [[ $right_pad -lt 0 ]] && right_pad=0
            printf '%*s' "$left_pad" ''
            printf '%s%s%s' "${TUI_FG_CYAN}${TUI_DIM}" "$label2" "${TUI_RESET}"
            printf '%*s' "$right_pad" ''
        else
            printf '%*s' "$((w - 2))" ''
        fi
        printf '%s%s\n' "${TUI_FG_CYAN}" "${TUI_BOX_V_LINE}"
    done

    # 下边框 (圆角)
    tui_goto $((row + h - 1)) "${col}"
    printf '%s%s' "${TUI_FG_CYAN}" "${TUI_BOX_BL_CORNER}"
    for ((i = 0; i < w - 2; i++)); do
        printf '%s' "${TUI_BOX_H_LINE}"
    done
    printf '%s%s' "${TUI_BOX_BR_CORNER}" "${TUI_RESET}"
}

#==============================================================================
# 顶部 (3 行):
#   行 1: 大标题 + 网络 + 音量
#   行 2: 顶部边框 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#   行 3: 帮助提示 (快捷键)
#==============================================================================
tui_render_header() {
    local cols lines
    cols=$(get_cols)
    lines=$(get_lines)

    # 行 1: 标题区
    tui_goto 1 1
    printf '%s' "${TUI_CLR_LINE}"

    # Logo + 名称 (连续字符串, 可搜索)
    printf '%s ♪ %s' "${TUI_FG_MAGENTA}${TUI_BOLD}" "${TUI_RESET}"
    printf '%sLX-Music-Shell%s ' "${TUI_FG_CYAN}${TUI_BOLD}" "${TUI_RESET}"
    printf '%s%sv%s%s ' "${TUI_DIM}" "${TUI_FG_GRAY}" "${LXMS_STATE_VERSION:-2.3}" "${TUI_RESET}"

    # 右侧状态: 网络 + 音量 (右对齐, 共 ~27 列)
    local status_col=$((cols - 32))
    [[ $status_col -lt 40 ]] && status_col=40
    # 网络状态 (带图标)
    case "${LXMS_STATE_NETWORK:-connected}" in
        connected)
            tui_goto 1 "$status_col"
            printf '%s●%s %s已连接%s  ' \
                "${TUI_FG_GREEN}" "${TUI_RESET}" "${TUI_DIM}" "${TUI_RESET}"
            ;;
        disconnected)
            tui_goto 1 "$status_col"
            printf '%s●%s %s已断开%s  ' \
                "${TUI_FG_RED}" "${TUI_RESET}" "${TUI_DIM}" "${TUI_RESET}"
            ;;
        checking)
            tui_goto 1 "$status_col"
            printf '%s○%s %s检测中%s  ' \
                "${TUI_FG_YELLOW}" "${TUI_RESET}" "${TUI_DIM}" "${TUI_RESET}"
            ;;
    esac

    # 音量
    local vol="${LXMS_STATE_VOLUME:-80}"
    local filled=$((vol / 10))
    printf '%s音量%s ' "${TUI_FG_GRAY}" "${TUI_RESET}"
    local i
    for ((i = 0; i < 10; i++)); do
        if [[ $i -lt $filled ]]; then
            printf '%s%s%s' "${TUI_BG_CYAN}${TUI_FG_CYAN}" "▰" "${TUI_RESET}"
        else
            printf '%s%s%s' "${TUI_DIM}" "▱" "${TUI_RESET}"
        fi
    done
    printf ' %s%d%%%s' "${TUI_BOLD}" "$vol" "${TUI_RESET}"

    # 行 2: 横向细双线分隔
    tui_goto 2 1
    printf '%s' "${TUI_CLR_LINE}"
    printf '%s' "${TUI_FG_GRAY}${TUI_DIM}"
    local sep=''
    for ((i = 0; i < cols; i++)); do sep+="─"; done
    printf '%s%s\n' "$sep" "${TUI_RESET}"

    # 行 3: 搜索框 (跟原版类似, 但用更明显的视觉)
    tui_render_search_box
}

#==============================================================================
# 搜索框 (行 3) - 美化: 高亮输入区
#==============================================================================
tui_render_search_box() {
    local cols
    cols=$(get_cols)
    local query="${LXMS_STATE_SEARCH_QUERY:-}"

    tui_goto 3 1
    printf '%s' "${TUI_CLR_LINE}"

    # 焦点指示
    local focus_marker="  "
    if [[ "${TUI_FOCUS_PANEL:-list}" == "search" ]]; then
        focus_marker="${TUI_FG_CYAN}${TUI_BOLD}▸ ${TUI_RESET}"
    fi

    # 🔍 + 搜索标签
    printf '%s%s 🔍 搜索: %s' \
        "$focus_marker" "${TUI_BOLD}${TUI_FG_CYAN}" "${TUI_RESET}"

    # 输入框 (边框)
    printf '%s╭' "${TUI_FG_GRAY}"
    if [[ -n "$query" ]]; then
        printf '%s%s%s' "${TUI_BG_BLUE}${TUI_FG_WHITE}" "$query" "${TUI_RESET}"
        # 闪烁光标
        printf '|%s' "${TUI_FG_CYAN}"
    else
        printf '%s(按 / 输入关键词)%s' "${TUI_DIM}" "${TUI_FG_GRAY}"
    fi
    printf '╮%s ' "${TUI_RESET}"

    # 右侧过滤选项 (彩色 chip)
    # 源
    printf '%s[s]源%s' "${TUI_DIM}" "${TUI_RESET}"
    printf '%s%s%s%s' \
        "${TUI_BG_BLUE}${TUI_FG_WHITE}${TUI_BOLD}" \
        " ${CURRENT_SOURCE:-netease} " \
        "${TUI_RESET}" \
        "${TUI_RESET}"

    # 音质
    printf ' %s[q]音%s' "${TUI_DIM}" "${TUI_RESET}"
    local q_color="${TUI_FG_YELLOW}"
    case "${DEFAULT_QUALITY:-flac}" in
        hires) q_color="${TUI_FG_PINK}" ;;
        320)   q_color="${TUI_FG_GREEN}" ;;
        128)   q_color="${TUI_FG_GRAY}" ;;
    esac
    printf '%s%s%s%s' \
        "${TUI_BG_GRAY}${q_color}${TUI_BOLD}" \
        " ${DEFAULT_QUALITY:-flac} " \
        "${TUI_RESET}" \
        "${TUI_RESET}"
}

#==============================================================================
# 列表区 (从行 4 开始)
#
# 状态: LXMS_PLAYLIST (9 列: name|artist|album|duration|song_id|quality|cover|quals|play_url)
#       LXMS_SELECTED_INDEX
#       LXMS_PLAYING_INDEX
#==============================================================================
tui_render_list() {
    local start_row="${1:-4}"
    local height="${2:-18}"
    local cols="${3:-$(get_cols)}"

    # 列表占的列宽 (自适应)
    local list_w
    if [[ "$cols" -ge 100 ]]; then
        list_w=$((cols * 48 / 100))  # 宽屏: 列表占 48%
    else
        list_w=$((cols - 4))  # 窄屏: 用满宽
    fi

    # 行布局 (显示列): │ + sp + 标记(2) + 序号(2) + sp + 歌名(N) + sp + 歌手(12) + sp + 时长(5) + sp + 芯片(7) + sp + │
    # 总宽 = N + 36 = list_w
    local name_w=$((list_w - 36))
    [[ $name_w -lt 6 ]] && name_w=6

    local total="${#LXMS_PLAYLIST[@]}"

    # 列表头 (圆角边框 + 标题内嵌)
    local title=" 列表 (${total}) "
    local title_dw
    title_dw=$(tui_str_width "$title")
    local pad=$((list_w - title_dw - 2))
    [[ $pad -lt 0 ]] && pad=0

    tui_goto "${start_row}" 1
    printf '%s' "${TUI_CLR_LINE}"
    printf '%s%s%s' "${TUI_FG_CYAN}${TUI_BOLD}" "${TUI_BOX_TL_CORNER}" "${TUI_RESET}"
    printf '%s%s%s' "${TUI_FG_CYAN}${TUI_BOLD}" "${title}" "${TUI_RESET}"
    local j
    printf '%s' "${TUI_FG_CYAN}"
    for ((j = 0; j < pad; j++)); do printf '%s' "${TUI_BOX_H_LINE}"; done
    printf '%s%s\n' "${TUI_BOX_TR_CORNER}" "${TUI_RESET}"

    # 打印一行列表内容: $1=行号 $2=标记 $3=序号 $4=歌名 $5=歌手 $6=时长 $7=芯片文本 $8=芯片色 $9=行背景 $10=歌名样式
    _tui_list_row() {
        local row="$1" marker="$2" idx="$3" name="$4" artist="$5" dur="$6" chip="$7" chip_style="$8" bg="$9" name_style="${10}"
        tui_goto "${row}" 1
        printf '%s' "${TUI_CLR_LINE}"
        # 左边框
        printf '%s%s%s ' "${TUI_FG_CYAN}" "${TUI_BOX_V_LINE}" "${TUI_RESET}"
        # 播放标记
        if [[ "$marker" == "play" ]]; then
            printf '%s%s▶%s ' "${TUI_FG_GREEN}" "${TUI_BOLD}" "${TUI_RESET}"
        else
            printf '  '
        fi
        # 序号
        printf '%s%s%2s%s ' "$bg" "${TUI_FG_YELLOW}${TUI_BOLD}" "$idx" "${TUI_RESET}"
        # 歌名 (显示宽度截断+填充)
        printf '%s%s' "$bg" "$name_style"
        tui_pad "$(tui_trunc "$name" "$name_w")" "$name_w"
        printf '%s ' "${TUI_RESET}"
        # 歌手
        printf '%s%s' "$bg" "${TUI_DIM}"
        tui_pad "$(tui_trunc "$artist" 12)" 12
        printf '%s ' "${TUI_RESET}"
        # 时长
        printf '%s%s' "$bg" "${TUI_DIM}"
        tui_pad "$dur" 5
        printf '%s ' "${TUI_RESET}"
        # 音质芯片 (定宽 7 显示列)
        if [[ -n "$chip_style" ]]; then
            printf '%s%s%s%s' "$chip_style" "$chip" "${TUI_RESET}" "$bg"
            local chip_dw
            chip_dw=$(tui_str_width "$chip")
            printf '%*s' $((7 - chip_dw)) ''
        else
            printf '%s' "${TUI_DIM}"
            tui_pad "$chip" 7
        fi
        printf '%s ' "${TUI_RESET}"
        # 右边框
        printf '%s%s%s\n' "${TUI_FG_CYAN}" "${TUI_BOX_V_LINE}" "${TUI_RESET}"
    }

    # 列标题行
    _tui_list_row $((start_row + 1)) "none" "#" "歌曲" "歌手" "时长" " 音质  " "" "" "${TUI_FG_CYAN}${TUI_BOLD}"

    # 列表项
    local count=0
    local i
    for ((i = 0; i < total && count < height - 4; i++)); do
        local track="${LXMS_PLAYLIST[i]}"
        local name artist album duration song_id quality
        IFS='|' read -r name artist album duration song_id quality _ _ <<< "$track"

        local marker="none"
        [[ "$i" == "${LXMS_PLAYING_INDEX:--1}" ]] && marker="play"

        local bg=""
        [[ "$i" == "${LXMS_SELECTED_INDEX:-0}" ]] && bg="${TUI_BG_BLUE}"

        # 音质芯片 (彩色背景)
        local chip chip_style
        case "${quality:-}" in
            hires) chip=" HiRes "; chip_style="${TUI_BG_ORANGE}${TUI_FG_WHITE}${TUI_BOLD}" ;;
            flac)  chip=" FLAC ";  chip_style="${TUI_BG_CYAN}${TUI_FG_WHITE}${TUI_BOLD}" ;;
            320)   chip=" HQ ";    chip_style="${TUI_BG_GREEN}${TUI_FG_WHITE}${TUI_BOLD}" ;;
            128)   chip=" SQ ";    chip_style="${TUI_BG_GRAY}${TUI_FG_WHITE}${TUI_BOLD}" ;;
            *)     chip="---";     chip_style="" ;;
        esac

        _tui_list_row $((start_row + 2 + count)) "$marker" "$i" "$name" "$artist" "$duration" "$chip" "$chip_style" "$bg" "${TUI_BOLD}"
        count=$((count + 1))
    done

    # 列表底部边框
    local bottom_row=$((start_row + count + 2))
    tui_goto "${bottom_row}" 1
    printf '%s' "${TUI_CLR_LINE}"
    printf '%s%s' "${TUI_FG_CYAN}" "${TUI_BOX_BL_CORNER}"
    for ((j = 0; j < list_w - 2; j++)); do printf '%s' "${TUI_BOX_H_LINE}"; done
    printf '%s%s\n' "${TUI_BOX_BR_CORNER}" "${TUI_RESET}"

    # 底部帮助提示 (单独一行)
    local hint_row=$((bottom_row + 1))
    tui_goto "${hint_row}" 1
    printf '%s' "${TUI_CLR_LINE}"
    printf '%s%s%s[j/k]↑/↓ [Enter]播放 [Space]暂停 [/]搜索 [q]退出%s' \
        "${TUI_DIM}" "${TUI_FG_CYAN}" "${TUI_BOLD}" "${TUI_RESET}"
}

#==============================================================================
tui_render_detail() {
    local start_row="${1:-4}"
    local cols="${2:-$(get_cols)}"
    local max_row="${3:-$(get_lines)}"

    local playing="${LXMS_PLAYING_INDEX:--1}"
    local detail_w
    if [[ "$cols" -ge 100 ]]; then
        detail_w=$((cols - (cols * 48 / 100) - 4))
    else
        detail_w=$((cols - 4))
    fi

    local row="${start_row}"
    local cover_rendered=0

    # ---- 封面区 (空间不足时自动跳过, 防滚屏) ----
    if [[ "$playing" -ge 0 ]] && [[ "${LXMS_SHOW_COVER:-1}" == "1" ]] && \
       [[ $((max_row - start_row)) -ge 20 ]]; then
        local track="${LXMS_PLAYLIST[playing]}"
        local cover
        IFS='|' read -r _ _ _ _ _ _ cover _ _ <<< "$track"

        # 列对齐 (详情的封面缩进, 与列表对齐)
        local cover_col=2
        if [[ "$cols" -ge 100 ]]; then
            cover_col=$((cols * 48 / 100 + 3))
        fi

        local cover_w=24
        local cover_h=8

        if [[ -n "$cover" ]] && [[ "$cover" != "null" ]]; then
            if ! tui_render_image "$cover" "$row" "$cover_col" 2>/dev/null; then
                tui_render_cover_placeholder "$row" "$cover_col" "$cover_w" "$cover_h"
            fi
        else
            tui_render_cover_placeholder "$row" "$cover_col" "$cover_w" "$cover_h"
        fi
        cover_rendered=1
        row=$((row + cover_h + 1))
    fi

    # ---- 元数据区 ----
    if [[ "$playing" -ge 0 ]]; then
        local track="${LXMS_PLAYLIST[playing]}"
        local name artist album duration quality
        IFS='|' read -r name artist album duration _ quality _ _ <<< "$track"

        # 详情框 (圆角)
        local col=1
        if [[ "$cols" -ge 100 ]]; then
            col=$((cols * 48 / 100 + 2))
        else
            col=2
        fi

        # 上边框
        [[ $row -le $max_row ]] || return 0
        tui_goto "$row" $col
        printf '%s╭' "${TUI_FG_LAVENDER}"
        printf '─%.0s' $(seq 1 $((detail_w - 2))) 2>/dev/null
        printf '╮%s\n' "${TUI_RESET}"
        row=$((row + 1))

        # 详情行: │ + sp + 内容(detail_w-4) + sp + │  (显示宽度对齐)
        _tui_detail_row() {
            local drow="$1" content="$2" style="$3"
            [[ $drow -gt $max_row ]] && return 0
            tui_goto "$drow" "$col"
            printf '%s%s%s ' "${TUI_FG_LAVENDER}" "│" "${TUI_RESET}"
            printf '%s' "$style"
            tui_pad "$(tui_trunc "$content" $((detail_w - 4)))" $((detail_w - 4))
            printf '%s ' "${TUI_RESET}"
            printf '%s%s\n' "${TUI_FG_LAVENDER}" "│" "${TUI_RESET}"
        }

        # 歌名
        _tui_detail_row "$row" " ${name}" "${TUI_BOLD}"
        row=$((row + 1))

        # 分隔
        _tui_detail_row "$row" "" ""
        row=$((row + 1))

        # 歌手 / 专辑 / 时长
        if [[ -n "$artist" ]]; then
            _tui_detail_row "$row" "♫ ${artist}" "${TUI_DIM}"
            row=$((row + 1))
        fi
        if [[ -n "${album:-}" ]]; then
            _tui_detail_row "$row" "💿 ${album}" "${TUI_DIM}"
            row=$((row + 1))
        fi
        if [[ -n "${duration:-}" ]]; then
            _tui_detail_row "$row" "⏱  ${duration}" "${TUI_DIM}"
            row=$((row + 1))
        fi

        # 音质 (彩色背景 chip)
        local q_bg q_fg q_label
        case "${quality:-}" in
            hires)
                q_bg="${TUI_BG_ORANGE}"
                q_fg="${TUI_FG_WHITE}${TUI_BOLD}"
                q_label=" HiRes "
                ;;
            flac)
                q_bg="${TUI_BG_CYAN}"
                q_fg="${TUI_FG_WHITE}${TUI_BOLD}"
                q_label=" FLAC "
                ;;
            320)
                q_bg="${TUI_BG_GREEN}"
                q_fg="${TUI_FG_WHITE}${TUI_BOLD}"
                q_label=" HQ "
                ;;
            128)
                q_bg="${TUI_BG_GRAY}"
                q_fg="${TUI_FG_WHITE}${TUI_BOLD}"
                q_label=" SQ "
                ;;
            *)
                q_bg="${TUI_BG_GRAY}"
                q_fg="${TUI_FG_WHITE}${TUI_DIM}"
                q_label=" --- "
                ;;
        esac
        [[ $row -le $max_row ]] || return 0
        tui_goto "$row" $col
        printf '%s%s%s ' "${TUI_FG_LAVENDER}" "│" "${TUI_RESET}"
        # 前缀 "⏵  音质: " 显示宽 9 (⏵=1, 空格×3, 音质=4, :=1)
        printf '%s⏵  音质: %s' "${TUI_DIM}" "${TUI_RESET}"
        printf '%s%s%s%s' "${q_bg}" "${q_fg}" "${q_label}" "${TUI_RESET}"
        local q_label_dw
        q_label_dw=$(tui_str_width "$q_label")
        local q_used=$((1 + 9 + q_label_dw))  # │ + 前缀 + 标签
        printf '%*s' $((detail_w - q_used - 1)) ''
        printf '%s%s\n' "${TUI_FG_LAVENDER}" "│" "${TUI_RESET}"
        row=$((row + 1))

        # 下边框
        [[ $row -le $max_row ]] || return 0
        tui_goto "$row" $col
        printf '%s╰' "${TUI_FG_LAVENDER}"
        printf '─%.0s' $(seq 1 $((detail_w - 2))) 2>/dev/null
        printf '╯%s\n' "${TUI_RESET}"
        row=$((row + 1))
    fi

    # ---- 进度条 ----
    [[ $row -gt $max_row ]] && return 0
    tui_goto "$row" 1
    printf '%s' "${TUI_CLR_LINE}"
    # 居中显示进度条
    local progress_w=40
    local pad_left=$(( (cols - progress_w - 2) / 2 ))
    printf '%*s' "$pad_left" ''

    local current="${LXMS_STATE_PROGRESS_C:-0}"
    local total="${LXMS_STATE_PROGRESS_T:-0}"
    local percent=0
    if [[ "$total" -gt 0 ]]; then
        percent=$((current * 100 / total))
    fi
    local filled=$((percent * progress_w / 100))

    printf '%s进度:%s ' "${TUI_DIM}" "${TUI_RESET}"
    # 时间
    printf '%s%02d:%02d%s' "${TUI_FG_CYAN}${TUI_BOLD}" "$((current/60))" "$((current%60))" "${TUI_RESET}"
    # 进度条
    printf '%s[' "${TUI_FG_GRAY}"
    local j
    for ((j = 0; j < filled; j++)); do
        if [[ $j -lt $((progress_w * 7 / 10)) ]]; then
            printf '%s%s%s' "${TUI_FG_GREEN}${TUI_BOLD}" "▰" "${TUI_RESET}${TUI_FG_GRAY}"
        else
            printf '%s%s%s' "${TUI_FG_YELLOW}" "▰" "${TUI_RESET}${TUI_FG_GRAY}"
        fi
    done
    for ((j = filled; j < progress_w; j++)); do
        printf ' '
    done
    printf ']%s' "${TUI_FG_GRAY}"
    # 总时长
    printf ' %s%02d:%02d%s' "${TUI_FG_CYAN}${TUI_BOLD}" "$((total/60))" "$((total%60))" "${TUI_RESET}"
}

#==============================================================================
# 主渲染: 多区块自适应
#==============================================================================
tui_render() {
    local cols lines
    cols=$(get_cols)
    lines=$(get_lines)

    tui_clear_screen
    tui_goto 1 1
    printf '%s' "${TUI_CURSOR_HIDE}"

    # 头部 (3 行): 行 1 标题, 行 2 分隔, 行 3 搜索
    tui_render_header

    # 主区: 行 4 - 最后行
    local main_start=4
    local main_height=$((lines - main_start - 2))  # 留 2 行给底部帮助行

    if [[ "$cols" -ge 100 ]]; then
        # 宽屏: 左右分栏
        local list_w=$((cols * 48 / 100))
        local detail_start_col=$((list_w + 1))
        local detail_w=$((cols - detail_start_col - 1))

        # 注册区域供鼠标
        input_clear_regions
        input_register_region "list" "${main_start}" 1 "$main_height" "$list_w"
        input_register_region "detail" "${main_start}" "$detail_start_col" "$main_height" "$detail_w"

        tui_render_list "${main_start}" "$main_height" "$cols"
        tui_render_detail "${main_start}" "$cols" "$((lines - 1))"
    else
        # 窄屏: 上下堆叠
        local list_h=$((main_height * 65 / 100))
        local detail_h=$((main_height - list_h))

        input_clear_regions
        input_register_region "list" "${main_start}" 1 "$list_h" "$cols"
        input_register_region "detail" $((main_start + list_h)) 1 "$detail_h" "$cols"

        tui_render_list "${main_start}" "$list_h" "$cols"
        tui_render_detail $((main_start + list_h)) "$cols" "$((lines - 1))"
    fi

    # 底部全局帮助
    tui_goto "${lines}" 1
    printf '%s' "${TUI_CLR_LINE}"
    printf '%s%s 主题:%s%s | %s[q]%s 退出 | %s[?]%s 帮助' \
        "${TUI_DIM}" "${TUI_FG_GRAY}" "${TUI_BOLD}" "$TUI_THEME_NAME" \
        "${TUI_FG_RED}${TUI_BOLD}" "${TUI_RESET}" \
        "${TUI_FG_YELLOW}${TUI_BOLD}" "${TUI_RESET}"
}

#==============================================================================
# vim-style 操作函数 (主事件循环调用)
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

tui_op_play_selected() { return 1; }
tui_op_rerender() { tui_render; return 0; }

#==============================================================================
# 清理
#==============================================================================
tui_cleanup() {
    printf '%s%s%s' "${TUI_ALT_OFF}" "${TUI_CURSOR_SHOW}" "${TUI_RESET}"
}

#==============================================================================
# 主题初始化
#==============================================================================
tui_init_theme() {
    if [[ "${LXMS_TUI_THEME:-}" =~ ^(dark|green|light|mono)$ ]]; then
        TUI_THEME_NAME="${BASH_REMATCH[1]}"
    fi
}

tui_init_theme
tui_init_color_mode