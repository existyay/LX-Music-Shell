#!/usr/bin/env bash
#==============================================================================
# LX-Music-Shell TUI - "Fox" 风格 (go-musicfox 视觉重制)
#
# 设计目标: 完整复现 go-musicfox 的视觉/交互体验 (bubbletea + lipgloss)
# 实现策略: bash 主体 (主循环/键盘/ANSI) + python3 辅助 (歌词解析/YRC渲染/频谱)
#
# 视觉特征 (来自 go-musicfox):
#   - 顶部水平红线 (┅ musicfox ┅)
#   - 双列菜单 (cols >= 88), 单列 (cols < 88)
#   - 选中行 "=> N. 标题" 红色高亮 + 未选中 "N. 标题" 灰色
#   - 底部播放栏 "[模式] 100% ♫ ♪ ♫ ♪ ♥ 歌名 歌手"
#   - 进度条 "################################ 00:16/05:30" 红色
#   - 5 行歌词居中, 当前行青色高亮
#
# 状态机: MAIN_MENU (主菜单) -> SUBMENU (子菜单) -> DETAIL (详情) -> PLAYING
#==============================================================================

[[ -n "${LXMS_FOX_LOADED:-}" ]] && return 0
readonly LXMS_FOX_LOADED=1

#==============================================================================
# ANSI 常量
#==============================================================================
_FX_ESC=$'\033'
readonly FX_RESET="${_FX_ESC}[0m"
readonly FX_BOLD="${_FX_ESC}[1m"
readonly FX_DIM="${_FX_ESC}[2m"
readonly FX_ITALIC="${_FX_ESC}[3m"
readonly FX_UNDERLINE="${_FX_ESC}[4m"
readonly FX_REVERSE="${_FX_ESC}[7m"

# 颜色 (go-musicfox 调色板)
readonly FX_FG_RED="${_FX_ESC}[31m"
readonly FX_FG_GREEN="${_FX_ESC}[32m"
readonly FX_FG_YELLOW="${_FX_ESC}[33m"
readonly FX_FG_BLUE="${_FX_ESC}[34m"
readonly FX_FG_MAGENTA="${_FX_ESC}[35m"
readonly FX_FG_CYAN="${_FX_ESC}[36m"
readonly FX_FG_WHITE="${_FX_ESC}[37m"
readonly FX_FG_GRAY="${_FX_ESC}[90m"
readonly FX_FG_PINK="${_FX_ESC}[38;5;205m"
readonly FX_FG_ORANGE="${_FX_ESC}[38;5;214m"
readonly FX_FG_LIGHT_CYAN="${_FX_ESC}[38;5;51m"

# 背景
readonly FX_BG_RED="${_FX_ESC}[41m"
readonly FX_BG_GREEN="${_FX_ESC}[42m"

# 光标与屏幕
readonly FX_HIDE_CURSOR="${_FX_ESC}[?25l"
readonly FX_SHOW_CURSOR="${_FX_ESC}[?25h"
readonly FX_ALT_ON="${_FX_ESC}[?1049h"
readonly FX_ALT_OFF="${_FX_ESC}[?1049l"
readonly FX_CLR="${_FX_ESC}[2J${_FX_ESC}[H"
readonly FX_CLR_LINE="${_FX_ESC}[2K"

# 边框
readonly FX_H_LINE='─'
readonly FX_H_DOUBLE='═'

#==============================================================================
# 主题 (参考 go-musicfox 的 "default" 调色板)
#==============================================================================
fx_theme_set() {
    # 主题颜色 (前景色, 可被 LXMS_FX_COLORS 覆盖)
    if [[ -z "${LXMS_FX_COLORS:-}" ]]; then
        export LXMS_FX_COLORS='red|cyan|white|gray|green|yellow|magenta|pink|orange'
    fi
}

fx_theme_set

#==============================================================================
# 工具: 光标定位, 显示宽度计算 (复用 tui.sh 的)
#==============================================================================
fx_goto() {
    printf '%s[%d;%dH' "${_FX_ESC}" "$1" "$2"
}

fx_clear() {
    printf '%s%s' "${FX_ALT_ON}" "${FX_CLR}"
}

fx_clear_line() {
    printf '%s' "${FX_CLR_LINE}"
}

# 终端列宽 (fallback 80)
fx_cols() {
    if [[ -n "${COLUMNS:-}" ]]; then echo "$COLUMNS"; return; fi
    tput cols 2>/dev/null || echo 80
}

# 终端行数
fx_lines() {
    if [[ -n "${LINES:-}" ]]; then echo "$LINES"; return; fi
    tput lines 2>/dev/null || echo 24
}

# 显示宽度 (中文字符 2 列)
fx_width() {
    local text="$1"
    local width=0 i cp
    for ((i = 0; i < ${#text}; i++)); do
        printf -v cp '%d' "'${text:i:1}" 2>/dev/null || cp=0
        if ((cp < 128)); then
            ((width += 1))
        elif ((cp >= 0x2E80 && cp <= 0x9FFF)) || \
             ((cp >= 0xFF00 && cp <= 0xFF60)) || \
             ((cp >= 0x1F300)); then
            ((width += 2))
        else
            ((width += 1))
        fi
    done
    echo "$width"
}

# 右侧填充空格到显示宽度 N
fx_pad() {
    local text="$1" target="$2"
    local w
    w=$(fx_width "$text")
    printf '%s' "$text"
    if ((w < target)); then
        printf '%*s' $((target - w)) ''
    fi
}

# 截断到显示宽度 N (加 …)
fx_trunc() {
    local text="$1" target="$2"
    local w
    w=$(fx_width "$text")
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

# 居中打印一行
fx_center() {
    local text="$1" total_cols="${2:-$(fx_cols)}"
    local w
    w=$(fx_width "$text")
    local left=$(( (total_cols - w) / 2 ))
    [[ $left -lt 0 ]] && left=0
    printf '%*s' "$left" ''
    printf '%s' "$text"
}

#==============================================================================
# 全局状态 (从主循环设置, 由各渲染函数读取)
#==============================================================================

# 当前面板/页面: main_menu, sub_menu, search, detail, playing
FX_PAGE="${FX_PAGE:-main_menu}"

# Main 菜单主标题 (顶部分隔线之间显示)
FX_TITLE="${FX_TITLE:-musicfox}"

# 当前用户名 (副标题用)
FX_USER_NICKNAME="${FX_USER_NICKNAME:-未登录}"

# 菜单项列表: FX_MENU_TITLE[i]="标题", FX_MENU_KEY[i]="key" (子菜单标识)
# 初始化为 go-musicfox 的 16 项主菜单
fx_init_main_menu() {
    FX_MENU_KEY=()
    FX_MENU_TITLE=()

    if [[ ${#FX_MENU_KEY[@]} -gt 0 ]]; then return; fi

    FX_MENU_KEY=(
        "search"          "song_list"      "album_list"     "ranks"
        "high_quality"    "hot_artists"    "recent_songs"   "cloud"
        "dj_radio"        "personal_fm"    "user_playlist"  "user_collection"
        "daily_song"      "daily_playlist" "help"           "check_update"
    )
    FX_MENU_TITLE=(
        "搜索"            "我的歌单"        "专辑列表"        "排行榜"
        "精选歌单"        "热门歌手"        "最近播放"        "云盘"
        "主播电台"        "私人FM"         "登录账号"        "我的收藏"
        "每日推荐歌曲"    "每日推荐歌单"    "帮助"            "检查更新"
    )
    FX_MENU_SEL=0
}

#==============================================================================
# 渲染: 顶部水平红线 (go-musicfox 标志)
#==============================================================================
fx_render_topline() {
    local cols
    cols=$(fx_cols)
    fx_goto 1 1
    fx_clear_line
    # 左半红线 ─── + 居中 "musicfox" + 右半红线 ───
    local title="$FX_TITLE"
    local title_w
    title_w=$(fx_width "$title")
    local half=$(( (cols - title_w - 4) / 2 ))
    [[ $half -lt 0 ]] && half=0
    printf '%s%s%s ' "${FX_FG_RED}" "$(printf "${FX_H_DOUBLE}%.0s" $(seq 1 $half) 2>/dev/null)" "${FX_RESET}"
    printf '%s%s%s' "${FX_BOLD}${FX_FG_RED}" "$title" "${FX_RESET}"
    printf '%s %s' "${FX_FG_RED}" "$(printf "${FX_H_DOUBLE}%.0s" $(seq 1 $((cols - half - title_w - 4))) 2>/dev/null)"
    printf '%s\n' "${FX_RESET}"
}

#==============================================================================
# 渲染: 副标题 (用户名 / 未登录)
#==============================================================================
fx_render_subtitle() {
    local row="$1" cols
    cols=$(fx_cols)
    fx_goto "$row" 1
    fx_clear_line
    local sub="[$FX_USER_NICKNAME]"
    local sub_w
    sub_w=$(fx_width "$sub")
    local left=$(( (cols - sub_w) / 2 ))
    [[ $left -lt 0 ]] && left=0
    printf '%*s' "$left" ''
    printf '%s%s%s\n' "${FX_FG_GRAY}" "$sub" "${FX_RESET}"
}

#==============================================================================
# 渲染: 菜单列表 (双列/单列自适应)
#
# Args:
#   $1=row_start, $2=total_rows
#   使用全局 FX_MENU_KEY[], FX_MENU_TITLE[], FX_MENU_SEL
#==============================================================================
fx_render_menu() {
    local row_start="$1"
    local cols
    cols=$(fx_cols)
    local total=${#FX_MENU_TITLE[@]}

    # 双列阈值 (go-musicfox 用 88)
    local dual=0
    [[ $cols -ge 88 ]] && dual=1

    # 列布局
    local left_pad=4
    local col1_w
    if ((dual)); then
        col1_w=$(( (cols / 2) - 8 ))
        [[ $col1_w -gt 44 ]] && col1_w=44
    else
        col1_w=$(( cols - 8 ))
    fi

    local i
    for ((i = 0; i < total; i++)); do
        local row=$((row_start + i))
        fx_goto "$row" 1
        fx_clear_line

        # 双列: 偶数索引左列, 奇数索引右列
        local col_x=1
        local col_y=$row_start
        if ((dual)); then
            col_y=$((row_start + (i / 2) * 1))
            if ((i % 2 == 1)); then
                col_x=$(( cols / 2 + 2 ))
            fi
        fi
        # 实际行号: 单列 = row, 双列 = row_start + (i/2)
        if ((dual)); then
            row=$((row_start + (i / 2) ))
        fi

        fx_goto "$row" "$col_x"
        fx_clear_line

        # 单列: 左填充, 双列: 左/右填充
        printf '%*s' "$left_pad" ''

        # 选中项 "=> N. 标题" 红色, 未选中 "N. 标题" 灰色
        local marker="  "
        local fg="${FX_FG_WHITE}"
        local bold=""
        if [[ "$i" == "${FX_MENU_SEL:-0}" ]]; then
            marker="${FX_FG_RED}${FX_BOLD}=>${FX_RESET}"
            fg="${FX_FG_RED}${FX_BOLD}"
            bold="${FX_BOLD}"
        fi

        printf '%s ' "$marker"
        printf '%s%2d. %s%s' "$fg" "$i" "${bold}$(fx_trunc "${FX_MENU_TITLE[i]}" $((col1_w - 10)))" "${FX_RESET}"

        # 双列: 同行右列项目 (i+1) 也已在本轮覆盖 — 实际是 next iter
    done
}

#==============================================================================
# 渲染: 底部播放栏 (模式 + 音量 + 状态 + 心 + 歌名 + 歌手)
# 参照 go-musicfox: [列表] 100% ♫ ♪ ♫ ♪ ♥ 歌名 歌手
#==============================================================================
fx_render_playbar() {
    local row="$1" cols
    cols=$(fx_cols)

    fx_goto "$row" 1
    fx_clear_line

    # 播放模式
    local mode_name="列表"
    case "${FX_MODE:-list}" in
        list)   mode_name="列表" ;;
        loop)   mode_name="列表循环" ;;
        single) mode_name="单曲循环" ;;
        random) mode_name="随机播放" ;;
    esac

    # 音量
    local vol="${FX_VOLUME:-80}"

    # 状态图标
    local state_icon
    if [[ "${FX_STATE:-playing}" == "playing" ]]; then
        state_icon="♫ ♪ ♫ ♪"
    else
        state_icon="_ z Z Z"
    fi

    # 当前曲目 (来自 PLAYLIST) (对 set -u 安全)
    local song_name=""
    local song_artist=""
    local playlist_n=0
    [[ -n "${LXMS_PLAYLIST+set}" ]] && playlist_n=${#LXMS_PLAYLIST[@]}
    if [[ "${LXMS_PLAYING_INDEX:-}" =~ ^[0-9]+$ ]] && \
       [[ ${playlist_n:-0} -gt 0 ]] && \
       [[ ${LXMS_PLAYING_INDEX} -lt ${playlist_n} ]]; then
        local track="${LXMS_PLAYLIST[LXMS_PLAYING_INDEX]}"
        local _n _a
        # 注意: 不能用 local IFS='|' read -r ... (local 会把 read/-r 当变量名)
        IFS='|' read -r _n _a _ _ _ <<< "$track"
        song_name="$_n"
        song_artist="$_a"
    fi

    # 拼装: [模式] 100% ♫ ♪ ♫ ♪ ♥ 歌名 歌手
    printf ' %s[%s]%s ' "${FX_FG_PINK}" "$mode_name" "${FX_RESET}"
    printf '%s%d%%%s ' "${FX_FG_GREEN}" "$vol" "${FX_RESET}"
    printf '%s%s%s ' "${FX_FG_YELLOW}" "$state_icon" "${FX_RESET}"
    printf '%s♥%s ' "${FX_FG_PINK}" "${FX_RESET}"
    printf '%s%s%s' "${FX_BOLD}${FX_FG_CYAN}" "$song_name" "${FX_RESET}"
    printf ' %s%s%s' "${FX_DIM}" "$song_artist" "${FX_RESET}"
}

#==============================================================================
# 渲染: 进度条 (全宽 ###### 时间)
#==============================================================================
fx_render_progress() {
    local row="$1" cols
    cols=$(fx_cols)
    local cur="${FX_PROGRESS_C:-0}" total="${FX_PROGRESS_T:-0}"
    local pct=0
    [[ $total -gt 0 ]] && pct=$((cur * 100 / total))

    fx_goto "$row" 1
    fx_clear_line

    # 进度条主体 (使用 █ 块字符)
    local bar_w=$((cols - 18))  # 留 14 列给时间
    [[ $bar_w -lt 10 ]] && bar_w=10
    local filled=$((pct * bar_w / 100))
    printf '%s' "${FX_FG_RED}"
    local j
    for ((j = 0; j < filled; j++)); do printf '█'; done
    printf '%s' "${FX_FG_GRAY}"
    for ((j = filled; j < bar_w; j++)); do printf '▱'; done
    printf '%s' "${FX_RESET}"

    # 时间 (右侧)
    fx_goto "$row" $((cols - 12))
    printf '%s%02d:%02d/%02d:%02d%s' \
        "${FX_FG_RED}" \
        $((cur/60)) $((cur%60)) \
        $((total/60)) $((total%60)) \
        "${FX_RESET}"
}

#==============================================================================
# 渲染: 歌词区 (5 行居中, 当前行高亮)
#
# 从 python3 辅助获取高亮渲染后的 5 行 (含 ANSI 颜色码)
# 缓存: FX_LYRIC_CACHE_KEY (仅在 current_ms 变动超 100ms 时重渲染)
#==============================================================================
FX_LYRIC_CACHE_MS=0
FX_LYRIC_CACHE_OUT=""  # python3 输出 (包含 ANSI 颜色)

fx_render_lyrics() {
    local start_row="$1" max_lines="${2:-5}" cols
    cols=$(fx_cols)

    local current_ms="${FX_CURRENT_MS:-0}"
    # 100ms 缓存 (跟 go-musicfox lyricCacheKey 一样)
    local cur_bucket=$(( current_ms / 100 ))
    if [[ "$cur_bucket" != "${FX_LYRIC_CACHE_MS:-0}" ]] || \
       [[ -z "$FX_LYRIC_CACHE_OUT" ]]; then
        FX_LYRIC_CACHE_MS="$cur_bucket"
        if [[ -n "${FX_LYRIC_PY:-}" ]] && command -v python3 >/dev/null 2>&1; then
            # 调用 python3 歌词模块
            local payload
            payload=$(printf '{"lrc":%s,"yrc":%s,"current_ms":%d,"center_lines":%d,"render_mode":"%s"}' \
                "$(printf '%s' "${FX_LRC_RAW:-}" | python3 -c 'import sys,json;print(json.dumps(sys.stdin.read()))' 2>/dev/null || echo '""')" \
                "$(printf '%s' "${FX_YRC_RAW:-}" | python3 -c 'import sys,json;print(json.dumps(sys.stdin.read()))' 2>/dev/null || echo '""')" \
                "$current_ms" "$max_lines" \
                "${FX_LYRIC_MODE:-smooth}")
            FX_LYRIC_CACHE_OUT=$(printf '%s' "$payload" | python3 "$FX_LYRIC_PY" 2>/dev/null || echo '')
        else
            FX_LYRIC_CACHE_OUT=""
        fi
    fi

    # 解析 python3 输出 (JSON {"lines":[...], "center_index":N})
    local center="${FX_LYRIC_CACHE_CENTER:-2}"
    local lines=()
    if [[ -n "$FX_LYRIC_CACHE_OUT" ]] && command -v python3 >/dev/null 2>&1; then
        # 用 python 提取 lines 和 center_index
        local parsed
        parsed=$(printf '%s' "$FX_LYRIC_CACHE_OUT" | python3 -c '
import sys, json, re
try:
    d = json.loads(sys.stdin.read())
    for line in d.get("lines", []):
        # 去除 ANSI 码后再输出, 边框颜色我们重控
        clean = re.sub(r"\033\[[0-9;]*m", "", line)
        print(clean)
    print("__CENTER__" + str(d.get("center_index", 2)))
except Exception as e:
    sys.exit(1)
' 2>/dev/null)
        if [[ -n "$parsed" ]]; then
            while IFS= read -r line; do
                if [[ "$line" == "__CENTER__"* ]]; then
                    center="${line#__CENTER__}"
                else
                    lines+=("$line")
                fi
            done <<< "$parsed"
        fi
    fi

    # 如果解析失败, 用原始 FX_LYRIC_LINES[]
    if [[ ${#lines[@]} -eq 0 ]]; then
        for ((i = 0; i < max_lines; i++)); do
            lines+=("${FX_LYRIC_LINES[i]:-}")
        done
    fi

    local i
    for ((i = 0; i < max_lines; i++)); do
        local row=$((start_row + i))
        fx_goto "$row" 1
        fx_clear_line

        local line="${lines[i]:-}"
        # 当前行高亮, 其他灰色
        local fg="${FX_FG_GRAY}"
        if [[ $i -eq $center ]]; then
            fg="${FX_BOLD}${FX_FG_CYAN}"
        fi

        # 居中
        local w
        w=$(fx_width "$line")
        local left=$(( (cols - w) / 2 ))
        [[ $left -lt 0 ]] && left=0
        printf '%*s' "$left" ''
        printf '%s%s%s' "$fg" "$line" "${FX_RESET}"
    done
}

#==============================================================================
# 完整渲染
#==============================================================================
fx_render() {
    local cols lines
    cols=$(fx_cols)
    lines=$(fx_lines)

    fx_clear
    fx_goto 1 1
    printf '%s' "${FX_HIDE_CURSOR}"

    # 顶部红线 (行 1)
    fx_render_topline

    # 副标题 (用户名) — 行 2
    fx_render_subtitle 2

    # 底部预留: 歌词(5) + 提示(1) + 播放栏(1) + 进度(1) = 8 行
    local bottom_margin=8
    local menu_start=4
    local menu_rows=$((lines - menu_start - bottom_margin))
    [[ $menu_rows -lt 4 ]] && menu_rows=4

    # 菜单双列时, 实际占用行数 = ceil(total/2)
    local total=${#FX_MENU_TITLE[@]}
    local actual_rows
    if [[ $cols -ge 88 ]]; then
        actual_rows=$(( (total + 1) / 2 ))
    else
        actual_rows=$total
    fi

    # 垂直居中菜单
    local menu_pad=$(( (menu_rows - actual_rows) / 2 ))
    [[ $menu_pad -lt 0 ]] && menu_pad=0
    fx_render_menu $((menu_start + menu_pad))

    # 歌词区 (底部居中) — 占 5 行
    local lyric_start=$((lines - bottom_margin + 1))
    [[ $lyric_start -lt $((menu_start + menu_rows)) ]] && lyric_start=$((menu_start + menu_rows + 1))
    fx_render_lyrics "$lyric_start" 5

    # 帮助提示 (歌词后 1 行间隔)
    local hint_row=$((lyric_start + 5))
    fx_render_hint "$hint_row"

    # 底部播放栏
    fx_render_playbar $((lines - 1))

    # 进度条 (最后一行)
    fx_render_progress "$lines"
}

#==============================================================================
# 渲染: 帮助提示行 (go-musicfox 风格)
#==============================================================================
fx_render_hint() {
    local row="$1" cols
    cols=$(fx_cols)
    fx_goto "$row" 1
    fx_clear_line
    local hint="[j/k]移动  [Enter]进入  [/]搜索  [Space]播放暂停  [q]退出"
    local w
    w=$(fx_width "$hint")
    local left=$(( (cols - w) / 2 ))
    [[ $left -lt 0 ]] && left=0
    printf '%*s' "$left" ''
    printf '%s%s%s' "${FX_DIM}" "$hint" "${FX_RESET}"
}

#==============================================================================
# 清理
#==============================================================================
fx_cleanup() {
    printf '%s%s%s' "${FX_ALT_OFF}" "${FX_SHOW_CURSOR}" "${FX_RESET}"
}

#==============================================================================
# 操作函数 (主事件循环调用)
#==============================================================================
fx_op_move_up() {
    FX_MENU_SEL=$(( ${FX_MENU_SEL:-0} - 1 ))
    [[ ${FX_MENU_SEL} -lt 0 ]] && FX_MENU_SEL=0
    return 0
}

fx_op_move_down() {
    local n=${#FX_MENU_TITLE[@]}
    [[ $n -eq 0 ]] && return 0
    FX_MENU_SEL=$(( ${FX_MENU_SEL:-0} + 1 ))
    [[ ${FX_MENU_SEL} -ge $n ]] && FX_MENU_SEL=$((n - 1))
    return 0
}

fx_op_quit() {
    return 2  # 通知主循环退出
}

fx_op_rerender() {
    fx_render
    return 0
}

#==============================================================================
# 主循环辅助: 检测 Main 菜单
#==============================================================================
fx_init_main_menu

# python3 歌词模块路径 (自动定位)
if [[ -z "${FX_LYRIC_PY:-}" ]]; then
    _fx_self_dir="${BASH_SOURCE[0]%/*}"
    if [[ -f "$_fx_self_dir/lyric.py" ]]; then
        export FX_LYRIC_PY="$_fx_self_dir/lyric.py"
    fi
fi