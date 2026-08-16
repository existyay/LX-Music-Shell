#!/usr/bin/env bash
#==============================================================================
# LX-Music-Shell 统一 TUI 单元测试 (v3)
#==============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TUI_SH="${PROJECT_ROOT}/lib/tui.sh"
INPUT_SH="${PROJECT_ROOT}/lib/input.sh"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    ((TESTS_RUN++))
    if [[ "$expected" == "$actual" ]]; then
        ((TESTS_PASSED++))
        printf '%b\n' "  ${GREEN}✓${NC} $desc"
    else
        ((TESTS_FAILED++))
        printf '%b\n' "  ${RED}✗${NC} $desc"
        printf '       期望: %s\n       实际: %s\n' "$expected" "$actual"
    fi
}

assert_contains() {
    local desc="$1" haystack="$2" needle="$3"
    ((TESTS_RUN++))
    if [[ "$haystack" == *"$needle"* ]]; then
        ((TESTS_PASSED++))
        printf '%b\n' "  ${GREEN}✓${NC} $desc"
    else
        ((TESTS_FAILED++))
        printf '%b\n' "  ${RED}✗${NC} $desc"
        printf '       期望包含: %s\n' "$needle"
    fi
}

strip_ansi() {
    printf '%s' "$1" | sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' | tr -d '\033'
}

# 加载模块 (input.sh 提供区域注册函数)
. "$INPUT_SH"
. "$TUI_SH"

#==============================================================================
echo -e "${YELLOW}=== 测试 1: 字符宽度 ===${NC}"
#==============================================================================

assert_eq "ASCII 宽度" "5" "$(tui_width 'hello')"
assert_eq "中文 2 字 = 4 列" "4" "$(tui_width '稻香')"
assert_eq "混合宽度" "7" "$(tui_width '稻香-AB')"
assert_eq "空串 = 0" "0" "$(tui_width '')"
assert_eq "数字冒号" "5" "$(tui_width '03:42')"

#==============================================================================
echo -e "${YELLOW}=== 测试 2: 截断 ===${NC}"
#==============================================================================

assert_eq "短串不截断" "hello" "$(tui_trunc 'hello' 10)"
out=$(tui_trunc '回到过去的美好时光' 8)
w=$(tui_width "$out")
assert_eq "长串截断后宽度<=8" "1" "$([ $w -le 8 ] && echo 1 || echo 0)"
assert_contains "截断加省略号" "$out" "…"

#==============================================================================
echo -e "${YELLOW}=== 测试 3: 菜单 ===${NC}"
#==============================================================================

assert_eq "菜单项数量=7" "7" "${#TUI_MENU_ITEMS[@]}"
assert_eq "首项 action" "search" "$(printf '%s' "${TUI_MENU_ITEMS[0]#*|}")"
assert_eq "末项 action" "quit" "$(printf '%s' "${TUI_MENU_ITEMS[6]#*|}")"

UI_SELECTED=3
assert_eq "选中项 action" "quality" "$(tui_menu_selected_action)"

#==============================================================================
echo -e "${YELLOW}=== 测试 4: 模式名 / 状态图标 ===${NC}"
#==============================================================================

PLAY_MODE=list; assert_eq "list 模式名" "列表" "$(tui_mode_name)"
PLAY_MODE=loop; assert_eq "loop 模式名" "列表循环" "$(tui_mode_name)"
PLAY_MODE=single; assert_eq "single 模式名" "单曲循环" "$(tui_mode_name)"
PLAY_MODE=random; assert_eq "random 模式名" "随机" "$(tui_mode_name)"

PLAYER_STATUS=playing; assert_eq "播放图标" "▶" "$(tui_state_icon)"
PLAYER_STATUS=paused; assert_eq "暂停图标" "⏸" "$(tui_state_icon)"
PLAYER_STATUS=stopped; assert_eq "停止图标" "⏹" "$(tui_state_icon)"

#==============================================================================
echo -e "${YELLOW}=== 测试 5: 歌词解析 ===${NC}"
#==============================================================================

LXMS_LRC_RAW="[00:00.00]第一行
[00:05.00]第二行
[00:10.50]第三行"
tui_lyric_parse
assert_eq "歌词时间数组" "0 5 10" "${TUI_LRC_TIMES[*]}"
assert_eq "歌词文本数组" "第一行 第二行 第三行" "${TUI_LRC_TEXTS[*]}"

assert_eq "0s 索引" "0" "$(tui_lyric_index 0)"
assert_eq "7s 索引 (应指向 5s 行)" "1" "$(tui_lyric_index 7)"
assert_eq "12s 索引" "2" "$(tui_lyric_index 12)"

# 元数据行应被跳过
LXMS_LRC_RAW="[ar:歌手]
[00:01.00]正文"
tui_lyric_parse
assert_eq "元数据行跳过" "1" "${#TUI_LRC_TEXTS[@]}"

#==============================================================================
echo -e "${YELLOW}=== 测试 6: 操作函数 ===${NC}"
#==============================================================================

UI_SCREEN=menu; UI_SELECTED=1
tui_op_move_up; assert_eq "menu move_up 1->0" "0" "$UI_SELECTED"
tui_op_move_up; assert_eq "menu move_up clamp 0" "0" "$UI_SELECTED"
tui_op_move_down; assert_eq "menu move_down 0->1" "1" "$UI_SELECTED"
tui_op_move_bottom; assert_eq "menu move_bottom ->6" "6" "$UI_SELECTED"

UI_SCREEN=search
PLAYLIST=("a|1|2|3|4|5|6|7|8" "b|1|2|3|4|5|6|7|8" "c|1|2|3|4|5|6|7|8")
UI_SELECTED=0
tui_op_move_down; assert_eq "search move_down 0->1" "1" "$UI_SELECTED"
tui_op_move_down; tui_op_move_down; assert_eq "search move_down clamp 2" "2" "$UI_SELECTED"
tui_op_move_top; assert_eq "search move_top" "0" "$UI_SELECTED"

UI_SCREEN=quality_select
TUI_SELECT_ITEMS=("HiRes (母带)" "FLAC (无损)" "HQ (320k)" "SQ (128k)")
UI_SELECTED=0; UI_SCROLL_TOP=0
tui_op_move_down; assert_eq "select move_down 0->1" "1" "$UI_SELECTED"
tui_op_move_bottom; assert_eq "select move_bottom ->3" "3" "$UI_SELECTED"
tui_op_move_top; assert_eq "select move_top" "0" "$UI_SELECTED"
tui_item_count_result=$(tui_item_count)
assert_eq "select item count=4" "4" "$tui_item_count_result"

#==============================================================================
echo -e "${YELLOW}=== 测试 7: 鼠标区域命中 → 动作 ===${NC}"
#==============================================================================

export COLUMNS=100 LINES=30
UI_SCREEN=search; UI_SELECTED=0; UI_SCROLL_TOP=0
PLAYLIST=("a|1|2|3|4|5|6|7|8" "b|1|2|3|4|5|6|7|8" "c|1|2|3|4|5|6|7|8")
PLAYLIST_INDEX=0
tui_register_regions 4 12

assert_eq "点击列表首行" "list:0" "$(tui_mouse_action 5 5)"
assert_eq "点击列表第二行" "list:1" "$(tui_mouse_action 5 6)"
assert_eq "点击搜索框" "search" "$(tui_mouse_action 5 4)"
assert_eq "点击播放栏左侧=toggle" "toggle" "$(tui_mouse_action 5 29)"
assert_eq "点击进度条 seek" "seek:50" "$(tui_mouse_action 50 30)"

UI_SCREEN=quality_select
TUI_SELECT_ITEMS=("HiRes (母带)" "FLAC (无损)" "HQ (320k)" "SQ (128k)")
UI_SELECTED=0; UI_SCROLL_TOP=0
tui_register_regions 4 12
assert_eq "点击选择项首行" "select:0" "$(tui_mouse_action 5 5)"
assert_eq "点击选择项第二行" "select:1" "$(tui_mouse_action 5 6)"

#==============================================================================
echo -e "${YELLOW}=== 测试 8: 渲染输出 ===${NC}"
#==============================================================================

render_menu() {
    UI_SCREEN="menu"
    PLAYER_STATUS="playing"
    PLAYBACK_POSITION=95
    PLAYBACK_DURATION=222
    VOLUME=80
    PLAY_MODE=list
    CURRENT_SOURCE_NAME="网易云音乐"
    VERSION="3.0"
    LXMS_LRC_RAW=""
    tui_render 2>/dev/null
}

out=$(render_menu)
clean=$(strip_ansi "$out")
assert_contains "菜单渲染含标题" "$clean" "LX-Music-Shell"
assert_contains "菜单渲染含搜索项" "$clean" "搜索音乐"
assert_contains "菜单渲染含退出项" "$clean" "退出"

render_search() {
    UI_SCREEN="search"
    UI_FOCUS="list"
    UI_QUERY="稻香"
    PLAYER_STATUS="playing"
    PLAYBACK_POSITION=95
    PLAYBACK_DURATION=222
    VOLUME=80
    PLAY_MODE=list
    DEFAULT_QUALITY="flac"
    CURRENT_SOURCE_NAME="网易云音乐"
    VERSION="3.0"
    LXMS_LRC_RAW=""
    tui_render 2>/dev/null
}

out=$(render_search)
clean=$(strip_ansi "$out")
assert_contains "搜索渲染含搜索框" "$clean" "搜索"
assert_contains "搜索渲染含音质 chip" "$clean" "FLAC"
assert_contains "搜索渲染含播放栏" "$clean" "🔊80%"
assert_contains "搜索渲染含当前时间" "$clean" "01:35"
assert_contains "搜索渲染含总时长" "$clean" "03:42"
assert_contains "搜索渲染含百分比" "$clean" "%"

render_quality_select() {
    UI_SCREEN="quality_select"
    UI_FOCUS="list"
    TUI_SELECT_TITLE="选择音质"
    TUI_SELECT_ITEMS=("HiRes (母带)" "FLAC (无损)" "HQ (320k)" "SQ (128k)")
    UI_SELECTED=1; UI_SCROLL_TOP=0
    tui_render_select 4 10 2>/dev/null
}
out=$(render_quality_select)
clean=$(strip_ansi "$out")
assert_contains "音质选择渲染含标题" "$clean" "选择音质"
assert_contains "音质选择渲染含 FLAC" "$clean" "FLAC (无损)"

#==============================================================================
# 结果
#==============================================================================
echo ""
echo "========================================"
echo "总计: $TESTS_RUN 运行"
echo "通过: $TESTS_PASSED"
echo "失败: $TESTS_FAILED"
echo "========================================"

[[ $TESTS_FAILED -eq 0 ]]
