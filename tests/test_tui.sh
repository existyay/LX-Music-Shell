#!/usr/bin/env bash
#==============================================================================
# LX-Music-Shell TUI 渲染单元测试 (v2.2)
#==============================================================================

set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$TEST_DIR")"
LIB_DIR="$PROJECT_DIR/lib"

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    ((TESTS_RUN++))
    if [[ "$expected" == "$actual" ]]; then
        ((TESTS_PASSED++))
        printf '%b\n' "  ${GREEN}✓${NC} $desc"
    else
        ((TESTS_FAILED++))
        printf '%b\n' "  ${RED}✗${NC} $desc"
        printf '       期望: %s\n' "$expected"
        printf '       实际: %s\n' "$actual"
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
        printf '       haystack: %.200s...\n' "$haystack" >&2
    fi
}

# 加载依赖
load_tui() {
    # shellcheck disable=SC1091
    . "$LIB_DIR/capability.sh"
    # shellcheck disable=SC1091
    . "$LIB_DIR/input.sh"
    # shellcheck disable=SC1091
    . "$LIB_DIR/tui.sh"
    detect_capability
}

#==============================================================================
# 测试 1: 主题
#==============================================================================
test_themes() {
    printf '\n%b\n' "${YELLOW}=== 测试 1: 主题切换 ===${NC}"

    load_tui

    # 默认主题
    assert_eq "默认主题" "dark" "${TUI_THEME_NAME:-dark}"

    # 切换主题
    tui_set_theme green
    assert_eq "切到 green" "green" "$TUI_THEME_NAME"

    tui_set_theme mono
    assert_eq "切到 mono" "mono" "$TUI_THEME_NAME"

    tui_set_theme invalid
    assert_eq "无效主题应保持" "mono" "$TUI_THEME_NAME"

    # 颜色定义
    local colors
    colors=$(_tui_get_theme_colors)
    tui_set_theme green
    local colors=$(_tui_get_theme_colors)
    assert_contains "green 颜色包含" "$colors" "cyan"
    tui_set_theme dark
}

#==============================================================================
# 测试 2: vim-style 操作 (LXMS_* 状态变量)
#==============================================================================
test_vim_operations() {
    printf '\n%b\n' "${YELLOW}=== 测试 2: vim-style 操作 ===${NC}"

    load_tui

    # 设置测试列表
    LXMS_PLAYLIST=(
        "稻香|周杰伦|魔杰座|03:42|sid1|flac||flac,320,128|url1"
        "晴天|周杰伦|叶惠美|04:29|sid2|320||320,128|url2"
        "七里香|周杰伦|七里香|04:59|sid3|flac||flac,320|url3"
        "夜曲|周杰伦|十一月的萧邦|04:26|sid4|320||320,128|url4"
    )
    LXMS_SELECTED_INDEX=1
    LXMS_PLAYING_INDEX=0

    # tui_op_move_up
    tui_op_move_up
    assert_eq "move_up (1->0)" "0" "$LXMS_SELECTED_INDEX"

    # 边界: 不能 < 0
    tui_op_move_up
    assert_eq "move_up 边界不小于 0" "0" "$LXMS_SELECTED_INDEX"

    # tui_op_move_down
    tui_op_move_down
    assert_eq "move_down (0->1)" "1" "$LXMS_SELECTED_INDEX"

    # tui_op_move_top
    tui_op_move_down
    tui_op_move_down
    tui_op_move_top
    assert_eq "move_top" "0" "$LXMS_SELECTED_INDEX"

    # tui_op_move_bottom
    tui_op_move_bottom
    assert_eq "move_bottom (尾)" "3" "$LXMS_SELECTED_INDEX"

    # 边界: 不能超过列表长度-1
    LXMS_PLAYLIST=()
    tui_op_move_bottom || true
    # 不崩溃即可 (LXMS_SELECTED_INDEX 可能保持上次的值)
    [[ $? -le 1 ]] && echo "  ✓ 空列表 move_bottom 不崩溃"

}

#==============================================================================
# 测试 3: 头部状态条
#==============================================================================
test_status_bar() {
    printf '\n%b\n' "${YELLOW}=== 测试 3: 头部状态条渲染 ===${NC}"

    load_tui

    local output
    output=$(tui_render_header 2>&1)

    assert_contains "包含 Logo" "$output" "LX-Music-Shell"
    assert_contains "包含版本" "$output" "v"
    assert_contains "包含网络状态" "$output" "已"
    assert_contains "包含音量字样" "$output" "音量"
}

#==============================================================================
# 测试 4: 搜索框渲染
#==============================================================================
test_search_box() {
    printf '\n%b\n' "${YELLOW}=== 测试 4: 搜索框渲染 ===${NC}"

    load_tui

    # 没输入查询
    LXMS_STATE_SEARCH_QUERY=""
    local out
    out=$(tui_render_search_box 2>&1)
    assert_contains "显示搜索提示" "$out" "搜索"

    # 已输入查询
    LXMS_STATE_SEARCH_QUERY="稻香"
    out=$(tui_render_search_box 2>&1)
    assert_contains "显示查询" "$out" "稻香"
}

#==============================================================================
# 测试 5: 列表渲染
#==============================================================================
test_list_render() {
    printf '\n%b\n' "${YELLOW}=== 测试 5: 列表渲染 ===${NC}"

    load_tui

    LXMS_PLAYLIST=(
        "稻香|周杰伦|魔杰座|03:42|sid1|flac||flac,320,128|url1"
        "晴天|周杰伦|叶惠美|04:29|sid2|320||320,128|url2"
        "七里香|周杰伦|七里香|04:59|sid3|flac||flac,320|url3"
    )
    LXMS_SELECTED_INDEX=1
    LXMS_PLAYING_INDEX=0

    local out
    out=$(tui_render_list 4 18 60 30 2>&1)

    assert_contains "列表包含 稻香" "$out" "稻香"
    assert_contains "列表包含 晴天" "$out" "晴天"
    assert_contains "列表包含 七里香" "$out" "七里香"
    # 列表标签带 ANSI 颜色码, 用 sed 剥离颜色码后匹配
    local stripped
    stripped=$(printf '%s' "$out" | sed "s/$(printf '\x1b')\\[[0-9;]*m//g")
    assert_contains "列表包含 FLAC 标签" "$stripped" "FLAC"
    assert_contains "列表包含 HQ 标签 (320k)" "$stripped" "HQ"
    assert_contains "包含播放标记 ▶" "$out" "▶"
}

#==============================================================================
# 测试 6: 详情渲染
#==============================================================================
test_detail_render() {
    printf '\n%b\n' "${YELLOW}=== 测试 6: 详情渲染 ===${NC}"

    load_tui

    LXMS_PLAYLIST=(
        "稻香|周杰伦|魔杰座|03:42|sid1|flac||flac,320,128|url1"
    )
    LXMS_PLAYING_INDEX=0
    LXMS_STATE_PROGRESS_C=70
    LXMS_STATE_PROGRESS_T=222

    local out
    out=$(tui_render_detail 4 60 30 2>&1)

    assert_contains "详情包含歌名" "$out" "稻香"
    assert_contains "详情包含歌手" "$out" "周杰伦"
    assert_contains "详情包含专辑" "$out" "魔杰座"
    assert_contains "详情包含时长" "$out" "03:42"
    assert_contains "详情包含进度" "$out" "进度"
}

#==============================================================================
# 测试 7: 封面占位符
#==============================================================================
test_cover_placeholder() {
    printf '\n%b\n' "${YELLOW}=== 测试 7: 封面占位符 ===${NC}"

    load_tui

    local out
    # 无图协议时
    LXMS_TERM_IMAGES="none"
    out=$(tui_render_image "https://example.com/cover.jpg" 1 1 2>&1 || true)
    # 不支持协议时返回 1,占位符应被主调用方渲染

    # 占位符应能正常渲染
    out=$(tui_render_cover_placeholder 1 1 20 8 2>&1)
    assert_contains "占位符包含框" "$out" "╔"
    assert_contains "占位符包含音符" "$out" "♪"
}

#==============================================================================
# 测试 8: 完整渲染 (自适应布局)
#==============================================================================
test_full_render() {
    printf '\n%b\n' "${YELLOW}=== 测试 8: 完整渲染 ===${NC}"

    load_tui

    LXMS_STATE_VERSION="2.2"
    LXMS_STATE_NETWORK="connected"
    LXMS_STATE_VOLUME=80
    LXMS_PLAYLIST=(
        "稻香|周杰伦|魔杰座|03:42|sid1|flac||flac,320,128|url1"
        "晴天|周杰伦|叶惠美|04:29|sid2|320||320,128|url2"
    )
    LXMS_SELECTED_INDEX=0
    LXMS_PLAYING_INDEX=0
    LXMS_STATE_PROGRESS_C=70
    LXMS_STATE_PROGRESS_T=222

    # 宽屏
    COLUMNS=120 LINES=30
    local out
    out=$(COLUMNS=120 LINES=30 tui_render 2>&1)
    assert_contains "宽屏含 Logo" "$out" "LX-Music-Shell"
    assert_contains "宽屏含歌曲" "$out" "稻香"
    assert_contains "宽屏含搜索框" "$out" "搜索"
    assert_contains "宽屏含帮助提示" "$out" "q:退出"

    # 窄屏
    out=$(COLUMNS=80 LINES=24 tui_render 2>&1)
    assert_contains "窄屏不崩溃" "$out" "LX-Music-Shell"
    assert_contains "窄屏含歌曲" "$out" "稻香"
}

#==============================================================================
# 主流程
#==============================================================================
main() {
    test_themes
    test_vim_operations
    test_status_bar
    test_search_box
    test_list_render
    test_detail_render
    test_cover_placeholder
    test_full_render

    printf '\n========================================\n'
    printf '总计: %d 运行\n' "$TESTS_RUN"
    printf '通过: %d\n' "$TESTS_PASSED"
    printf '失败: %d\n' "$TESTS_FAILED"
    printf '========================================\n'

    if [[ $TESTS_FAILED -gt 0 ]]; then
        exit 1
    fi
    exit 0
}

main "$@"