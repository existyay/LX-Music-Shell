#!/usr/bin/env bash
#==============================================================================
# LX-Music-Shell 统一功能型 TUI (v3 重构)
#
# 单一 TUI 状态机 + 完整播放器 UI, 参考 go-musicfox 视觉语言:
#   顶部红标题线 / 副标题 / 主区(菜单 or 搜索+结果) /
#   底部常驻(歌词 + 频谱 + 帮助 + 播放栏 + 进度条)
#
# 屏幕 (UI_SCREEN):
#   menu    - 主菜单
#   search  - 搜索框 + 结果列表 (结果即播放列表)
#   help    - 帮助页
#
# 键盘 (vim 风格) + 鼠标 (SGR 1006) 双输入。
# 歌词由 bash 原生 LRC 解析器驱动 (无 python 子进程), 逐帧便宜。
#
# 状态变量 (由主循环设置):
#   UI_SCREEN, UI_SELECTED, UI_SCROLL_TOP, UI_QUERY
#   PLAYLIST[]          - 9 列轨道: name|artist|album|duration|song_id|quality|cover|quals|url
#   PLAYLIST_INDEX      - 当前播放索引
#   PLAYER_STATUS       - playing|paused|stopped
#   PLAYBACK_POSITION / PLAYBACK_DURATION - 秒
#   VOLUME, PLAY_MODE, NETWORK_STATUS, CURRENT_SOURCE_NAME
#   LXMS_LRC_RAW        - 原始 LRC 文本 (可空)
#==============================================================================

[[ -n "${LXMS_TUI_LOADED:-}" ]] && return 0
readonly LXMS_TUI_LOADED=1

#==============================================================================
# ANSI 常量
#==============================================================================
readonly _T_ESC=$'\033'
readonly T_RESET="${_T_ESC}[0m"
readonly T_BOLD="${_T_ESC}[1m"
readonly T_DIM="${_T_ESC}[2m"
readonly T_INVERT="${_T_ESC}[7m"

readonly T_FG_RED="${_T_ESC}[31m"
readonly T_FG_GREEN="${_T_ESC}[32m"
readonly T_FG_YELLOW="${_T_ESC}[33m"
readonly T_FG_MAGENTA="${_T_ESC}[35m"
readonly T_FG_CYAN="${_T_ESC}[36m"
readonly T_FG_WHITE="${_T_ESC}[37m"
readonly T_FG_GRAY="${_T_ESC}[90m"
readonly T_FG_ORANGE="${_T_ESC}[38;5;214m"
readonly T_FG_PINK="${_T_ESC}[38;5;205m"
readonly T_FG_LIGHT_CYAN="${_T_ESC}[38;5;51m"

readonly T_BG_BLUE="${_T_ESC}[44m"

readonly T_HIDE_CURSOR="${_T_ESC}[?25l"
readonly T_SHOW_CURSOR="${_T_ESC}[?25h"
readonly T_ALT_ON="${_T_ESC}[?1049h"
readonly T_ALT_OFF="${_T_ESC}[?1049l"
readonly T_CLR="${_T_ESC}[2J${_T_ESC}[H"
readonly T_HOME="${_T_ESC}[H"
readonly T_CLR_LINE="${_T_ESC}[2K"

#==============================================================================
# 状态 (默认值, 主循环可覆盖)
#==============================================================================
UI_SCREEN="${UI_SCREEN:-menu}"
UI_SELECTED="${UI_SELECTED:-0}"
UI_SCROLL_TOP="${UI_SCROLL_TOP:-0}"
UI_QUERY="${UI_QUERY:-}"
UI_FOCUS="${UI_FOCUS:-list}"        # list | search (搜索框是否获得键盘焦点)
UI_HELP_PAGE="${UI_HELP_PAGE:-0}"

#==============================================================================
# 主菜单项 (label|action)
#==============================================================================
TUI_MENU_ITEMS=(
    "搜索音乐|search"
    "搜索歌单|playlist_search"
    "今日推荐|recommend"
    "播放列表|playlist"
    "正在播放|playing"
    "切换音质|quality"
    "播放模式|mode"
    "帮助|help"
    "退出|quit"
)

# 选择子菜单 (音源/音质) 由主脚本填充
# shellcheck disable=SC2034  # TUI_SELECT_* 跨文件由 lx-music-shell 填充/读取
TUI_SELECT_ITEMS=()
# shellcheck disable=SC2034  # 由 lx-music-shell 填充/读取
TUI_SELECT_VALUES=()
# shellcheck disable=SC2034  # 由 lx-music-shell 填充/读取
TUI_SELECT_TITLE=""

#==============================================================================
# 工具: 终端尺寸 / 光标 / 字符宽度
#==============================================================================
tui_cols() {
    if [[ -n "${COLUMNS:-}" ]] && [[ "$COLUMNS" =~ ^[0-9]+$ ]]; then printf '%s' "$COLUMNS"; return; fi
    tput cols 2>/dev/null || echo 80
}

tui_lines() {
    if [[ -n "${LINES:-}" ]] && [[ "$LINES" =~ ^[0-9]+$ ]]; then printf '%s' "$LINES"; return; fi
    tput lines 2>/dev/null || echo 24
}

tui_goto() {
    printf '%s[%d;%dH' "${_T_ESC}" "$1" "$2"
}

tui_clr_line() {
    printf '%s' "${T_CLR_LINE}"
}

# 显示宽度: ASCII=1, CJK/全角/emoji=2
tui_width() {
    local text="$1" w=0 i cp
    for ((i = 0; i < ${#text}; i++)); do
        printf -v cp '%d' "'${text:i:1}" 2>/dev/null || cp=0
        if ((cp < 128)); then ((w += 1));
        elif ((cp >= 0x2E80 && cp <= 0x9FFF)) || ((cp >= 0xF900 && cp <= 0xFAFF)) || \
             ((cp >= 0xFF00 && cp <= 0xFF60)) || ((cp >= 0x20000)) || \
             ((cp >= 0x1F300 && cp <= 0x1FAFF)); then ((w += 2));
        else ((w += 1)); fi
    done
    printf '%d' "$w"
}

# 截断到显示宽度 target (超出加 …)
tui_trunc() {
    local text="$1" target="$2" w out="" cw=0 i cp ch
    w=$(tui_width "$text")
    if ((w <= target)); then printf '%s' "$text"; return; fi
    for ((i = 0; i < ${#text}; i++)); do
        ch="${text:i:1}"
        printf -v cp '%d' "'$ch" 2>/dev/null || cp=0
        if ((cp < 128)); then cw=$((cw + 1)); else cw=$((cw + 2)); fi
        ((cw > target - 1)) && break
        out+="$ch"
    done
    printf '%s…' "$out"
}

# 安全返回播放列表长度 (对 set -u / 未声明数组健壮)
tui_list_n() {
    if [[ -n "${PLAYLIST+set}" ]]; then printf '%d' "${#PLAYLIST[@]}"; else printf '0'; fi
}

# 菜单行距: 空间不足时单行排列, 避免菜单项被裁切
tui_menu_step() {
    local start="$1" end="$2" total="${3:-${#TUI_MENU_ITEMS[@]}}"
    if (( (end - start + 1) >= total * 2 - 1 )); then
        printf '2'
    else
        printf '1'
    fi
}

# 当前屏幕可移动条目数
tui_item_count() {
    case "${UI_SCREEN:-menu}" in
        search)         tui_list_n ;;
        source_select|quality_select|playlist_select) printf '%d' "${#TUI_SELECT_ITEMS[@]}" ;;
        playing)        printf '0' ;;
        *)              printf '%d' "${#TUI_MENU_ITEMS[@]}" ;;
    esac
}

# 居中计算左填充 (用于居中打印)
tui_left_pad() {
    local text="$1" total="${2:-$(tui_cols)}" w
    w=$(tui_width "$text")
    local left=$(( (total - w) / 2 ))
    [[ $left -lt 0 ]] && left=0
    printf '%d' "$left"
}

# 打印一行为空串 (右填充到全宽, 用于清除)
tui_blank_row() {
    local row="$1"
    tui_goto "$row" 1
    tui_clr_line
}

# 清空连续区域的所有行 (屏幕切换/列表缩短时避免残留旧内容造成“乱码”)
tui_blank_area() {
    local start="$1" end="$2" row
    for ((row = start; row <= end; row++)); do
        tui_blank_row "$row"
    done
}

#==============================================================================
# 播放模式名称 / 状态图标
#==============================================================================
tui_mode_name() {
    case "${PLAY_MODE:-list}" in
        list)   printf '列表' ;;
        loop)   printf '列表循环' ;;
        single) printf '单曲循环' ;;
        random) printf '随机' ;;
        *)      printf '列表' ;;
    esac
}

tui_state_icon() {
    case "${PLAYER_STATUS:-stopped}" in
        playing)  printf '▶' ;;
        paused)   printf '⏸' ;;
        buffering) printf '⌛' ;;
        *)        printf '⏹' ;;
    esac
}

#==============================================================================
# 歌词: 原生 LRC 解析 (惰性初始化)
#==============================================================================
declare -a TUI_LRC_TIMES=()
declare -a TUI_LRC_TEXTS=()
TUI_LRC_PARSED_FOR=""

# 解析 LXMS_LRC_RAW -> TUI_LRC_TIMES[] / TUI_LRC_TEXTS[]
tui_lyric_parse() {
    local raw="${LXMS_LRC_RAW:-}"
    if [[ -z "$raw" ]]; then
        TUI_LRC_TIMES=(); TUI_LRC_TEXTS=()
        TUI_LRC_PARSED_FOR=""
        return
    fi
    # 若已解析过同一份, 直接返回
    [[ "$TUI_LRC_PARSED_FOR" == "$raw" ]] && return

    TUI_LRC_TIMES=(); TUI_LRC_TEXTS=()
    TUI_LRC_PARSED_FOR="$raw"
    local line
    while IFS= read -r line; do
        # 提取所有 [mm:ss.xx] 时间标签
        local t text mm ss
        while [[ "$line" =~ ^\[([0-9]+):([0-9.]+)\](.*)$ ]]; do
            mm="${BASH_REMATCH[1]}"
            ss="${BASH_REMATCH[2]}"
            text="${BASH_REMATCH[3]}"
            # 跳过元数据行
            [[ "$text" == "ti:"* || "$text" == "ar:"* || "$text" == "al:"* || "$text" == "by:"* || "$text" == "offset:"* ]] && break
            ss="${ss%%.*}"  # 去掉毫秒
            # 10# 防止 09 被解释为八进制
            t=$(( 10#$mm * 60 + 10#${ss:-0} ))
            text="${text#"${text%%[![:space:]]*}"}"  # 去前导空白
            [[ -n "$text" ]] && { TUI_LRC_TIMES+=("$t"); TUI_LRC_TEXTS+=("$text"); }
            break  # 一行只取首个时间标签的正文 (简单处理)
        done
    done <<< "$raw"
}

# 返回当前歌词行索引 (播放位置 -> 最大 time <= pos 的行), 无则 -1
tui_lyric_index() {
    local pos="${1:-${PLAYBACK_POSITION:-0}}" i idx=-1 n
    n=${#TUI_LRC_TIMES[@]}
    if (( n == 0 )); then
        printf '%d' "$idx"
        return
    fi
    # 播放位置在第一句之前时, 显示第一句而不是无歌词
    if (( pos < ${TUI_LRC_TIMES[0]} )); then
        printf '0'
        return
    fi
    for ((i = 0; i < n; i++)); do
        [[ "${TUI_LRC_TIMES[i]}" -le "$pos" ]] && idx=$i || break
    done
    printf '%d' "$idx"
}

#==============================================================================
# 渲染: 顶部红线 (go-musicfox 标志)
#==============================================================================
tui_render_topline() {
    local cols title="${UI_TITLE:-LX-Music-Shell}" tw half
    cols=$(tui_cols)
    tui_goto 1 1
    tui_clr_line
    tw=$(tui_width "$title")
    half=$(( (cols - tw - 4) / 2 ))
    [[ $half -lt 0 ]] && half=0
    printf '%s' "${T_FG_RED}"
    local i
    for ((i = 0; i < half; i++)); do printf '═'; done
    printf ' %s%s%s ' "${T_BOLD}${T_FG_RED}" "$title" "${T_RESET}${T_FG_RED}"
    for ((i = 0; i < (cols - half - tw - 4); i++)); do printf '═'; done
    printf '%s' "${T_RESET}"
}

#==============================================================================
# 渲染: 副标题 (音源 + 版本)
#==============================================================================
tui_source_name() {
    case "${CURRENT_SOURCE_NAME:-${CURRENT_SOURCE:-}}" in
        ""|netease|wy) printf '网易云音乐' ;;
        kugou|kg)      printf '酷狗音乐' ;;
        kuwo|kw)       printf '酷我音乐' ;;
        qq|tx)         printf 'QQ音乐' ;;
        migu|mg)       printf '咪咕音乐' ;;
        ximalaya)      printf '喜马拉雅' ;;
        *)             printf '%s' "${CURRENT_SOURCE_NAME:-${CURRENT_SOURCE}}" ;;
    esac
}

tui_render_subtitle() {
    local row="$1" cols left sub
    cols=$(tui_cols)
    tui_goto "$row" 1
    tui_clr_line
    sub="♪ $(tui_source_name)   v${VERSION:-3.0}"
    sub="$(tui_trunc "$sub" "$cols")"
    left=$(tui_left_pad "$sub" "$cols")
    printf '%*s%s%s%s' "$left" '' "${T_DIM}${T_FG_GRAY}" "$sub" "${T_RESET}"
}

#==============================================================================
# 渲染: 菜单
#==============================================================================
tui_render_menu() {
    local start_row="$1" end_row="$2" cols
    cols=$(tui_cols)
    local total=${#TUI_MENU_ITEMS[@]}
    local step
    step=$(tui_menu_step "$start_row" "$end_row" "$total")
    local i
    for ((i = 0; i < total; i++)); do
        local row=$((start_row + i * step))
        (( row > end_row )) && break
        tui_blank_row "$row"
        tui_goto "$row" 4
        local label="${TUI_MENU_ITEMS[i]%%|*}"
        label="$(tui_trunc "$label" $((cols - 12)))"
        if [[ "$i" == "${UI_SELECTED:-0}" ]]; then
            printf '%s=> %s%s%s' "${T_BOLD}${T_FG_RED}" "${T_BOLD}${T_FG_RED}" "$label" "${T_RESET}"
        else
            printf '   %s%s%s' "${T_FG_WHITE}" "$label" "${T_RESET}"
        fi
    done
}

#==============================================================================
# 渲染: 搜索框 (search 屏幕第 1 行主区)
#==============================================================================
tui_render_search_input() {
    local row="$1" cols
    cols=$(tui_cols)
    tui_blank_row "$row"
    tui_goto "$row" 2

    local focused=0
    [[ "${UI_FOCUS:-list}" == "search" ]] && focused=1

    printf '%s🔍 %s' "${T_FG_CYAN}${T_BOLD}" "${T_RESET}"
    local prompt
    if ((focused)); then
        prompt="${T_BG_BLUE}${T_FG_WHITE}"
        printf '%s' "${T_FG_CYAN}${T_BOLD}▸${T_RESET} "
        local q cur before after
        q="${UI_QUERY:-}"
        cur="${UI_QUERY_CURSOR:-0}"
        (( cur < 0 )) && cur=0
        (( cur > ${#q} )) && cur=${#q}
        before="$(tui_trunc "${q:0:cur}" $((cols - 26)))"
        after="$(tui_trunc "${q:cur}" $((cols - 26)))"
        printf '%s%s%s%s%s' "$prompt" "$before" "${T_BG_BLUE}${T_FG_WHITE}▏${T_RESET}" "$after" "${T_RESET}"
        printf '%s|%s' "${T_FG_CYAN}${T_BOLD}" "${T_RESET}"
    else
        if [[ -z "${UI_QUERY:-}" ]]; then
            if [[ "${UI_SEARCH_MODE:-song}" == "playlist" ]]; then
                printf '%s(输入歌单关键词后回车搜索, / 聚焦)%s' "${T_DIM}${T_FG_GRAY}" "${T_RESET}"
            else
                printf '%s(输入关键词后回车搜索, / 聚焦)%s' "${T_DIM}${T_FG_GRAY}" "${T_RESET}"
            fi
        else
            printf '%s%s%s' "${T_FG_WHITE}" "$(tui_trunc "${UI_QUERY}" $((cols - 24)))" "${T_RESET}"
        fi
    fi

    # 右侧: 源 + 音质 chip
    local right right_w
    right=" [$(tui_mode_name)] $(tui_quality_chip) "
    right_w=$(tui_width "$right")
    tui_goto "$row" $((cols - right_w + 1))
    printf '%s' "$right"
}

# 音质 chip 文本 (纯文本, 无颜色, 用于宽度计算)
tui_quality_chip() {
    local q="${DEFAULT_QUALITY:-flac}"
    case "$q" in
        hires) printf 'HiRes' ;;
        flac)  printf 'FLAC' ;;
        320)   printf 'HQ' ;;
        128)   printf 'SQ' ;;
        *)     printf '--' ;;
    esac
}

#==============================================================================
# 渲染: 结果/播放列表
#
# 使用 PLAYLIST[] (9 列轨道)。高亮选中行, ▶ 标记当前播放, 显示音质 chip。
#==============================================================================
tui_render_list() {
    local start_row="$1" end_row="$2" cols
    cols=$(tui_cols)
    local n
    n=$(tui_list_n)
    local visible=$((end_row - start_row + 1))

    # 自动滚动保持选中可见
    local sel="${UI_SELECTED:-0}"
    if ((sel < UI_SCROLL_TOP)); then UI_SCROLL_TOP=$sel; fi
    if ((sel >= UI_SCROLL_TOP + visible)); then UI_SCROLL_TOP=$((sel - visible + 1)); fi

    if ((n == 0)); then
        local bi
        for ((bi = 0; bi < visible; bi++)); do tui_blank_row $((start_row + bi)); done
        tui_goto "$start_row" 4
        printf '%s(无结果, 输入关键词搜索)%s' "${T_DIM}${T_FG_GRAY}" "${T_RESET}"
        return
    fi

    local i
    for ((i = 0; i < visible; i++)); do
        local idx=$((UI_SCROLL_TOP + i))
        (( idx >= n )) && break
        local row=$((start_row + i))
        tui_blank_row "$row"

        local track="${PLAYLIST[idx]}"
        local name="" artist="" duration="" quality="" qlabel=""
        IFS='|' read -r name artist _alb duration _sid quality _cover _quals _url <<< "$track"
        [[ -z "$name" ]] && name="未知"

        # 选中/播放标记
        tui_goto "$row" 2
        local marker="  "
        if [[ "$idx" == "${PLAYLIST_INDEX:-}" ]]; then
            marker="${T_FG_GREEN}▶${T_RESET} "
        fi

        # 高亮选中行
        local fg="${T_FG_WHITE}"
        local fg2="${T_DIM}${T_FG_GRAY}"
        if [[ "$idx" == "$sel" ]]; then
            fg="${T_INVERT}${T_BOLD}${T_FG_WHITE}"
            fg2="${T_INVERT}${T_DIM}"
        fi

        # 序号 + 歌名 + 歌手 (截断)
        local idx_str
        printf -v idx_str '%2d' "$idx"
        local name_w=$((cols - 40))
        [[ $name_w -lt 10 ]] && name_w=10

        printf '%s%s%s %s%s%s ' \
            "$marker" "$fg" "$idx_str" "$fg" "$(tui_trunc "$name" "$((name_w / 2))")" "${T_RESET}"
        printf '%s%s%s' "$fg2" "$(tui_trunc "$artist" "$((name_w / 2 - 2))")" "${T_RESET}"

        # 时长 (右对齐固定列)
        tui_goto "$row" $((cols - 22))
        printf '%s%s%s' "${T_FG_GRAY}" "${duration:--:--}" "${T_RESET}"

        # 音质 chip
        case "$quality" in
            hires) qlabel="${T_FG_PINK}HiRes" ;;
            flac)  qlabel="${T_FG_CYAN}FLAC" ;;
            320)   qlabel="${T_FG_GREEN}HQ" ;;
            128)   qlabel="${T_FG_GRAY}SQ" ;;
            *)     qlabel="${T_FG_GRAY}--" ;;
        esac
        tui_goto "$row" $((cols - 12))
        printf '%s[%s]%s' "${T_DIM}" "$qlabel" "${T_RESET}"
    done

    # 清空列表缩小后残留的旧行
    local ri
    for ((ri = i; ri < visible; ri++)); do
        tui_blank_row $((start_row + ri))
    done
}

#==============================================================================
# 渲染: 歌词区 (5 行居中, 当前行高亮)
#==============================================================================
tui_render_lyrics() {
    local start_row="$1" max_lines="${2:-5}" cols
    cols=$(tui_cols)

    tui_lyric_parse
    local idx
    idx=$(tui_lyric_index "${PLAYBACK_POSITION:-0}")

    local center=$((max_lines / 2))
    local i
    for ((i = 0; i < max_lines; i++)); do
        local row=$((start_row + i))
        tui_blank_row "$row"
        local li=$((idx - center + i))
        local text=""
        if ((li >= 0 && li < ${#TUI_LRC_TEXTS[@]})); then
            text="${TUI_LRC_TEXTS[li]}"
        fi
        # 无歌词时显示提示
        if ((idx < 0)) && ((i == center)); then
            if [[ "${PLAYER_STATUS:-stopped}" == "stopped" ]]; then
                text="♪ 播放后显示歌词 ♪"
            else
                text="(暂无歌词)"
            fi
        fi
        text="$(tui_trunc "$text" "$cols")"
        local left
        left=$(tui_left_pad "$text" "$cols")
        if ((i == center)); then
            printf '%*s%s%s%s' "$left" '' "${T_BOLD}${T_FG_LIGHT_CYAN}" "$text" "${T_RESET}"
        else
            printf '%*s%s%s%s' "$left" '' "${T_DIM}${T_FG_GRAY}" "$text" "${T_RESET}"
        fi
    done
}

#==============================================================================
# 渲染: 频谱 (纯 bash 动画, 播放状态驱动, 无音频采集依赖)
#
# 用一个确定性伪随机 + 正弦包络 + 低频强调生成 32 根柱, 随播放位置跳动。
#==============================================================================
tui_render_spectrum() {
    local start_row="$1" height="${2:-3}" cols
    cols=$(tui_cols)
    local bands=32
    local bw=$((cols / bands))
    [[ $bw -lt 1 ]] && bw=1

    # 时间片: 播放位置 * 4 (约 4Hz 更新粒度) ; 未播放时用秒级时钟
    local t
    if [[ "${PLAYER_STATUS:-stopped}" == "playing" ]]; then
        t=$(( (PLAYBACK_POSITION % 1000) * 4 ))
    else
        t=$(( $(date +%s) % 1000 ))
    fi

    local row b
    for ((row = 0; row < height; row++)); do
        tui_blank_row $((start_row + row))
        tui_goto $((start_row + row)) 1
        for ((b = 0; b < bands; b++)); do
            # 确定性强度的 "音乐感" 函数
            local v
            v=$(( (b * 37 + t * 13 + b * b * 5) % 97 ))
            # 低频强调: 越靠左 (低频) 越活跃
            local amp=$(( (bands - b) * 128 / bands + 32 ))
            v=$(( v * amp / 128 ))
            # 叠加慢正弦包络
            local env
            env=$(( (b + t / 7) % 31 ))
            env=$(( env > 15 ? 31 - env : env ))
            v=$(( v * (env + 20) / 35 ))
            (( v > 100 )) && v=100
            (( v < 4 )) && v=0

            # 映射到本行: 高度 height, 每行约 (100/height) 强度
            local row_lo=$(( row * 100 / height ))
            local row_hi=$(( (row + 1) * 100 / height ))
            local ch=' '
            if (( v >= row_hi )); then ch='█'
            elif (( v >= (row_lo + row_hi) / 2 )); then ch='▄'
            fi

            local color="${T_FG_GRAY}${T_DIM}"
            if (( v >= 75 )); then color="${T_FG_RED}${T_BOLD}"
            elif (( v >= 55 )); then color="${T_FG_ORANGE}"
            elif (( v >= 35 )); then color="${T_FG_YELLOW}"
            elif (( v >= 15 )); then color="${T_FG_GREEN}"
            fi

            printf '%s%s%s' "$color" "$ch" "${T_RESET}"
        done
    done
}

#==============================================================================
# 渲染: 帮助提示行
#==============================================================================
tui_render_hint() {
    local row="$1" cols left
    cols=$(tui_cols)
    tui_blank_row "$row"
    local hint
    case "${UI_SCREEN:-menu}" in
        search)
            if [[ "${UI_FOCUS:-list}" == "search" ]]; then
                if [[ "${UI_SEARCH_MODE:-song}" == "playlist" ]]; then
                    hint="输入歌单关键词, [Enter]搜索  [Esc]返回菜单"
                else
                    hint="输入关键词, [Enter]搜索  [Esc]返回菜单"
                fi
            else
                hint="[/]搜索  [↑↓/jk]选择  [Enter]播放  [Space]暂停  [n]下一首  [p]上一首  [+/-]音量  [Esc]菜单  [q]退出"
            fi
            ;;
        playlist_select)
            hint="[↑↓/jk]选择歌单  [Enter]加载歌曲  [Esc]返回菜单  [q]退出"
            ;;
        playing)
            hint="[Esc]返回  [Space]暂停/继续  [n]下一首  [p]上一首  [+/-]音量  [q]退出"
            ;;
        source_select|quality_select)
            hint="[↑↓/jk]选择  [Enter]确认  [Esc]返回菜单  [q]退出"
            ;;
        *)
            hint="[↑↓/jk]选择  [Enter]确认  [/]搜索  [Space]暂停  [q]退出"
            ;;
    esac
    hint="$(tui_trunc "$hint" "$cols")"
    left=$(tui_left_pad "$hint" "$cols")
    printf '%*s%s%s%s' "$left" '' "${T_DIM}${T_FG_GRAY}" "$hint" "${T_RESET}"
}

#==============================================================================
# 渲染: 底部播放栏 (模式 + 音量 + 状态 + 歌名/歌手)
#==============================================================================
tui_render_playbar() {
    local row="$1" cols
    cols=$(tui_cols)
    tui_blank_row "$row"
    tui_goto "$row" 1

    # 模式 | 音量 | 状态图标 | 当前曲目
    printf ' %s[%s]%s ' "${T_FG_PINK}" "$(tui_mode_name)" "${T_RESET}"
    printf '%s│%s ' "${T_DIM}${T_FG_GRAY}" "${T_RESET}"
    printf '%s🔊%d%%%s ' "${T_FG_GREEN}" "${VOLUME:-80}" "${T_RESET}"
    printf '%s│%s ' "${T_DIM}${T_FG_GRAY}" "${T_RESET}"

    local icon="♫ ♪ ♫ ♪"
    [[ "${PLAYER_STATUS:-stopped}" != "playing" ]] && icon="_ z Z Z"
    printf '%s%s%s ' "${T_FG_YELLOW}" "$icon" "${T_RESET}"
    printf '%s│%s ' "${T_DIM}${T_FG_GRAY}" "${T_RESET}"

    # 当前曲目 (列表优先; 后台播放/无列表时回退到 CURRENT_TRACK)
    local name="(未播放)" artist=""
    local n
    n=$(tui_list_n)
    if [[ "${PLAYLIST_INDEX:-}" =~ ^[0-9]+$ ]] && ((PLAYLIST_INDEX < n)); then
        local track="${PLAYLIST[PLAYLIST_INDEX]}"
        IFS='|' read -r name artist _ _ _ _ _ _ _ <<< "$track"
    elif [[ -n "${CURRENT_TRACK:-}" ]]; then
        name="${CURRENT_TRACK}"
        artist=""
    fi
    local avail=$((cols - 44))
    [[ $avail -lt 8 ]] && avail=8
    printf '%s%s%s' "${T_BOLD}${T_FG_CYAN}" "$(tui_trunc "$name" "$avail")" "${T_RESET}"
    if [[ -n "$artist" ]]; then
        printf ' %s%s%s' "${T_DIM}" "$(tui_trunc "$artist" 20)" "${T_RESET}"
    fi
}

#==============================================================================
# 渲染: 进度条 (真实进度 + 时间 + 可点击 seek)
#==============================================================================
tui_render_progress() {
    local row="$1" cols
    cols=$(tui_cols)
    local cur="${PLAYBACK_POSITION:-0}" total="${PLAYBACK_DURATION:-0}"
    local pct=0
    (( total > 0 )) && pct=$((cur * 100 / total))
    (( pct > 100 )) && pct=100
    (( pct < 0 )) && pct=0

    tui_blank_row "$row"
    tui_goto "$row" 2

    # 左侧: 当前时间 (青色加粗)
    printf '%s%02d:%02d%s ' "${T_BOLD}${T_FG_CYAN}" $((cur / 60)) $((cur % 60)) "${T_RESET}"

    # 中间: 现代细进度条 (▰/▱, 渐变高亮)
    local bar_w=$((cols - 26))
    (( bar_w < 10 )) && bar_w=10
    local filled=$((pct * bar_w / 100))

    local bar_color="${T_FG_CYAN}${T_BOLD}"
    if (( pct >= 80 )); then bar_color="${T_FG_GREEN}${T_BOLD}"
    elif (( pct >= 40 )); then bar_color="${T_FG_ORANGE}"
    fi

    printf '%s' "${bar_color}"
    local j
    for ((j = 0; j < filled; j++)); do printf '▰'; done
    printf '%s' "${T_DIM}${T_FG_GRAY}"
    for ((j = filled; j < bar_w; j++)); do printf '▱'; done
    printf '%s' "${T_RESET}"

    # 右侧: 总时长 + 百分比
    printf ' %s%02d:%02d%s %s%3d%%%s' \
        "${T_FG_WHITE}" $((total / 60)) $((total % 60)) "${T_RESET}" \
        "${T_BOLD}${T_FG_CYAN}" "$pct" "${T_RESET}"
}
#==============================================================================
# 渲染: 封面 (kitty 图形协议, best-effort)
#
# 若 kitty 且本地封面文件已下载 (TUI_COVER_FILE), 用 t=f 传输; 否则 ASCII 占位。
#==============================================================================
# 封面半块渲染器路径 (参考 bilibili-tui halfblocks fallback)
if [[ -z "${LXMS_COVER_RENDER:-}" ]]; then
    _tui_self_dir="${BASH_SOURCE[0]%/*}"
    [[ -f "$_tui_self_dir/cover_render.py" ]] && LXMS_COVER_RENDER="$_tui_self_dir/cover_render.py"
fi

tui_render_cover() {
    local row="$1" col="${2:-1}" size="${3:-10}"
    if [[ -n "${TUI_COVER_FILE:-}" ]] && [[ -f "$TUI_COVER_FILE" ]]; then
        # 优先使用 ffmpeg 半块真彩渲染 (通用且稳定, bilibili-tui 同款 fallback)
        if [[ -n "${LXMS_COVER_RENDER:-}" ]] && [[ -f "${LXMS_COVER_RENDER:-}" ]] && command -v python3 >/dev/null 2>&1 && command -v ffmpeg >/dev/null 2>&1; then
            tui_goto "$row" "$col"
            python3 "$LXMS_COVER_RENDER" "$TUI_COVER_FILE" $((size * 2)) "$size" 2>/dev/null
            return 0
        fi
        # Kitty 原生图形协议 (仅在半块渲染不可用时)
        if [[ "${TERM:-}" == *kitty* || "${TERM:-}" == xterm-kitty* ]]; then
            tui_goto "$row" "$col"
            printf '\033_Ga=T,f=100,t=f,c=%d,r=%d;%s\033\\' "$size" "$size" "$TUI_COVER_FILE"
            return 0
        fi
    fi
    # ASCII 占位
    tui_goto "$row" "$col"
    printf '%s♪♫♪%s' "${T_FG_MAGENTA}${T_BOLD}" "${T_RESET}"
    return 0
}

#==============================================================================
# 开屏加载动画 (仅启动时播放一次, ASCII 帧避免终端字体乱码)
#==============================================================================
tui_splash_loading() {
    local frames=('|' '/' '-' '\\') i pad cols
    cols=$(tui_cols)
    printf '%s' "${T_HIDE_CURSOR}"
    printf '%s' "${T_CLR}"
    for ((i = 0; i < 8; i++)); do
        pad=$(( (cols - 26) / 2 ))
        [[ $pad -lt 0 ]] && pad=0
        printf '%s[2K%s[%d;1H' "${_T_ESC}" "${_T_ESC}" 1
        printf '%*s%s LX-Music-Shell 加载中...' "$pad" '' "${frames[$((i % 4))]}"
        sleep 0.06
    done
    # 清空开屏动画所在行, 避免退出 TUI 后残留在普通屏幕上
    printf '%s[2K%s[1;1H%s[2K' "${_T_ESC}" "${_T_ESC}" "${_T_ESC}"
}

#==============================================================================
# 进入备屏 + 隐藏光标 (每会话调用一次)
#==============================================================================
tui_enter() {
    printf '%s%s' "${T_ALT_ON}" "${T_CLR}"
    printf '%s' "${T_HIDE_CURSOR}"
}

#==============================================================================
# 主渲染 (每帧调用: 增量重绘, 不清全屏避免闪烁)
#
# 只用光标归位 (T_HOME), 每行绘制前用 T_CLR_LINE 清行,
# 不做 \033[2J 全屏清屏, 消除逐帧闪屏。
# 仅当终端 resize (SIGWINCH) 时做一次全屏清屏, 清除旧尺寸残留。
#==============================================================================
TUI_NEED_CLEAR=0
# shellcheck disable=SC2034  # TUI_DIRTY 由 lx-music-shell 主循环消费
TUI_DIRTY=1
TUI_LAST_SCREEN=""
TUI_LAST_LINES=0
TUI_LAST_COLS=0

tui_on_resize() {
    TUI_NEED_CLEAR=1
    # shellcheck disable=SC2034  # TUI_DIRTY 由 lx-music-shell 主循环消费
    TUI_DIRTY=1
    # 清掉缓存的终端尺寸, 下次渲染重新 tput 获取, 保证实时适应窗口大小
    COLUMNS=""
    LINES=""
}

tui_render() {
    local cols lines frame do_full_clear
    cols=$(tui_cols)
    lines=$(tui_lines)
    # 缓存尺寸, 本帧渲染内的 tui_cols/tui_lines 不再重复调用 tput
    COLUMNS="$cols"
    LINES="$lines"

    # 屏幕切换/尺寸变化/收到 resize 信号时才整屏清除
    if [[ "${UI_SCREEN:-menu}" != "${TUI_LAST_SCREEN:-}" || "$lines" != "${TUI_LAST_LINES:-0}" || "$cols" != "${TUI_LAST_COLS:-0}" ]]; then
        do_full_clear=1
    fi
    if [[ "${TUI_NEED_CLEAR:-0}" == "1" ]]; then
        do_full_clear=1
        TUI_NEED_CLEAR=0
    fi

    TUI_LAST_SCREEN="${UI_SCREEN:-menu}"
    TUI_LAST_LINES="$lines"
    TUI_LAST_COLS="$cols"
    TUI_FULL_CLEAR=$do_full_clear

    # 布局: 顶部 2 行 + 底部常驻区, 根据窗口高度自适应
    local lyric_h hint_h bottom main_start main_end
    if (( lines >= 24 )); then
        lyric_h=5; hint_h=1
    elif (( lines >= 18 )); then
        lyric_h=3; hint_h=1
    elif (( lines >= 12 )); then
        lyric_h=1; hint_h=1
    else
        lyric_h=0; hint_h=0
    fi

    bottom=$((1 + 1 + lyric_h + hint_h))  # 播放栏 + 进度 + 歌词 + 提示
    main_start=4
    (( lines < 16 )) && main_start=3
    main_end=$((lines - bottom))
    (( main_end < main_start + 1 )) && main_end=$((main_start + 1))
    (( main_end > lines - 2 )) && main_end=$((lines - 2))
    (( main_end < main_start )) && main_end=$main_start

    # 鼠标区域必须在主 shell 注册 (命令替换子 shell 会丢失数组修改)
    tui_register_regions "$main_start" "$main_end"

    # 双缓冲: 在子 shell 中生成整帧, 一次性输出, 消除逐行清屏闪烁
    frame="$(tui_render_frame "$main_start" "$main_end" "$lines")"
    printf '%s' "$frame"
    TUI_FULL_CLEAR=0
}

tui_render_frame() {
    local main_start="$1" main_end="$2" lines="$3"

    if [[ "${TUI_FULL_CLEAR:-0}" == "1" ]]; then
        printf '%s' "${T_CLR}"
    else
        printf '%s' "${T_HOME}"
    fi

    tui_render_topline
    tui_render_subtitle 2

    case "${UI_SCREEN:-menu}" in
        search)
            tui_render_search_input "$main_start"
            tui_render_list $((main_start + 1)) "$main_end"
            ;;
        help)
            tui_render_help "$main_start" "$main_end"
            ;;
        playing)
            tui_render_playing "$main_start" "$main_end"
            ;;
        playlist_select)
            tui_render_playlist_select "$main_start" "$main_end"
            ;;
        source_select|quality_select)
            tui_render_select "$main_start" "$main_end"
            ;;
        menu|*)
            tui_render_menu "$main_start" "$main_end"
            ;;
    esac

    # 底部区域 (根据外层传入的布局参数自适应)
    local lyric_h hint_h
    if (( lines >= 24 )); then
        lyric_h=5; hint_h=1
    elif (( lines >= 18 )); then
        lyric_h=3; hint_h=1
    elif (( lines >= 12 )); then
        lyric_h=1; hint_h=1
    else
        lyric_h=0; hint_h=0
    fi

    local lyric_start=$((main_end + 1))
    if (( lyric_h > 0 )); then
        tui_render_lyrics "$lyric_start" "$lyric_h"
    fi

    if (( hint_h > 0 )); then
        local hint_row=$((lyric_start + lyric_h))
        tui_render_hint "$hint_row"
    fi
    tui_render_playbar $((lines - 1))
    tui_render_progress "$lines"
}
#==============================================================================
# 帮助页
#==============================================================================
tui_render_help() {
    local start_row="$1" end_row="$2"
    local -a lines
    lines=(
        "LX-Music-Shell v${VERSION:-3.0} — 终端音乐播放器"
        ""
        "  搜索:  / 聚焦搜索框, 输入关键词, Enter 确认"
        "  播放:  Enter 播放选中, Space 暂停/继续"
        "  切歌:  n 下一首 / p 上一首"
        "  音量:  + / - 调节"
        "  模式:  m 循环播放模式"
        "  音源:  s 切换音源, c 切换音质"
        "  退出:  q / Esc / Ctrl-C"
    )
    local i
    for ((i = 0; i < ${#lines[@]}; i++)); do
        local row=$((start_row + i))
        (( row > end_row )) && break
        tui_blank_row "$row"
        tui_goto "$row" 4
        printf '%s%s%s' "${T_DIM}${T_FG_WHITE}" "${lines[i]}" "${T_RESET}"
    done
    local ri
    for ((ri = i; ri <= end_row - start_row; ri++)); do
        tui_blank_row $((start_row + ri))
    done
}

#==============================================================================
# 渲染: 通用选择子菜单 (音源/音质)
#==============================================================================
tui_render_select() {
    local start_row="$1" end_row="$2" cols
    cols=$(tui_cols)
    tui_goto "$start_row" 2
    printf '%s%s%s' "${T_BOLD}${T_FG_CYAN}" "${TUI_SELECT_TITLE}" "${T_RESET}"

    local n=${#TUI_SELECT_ITEMS[@]}
    local visible=$((end_row - start_row))
    (( visible < 1 )) && visible=1

    local sel="${UI_SELECTED:-0}"
    if ((sel < UI_SCROLL_TOP)); then UI_SCROLL_TOP=$sel; fi
    if ((sel >= UI_SCROLL_TOP + visible)); then UI_SCROLL_TOP=$((sel - visible + 1)); fi
    if (( UI_SCROLL_TOP < 0 )); then UI_SCROLL_TOP=0; fi

    if ((n == 0)); then
        local bi
        for ((bi = 0; bi < visible; bi++)); do tui_blank_row $((start_row + bi)); done
        tui_goto $((start_row + 1)) 4
        printf '%s(无可用选项)%s' "${T_DIM}${T_FG_GRAY}" "${T_RESET}"
        return
    fi

    local i idx row label
    for ((i = 0; i < visible; i++)); do
        idx=$((UI_SCROLL_TOP + i))
        (( idx >= n )) && break
        row=$((start_row + 1 + i))
        tui_blank_row "$row"
        tui_goto "$row" 4
        label="${TUI_SELECT_ITEMS[idx]}"
        label="$(tui_trunc "$label" $((cols - 10)))"
        if [[ "$idx" == "$sel" ]]; then
            printf '%s=> %s%s%s' "${T_BOLD}${T_FG_RED}" "${T_BOLD}${T_FG_RED}" "$label" "${T_RESET}"
        else
            printf '   %s%s%s' "${T_FG_WHITE}" "$label" "${T_RESET}"
        fi
    done
    local ri
    for ((ri = i; ri < visible; ri++)); do
        tui_blank_row $((start_row + ri))
    done
}

#==============================================================================
# 渲染: 正在播放页 (封面 + 歌曲信息)
#==============================================================================
tui_render_playing() {
    local start_row="$1" end_row="$2" cols
    cols=$(tui_cols)
    tui_blank_area "$start_row" "$end_row"

    local name="未知" artist="" album="" quality="--" source="" track
    local n
    n=$(tui_list_n)
    if [[ "${PLAYLIST_INDEX:-}" =~ ^[0-9]+$ ]] && ((PLAYLIST_INDEX < n)); then
        track="${PLAYLIST[PLAYLIST_INDEX]}"
        IFS='|' read -r name artist album _ _ quality _ _ _ _ <<< "$track"
    elif [[ -n "${CURRENT_TRACK:-}" ]]; then
        name="${CURRENT_TRACK%% - *}"
        artist="${CURRENT_TRACK#* - }"
        [[ "$artist" == "$CURRENT_TRACK" ]] && artist=""
    fi
    [[ -z "$name" ]] && name="未知"
    [[ -z "$artist" ]] && artist="未知歌手"
    source="$(tui_source_name)"
    [[ -z "$source" ]] && source="自动匹配"
    local qlabel="--"
    case "$quality" in
        hires) qlabel="HiRes" ;;
        flac)  qlabel="FLAC" ;;
        320)   qlabel="HQ" ;;
        128)   qlabel="SQ" ;;
    esac

    # 封面: 优先真实封面 (kitty/半块真彩), 无封面时绘制 ASCII 封面盒
    local cover_size=8
    if [[ -n "${TUI_COVER_FILE:-}" ]] && [[ -f "$TUI_COVER_FILE" ]]; then
        tui_render_cover "$start_row" 2 "$cover_size"
    else
        local cw=22 ch=7 left=2 top="$start_row" r
        tui_goto "$top" "$left"
        printf '┌%s┐' "$(printf '─%.0s' $(seq 1 $((cw - 2))))"
        for ((r = 1; r < ch - 1; r++)); do
            tui_goto $((top + r)) "$left"
            printf '│%*s│' $((cw - 2)) ''
        done
        tui_goto $((top + ch - 1)) "$left"
        printf '└%s┘' "$(printf '─%.0s' $(seq 1 $((cw - 2))))"
        local title_line="${name}"
        local tw
        tw=$(tui_width "$title_line")
        (( tw > cw - 4 )) && title_line="$(tui_trunc "$title_line" $((cw - 4)))"
        local pad=$(( (cw - 2 - tw) / 2 ))
        tui_goto $((top + 3)) $((left + 1))
        printf '%*s%s%*s' "$pad" '' "$title_line" $((cw - 2 - tw - pad)) ''
    fi

    # 歌曲信息 (居中, 在封面下方)
    local info_row=$((start_row + cover_size + 1))
    local line
    line="${name} - ${artist}"
    line="$(tui_trunc "$line" "$cols")"
    local pad
    pad=$(tui_left_pad "$line" "$cols")
    tui_goto "$info_row" 1
    printf '%*s%s%s%s' "$pad" '' "${T_BOLD}${T_FG_WHITE}" "$line" "${T_RESET}"

    line="专辑: ${album:-无}    来源: ${source}    音质: ${qlabel}"
    line="$(tui_trunc "$line" "$cols")"
    pad=$(tui_left_pad "$line" "$cols")
    tui_goto $((info_row + 1)) 1
    printf '%*s%s%s%s' "$pad" '' "${T_DIM}${T_FG_GRAY}" "$line" "${T_RESET}"

    line="作曲: -    模式: $(tui_mode_name)    音量: ${VOLUME:-80}%"
    line="$(tui_trunc "$line" "$cols")"
    pad=$(tui_left_pad "$line" "$cols")
    tui_goto $((info_row + 2)) 1
    printf '%*s%s%s%s' "$pad" '' "${T_DIM}${T_FG_GRAY}" "$line" "${T_RESET}"
}

#==============================================================================
# 渲染: 歌单搜索结果 (左侧列表 + 右侧预览)
#==============================================================================
tui_render_playlist_select() {
    local start_row="$1" end_row="$2" cols
    cols=$(tui_cols)
    tui_blank_area "$start_row" "$end_row"

    local n=${#PLAYLIST_SEARCH_RESULTS[@]}
    local visible=$((end_row - start_row + 1))
    (( visible < 1 )) && visible=1
    local sel="${UI_SELECTED:-0}"
    if ((sel < UI_SCROLL_TOP)); then UI_SCROLL_TOP=$sel; fi
    if ((sel >= UI_SCROLL_TOP + visible)); then UI_SCROLL_TOP=$((sel - visible + 1)); fi
    (( UI_SCROLL_TOP < 0 )) && UI_SCROLL_TOP=0

    local list_w=$((cols * 58 / 100))
    (( list_w < 20 )) && list_w=20
    (( list_w > cols - 30 )) && list_w=$((cols - 30))

    if ((n == 0)); then
        tui_goto "$start_row" 4
        printf '%s(无歌单结果)%s' "${T_DIM}${T_FG_GRAY}" "${T_RESET}"
        return
    fi

    local i idx row label
    for ((i = 0; i < visible; i++)); do
        idx=$((UI_SCROLL_TOP + i))
        (( idx >= n )) && break
        row=$((start_row + i))
        tui_blank_row "$row"
        local pline="${PLAYLIST_SEARCH_RESULTS[idx]}"
        local pname pcount
        IFS='|' read -r pname _ pcount _ _ <<< "$pline"
        label="$(printf '%2d' "$idx")  ${pname}  (${pcount}首)"
        label="$(tui_trunc "$label" $((list_w - 6)))"
        tui_goto "$row" 2
        if [[ "$idx" == "$sel" ]]; then
            printf '%s=> %s%s%s' "${T_BOLD}${T_FG_RED}" "${T_BOLD}${T_FG_RED}" "$label" "${T_RESET}"
        else
            printf '   %s%s%s' "${T_FG_WHITE}" "$label" "${T_RESET}"
        fi
    done
    local ri
    for ((ri = i; ri < visible; ri++)); do
        tui_blank_row $((start_row + ri))
    done

    # 右侧预览
    local pcol=$((list_w + 4))
    local pw=$((cols - pcol - 2))
    (( pw < 14 )) && pw=14
    local sline="${PLAYLIST_SEARCH_RESULTS[sel]}"
    local sname scount splay scover
    IFS='|' read -r sname _ scount splay scover <<< "$sline"
    local box_h=7
    local top="$start_row"
    tui_goto "$top" "$pcol"
    printf '┌%s┐' "$(printf '─%.0s' $(seq 1 $((pw - 2))))"
    local b
    for ((b = 1; b < box_h - 1; b++)); do
        tui_goto $((top + b)) "$pcol"
        printf '│%*s│' $((pw - 2)) ''
    done
    tui_goto $((top + box_h - 1)) "$pcol"
    printf '└%s┘' "$(printf '─%.0s' $(seq 1 $((pw - 2))))"

    local cover_text="♫ 歌单封面"
    local tw
    tw=$(tui_width "$cover_text")
    (( tw > pw - 4 )) && cover_text="$(tui_trunc "$cover_text" $((pw - 4)))"
    local pad=$(( (pw - 2 - tw) / 2 ))
    tui_goto $((top + 3)) $((pcol + 1))
    printf '%*s%s%*s' "$pad" '' "$cover_text" $((pw - 2 - tw - pad)) ''

    local info_row=$((top + box_h))
    local iline
    iline="名称: ${sname}"
    iline="$(tui_trunc "$iline" "$pw")"
    tui_goto "$info_row" "$pcol"
    printf '%s%s%s' "${T_BOLD}${T_FG_WHITE}" "$iline" "${T_RESET}"

    iline="歌曲: ${scount}首"
    tui_goto $((info_row + 1)) "$pcol"
    printf '%s%s%s' "${T_DIM}${T_FG_GRAY}" "$iline" "${T_RESET}"

    iline="播放: ${splay}"
    tui_goto $((info_row + 2)) "$pcol"
    printf '%s%s%s' "${T_DIM}${T_FG_GRAY}" "$iline" "${T_RESET}"

    iline="封面: ${scover:0:32}..."
    iline="$(tui_trunc "$iline" "$pw")"
    tui_goto $((info_row + 3)) "$pcol"
    printf '%s%s%s' "${T_DIM}${T_FG_GRAY}" "$iline" "${T_RESET}"
}

#==============================================================================
# 鼠标区域注册 (供 input_mouse_to_action 命中测试)
#
# 区域命名:
#   menu_i   - 菜单第 i 项
#   list_i   - 结果列表第 i 行 (相对于列表首行)
#   search   - 搜索框
#   progress - 进度条
#   playbar  - 播放栏
#==============================================================================
tui_register_regions() {
    local main_start="$1" main_end="$2" cols lines
    cols=$(tui_cols); lines=$(tui_lines)

    input_clear_regions

    case "${UI_SCREEN:-menu}" in
        search)
            # 搜索框
            input_register_region "search" "$main_start" 1 1 "$cols"
            # 列表项
            local visible=$((main_end - main_start))
            local i
            for ((i = 0; i < visible; i++)); do
                input_register_region "list_$i" $((main_start + 1 + i)) 1 1 "$cols"
            done
            ;;
        source_select|quality_select|playlist_select)
            local visible=$((main_end - main_start))
            local i
            for ((i = 0; i < visible; i++)); do
                input_register_region "select_$i" $((main_start + 1 + i)) 1 1 "$cols"
            done
            ;;
        menu|*)
            local total=${#TUI_MENU_ITEMS[@]}
            local i step
            step=$(tui_menu_step "$main_start" "$main_end" "$total")
            for ((i = 0; i < total; i++)); do
                local row=$((main_start + i * step))
                (( row > main_end )) && break
                input_register_region "menu_$i" "$row" 1 1 "$cols"
            done
            ;;
    esac

    # 播放栏 + 进度条
    input_register_region "playbar" $((lines - 1)) 1 1 "$cols"
    input_register_region "progress" "$lines" 1 1 "$cols"
}

#==============================================================================
# 鼠标 → 动作 (返回动作码文本; 主循环据此执行)
#
# 输出: "menu:<idx>" | "list:<idx>" | "search" | "playbar" | "progress:<pct>"
# 未命中返回 1
#==============================================================================
tui_mouse_action() {
    local x="$1" y="$2" region
    if ! input_mouse_to_action "$x" "$y"; then
        return 1
    fi
    region="${INPUT_HIT_REGION:-}"

    case "$region" in
        search)
            printf 'search'
            ;;
        list_*)
            local li="${region#list_}"
            printf 'list:%d' "$((UI_SCROLL_TOP + li))"
            ;;
        menu_*)
            local mi="${region#menu_}"
            printf 'menu:%d' "$mi"
            ;;
        select_*)
            local si="${region#select_}"
            printf 'select:%d' "$((UI_SCROLL_TOP + si))"
            ;;
        playbar)
            # 播放栏左半=暂停, 右半=下一首 (简化: 按列划分)
            if ((x <= 12)); then printf 'toggle'; else printf 'next'; fi
            ;;
        progress)
            local cols
            cols=$(tui_cols)
            local pct=$((x * 100 / cols))
            printf 'seek:%d' "$pct"
            ;;
        *)
            return 1
            ;;
    esac
}

#==============================================================================
# 操作函数 (主事件循环调用)
#==============================================================================
tui_op_move_up() {
    local n
    n=$(tui_item_count)
    (( n > 0 )) && { UI_SELECTED=$((UI_SELECTED - 1)); (( UI_SELECTED < 0 )) && UI_SELECTED=0; }
}

tui_op_move_down() {
    local n
    n=$(tui_item_count)
    (( n > 0 )) && { UI_SELECTED=$((UI_SELECTED + 1)); (( UI_SELECTED >= n )) && UI_SELECTED=$((n - 1)); }
}

tui_op_move_top() {
    UI_SELECTED=0
    UI_SCROLL_TOP=0
}

tui_op_move_bottom() {
    local n
    n=$(tui_item_count)
    (( n > 0 )) && UI_SELECTED=$((n - 1))
}

tui_op_next_page() {
    local n
    n=$(tui_item_count)
    (( n > 0 )) && { UI_SELECTED=$((UI_SELECTED + 10)); (( UI_SELECTED >= n )) && UI_SELECTED=$((n - 1)); }
}

tui_op_prev_page() {
    UI_SELECTED=$((UI_SELECTED - 10))
    (( UI_SELECTED < 0 )) && UI_SELECTED=0
}

tui_op_start_search() {
    UI_SCREEN="search"
    UI_FOCUS="search"
    UI_QUERY=""
    UI_QUERY_CURSOR=0
    UI_SEARCH_MODE="song"
    UI_SELECTED=0
    UI_SCROLL_TOP=0
}

tui_op_start_playlist_search() {
    UI_SCREEN="search"
    UI_FOCUS="search"
    UI_QUERY=""
    UI_QUERY_CURSOR=0
    UI_SEARCH_MODE="playlist"
    UI_SELECTED=0
    UI_SCROLL_TOP=0
}

# 在搜索框光标处插入字符
tui_op_search_append() {
    local ch="$1" cur
    UI_FOCUS="search"
    cur="${UI_QUERY_CURSOR:-0}"
    UI_QUERY="${UI_QUERY:0:cur}${ch}${UI_QUERY:cur}"
    UI_QUERY_CURSOR=$((cur + ${#ch}))
}

# 删除光标前一个字符
tui_op_search_backspace() {
    local cur
    UI_FOCUS="search"
    cur="${UI_QUERY_CURSOR:-0}"
    if (( cur > 0 )); then
        UI_QUERY="${UI_QUERY:0:cur-1}${UI_QUERY:cur}"
        UI_QUERY_CURSOR=$((cur - 1))
    fi
}

# 删除光标后一个字符 (Delete)
tui_op_search_delete() {
    local cur len
    UI_FOCUS="search"
    cur="${UI_QUERY_CURSOR:-0}"
    len=${#UI_QUERY}
    if (( cur < len )); then
        UI_QUERY="${UI_QUERY:0:cur}${UI_QUERY:cur+1}"
    fi
}

tui_op_search_left() {
    local cur
    UI_FOCUS="search"
    cur="${UI_QUERY_CURSOR:-0}"
    (( cur > 0 )) && UI_QUERY_CURSOR=$((cur - 1))
}

tui_op_search_right() {
    local cur len
    UI_FOCUS="search"
    cur="${UI_QUERY_CURSOR:-0}"
    len=${#UI_QUERY}
    (( cur < len )) && UI_QUERY_CURSOR=$((cur + 1))
}

tui_op_search_home() {
    UI_FOCUS="search"
    UI_QUERY_CURSOR=0
}

tui_op_search_end() {
    UI_FOCUS="search"
    UI_QUERY_CURSOR=${#UI_QUERY}
}

# 退出搜索/选择子菜单 (回到菜单)
tui_op_search_cancel() {
    if [[ "${UI_SCREEN:-menu}" != "menu" ]]; then
        UI_SCREEN="menu"
        UI_FOCUS="list"
        UI_QUERY=""
        UI_QUERY_CURSOR=0
        UI_SEARCH_MODE="song"
        UI_SELECTED=0
        UI_SCROLL_TOP=0
    fi
}

# 菜单选中项的 action key
tui_menu_selected_action() {
    local sel="${UI_SELECTED:-0}"
    local item="${TUI_MENU_ITEMS[$sel]:-}"
    printf '%s' "${item#*|}"
}

tui_cleanup() {
    printf '%s%s%s' "${T_ALT_OFF}" "${T_SHOW_CURSOR}" "${T_RESET}"
}
