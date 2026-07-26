#!/usr/bin/env bash
#==============================================================================
# LX-Music-Shell TUI 渲染单元测试
#==============================================================================

set -u

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
    local desc="$1"
    local expected="$2"
    local actual="$3"

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
    local desc="$1"
    local haystack="$2"
    local needle="$3"

    ((TESTS_RUN++))
    if [[ "$haystack" == *"$needle"* ]]; then
        ((TESTS_PASSED++))
        printf '%b\n' "  ${GREEN}✓${NC} $desc"
    else
        ((TESTS_FAILED++))
        printf '%b\n' "  ${RED}✗${NC} $desc"
        printf '       期望包含: %s\n' "$needle"
        printf '       实际: %s\n' "$haystack"
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
# 测试 1: 布局计算
#==============================================================================
test_layout_calculation() {
    printf '\n%b\n' "${YELLOW}=== 测试 1: 布局计算 ===${NC}"

    load_tui

    # 宽屏
    tui_calculate_layout 120 30
    assert_eq "宽屏模式" "split" "$TUI_LAYOUT_MODE"

    # 窄屏
    tui_calculate_layout 80 30
    assert_eq "窄屏模式" "stack" "$TUI_LAYOUT_MODE"

    # 高度不足
    tui_calculate_layout 120 20
    assert_eq "高度不足时最小化" "minimal" "$TUI_LAYOUT_MODE"
}

#==============================================================================
# 测试 2: 状态条渲染
#==============================================================================
test_status_bar() {
    printf '\n%b\n' "${YELLOW}=== 测试 2: 状态条渲染 ===${NC}"

    load_tui

    local output
    output=$(tui_render_status_bar 2>&1)

    assert_contains "状态条包含 Logo" "$output" "LX-Music-Shell"
    assert_contains "状态条包含音量" "$output" "音量"
    assert_contains "状态条包含网络状态" "$output" "已"
}

#==============================================================================
# 测试 3: 列表渲染（空播放列表）
#==============================================================================
test_list_empty() {
    printf '\n%b\n' "${YELLOW}=== 测试 3: 空列表渲染 ===${NC}"

    load_tui

    LXMS_PLAYLIST=()
    LXMS_SELECTED_INDEX=0
    LXMS_PLAYING_INDEX=-1

    local output
    output=$(tui_render_list 40 3 20 2>&1)

    # 应该显示标题 (但没有歌曲)
    assert_contains "空列表标题" "$output" "搜索结果"
}

#==============================================================================
# 测试 4: 列表渲染（有歌曲）
#==============================================================================
test_list_with_songs() {
    printf '\n%b\n' "${YELLOW}=== 测试 4: 列表渲染(有歌曲) ===${NC}"

    load_tui

    LXMS_PLAYLIST=(
        "1|稻香|周杰伦|03:42|sid1|flac|cover1|flac,320,128|url1"
        "2|晴天|周杰伦|04:29|sid2|320|cover2|320,128|url2"
        "3|七里香|周杰伦|04:59|sid3|128|cover3|128|url3"
    )
    LXMS_SELECTED_INDEX=1
    LXMS_PLAYING_INDEX=0

    local output
    output=$(tui_render_list 60 3 20 2>&1)

    assert_contains "包含歌曲1 稻香" "$output" "稻香"
    assert_contains "包含歌曲2 晴天" "$output" "晴天"
    assert_contains "包含 FLAC 标签" "$output" "FLAC"
    assert_contains "包含 HQ 标签 (320k)" "$output" "HQ"
}

#==============================================================================
# 测试 5: 详情渲染
#==============================================================================
test_detail_render() {
    printf '\n%b\n' "${YELLOW}=== 测试 5: 详情渲染 ===${NC}"

    load_tui

    # 显示封面测试
    LXMS_TERM_IMAGES="none"
    LXMS_SHOW_COVER=1
    LXMS_PLAYLIST=(
        "1|稻香|周杰伦|魔杰座|03:42|sid1|flac|https://example.com/cover.jpg|flac,320,128|url1"
    )
    LXMS_PLAYING_INDEX=0
    LXMS_PLAYBACK_CURRENT=60
    LXMS_PLAYBACK_TOTAL=222

    local output
    output=$(tui_render_detail 60 3 2>&1)

    assert_contains "详情包含歌名" "$output" "稻香"
    assert_contains "详情包含歌手" "$output" "歌手"
    assert_contains "详情包含 FLAC" "$output" "FLAC"
    assert_contains "详情包含专辑" "$output" "专辑"
    assert_contains "详情包含进度" "$output" "进度"
}

#==============================================================================
# 测试 6: 封面占位符
#==============================================================================
test_cover_placeholder() {
    printf '\n%b\n' "${YELLOW}=== 测试 6: 封面占位符 ===${NC}"

    load_tui
    LXMS_TERM_IMAGES="none"

    local output
    output=$(tui_render_cover "https://example.com/cover.jpg" 3 1 2>&1)
    assert_contains "无图片协议显示占位符" "$output" "无封面"

    LXMS_TERM_IMAGES="kitty"
    output=$(tui_render_cover "https://example.com/cover.jpg" 3 1 2>&1)
    assert_contains "kitty 协议输出 ESC_G" "$output" "_G"
}

#==============================================================================
# 测试 7: 完整渲染
#==============================================================================
test_full_render() {
    printf '\n%b\n' "${YELLOW}=== 测试 7: 完整 TUI 渲染 ===${NC}"

    load_tui

    LXMS_VERSION="v2.0"
    LXMS_NETWORK="connected"
    LXMS_VOLUME=80
    LXMS_PLAYLIST=(
        "1|稻香|周杰伦|03:42|sid1|flac||flac,320,128|url1"
        "2|晴天|周杰伦|04:29|sid2|320||320,128|url2"
    )
    LXMS_SELECTED_INDEX=0
    LXMS_PLAYING_INDEX=0
    LXMS_PLAYBACK_CURRENT=30
    LXMS_PLAYBACK_TOTAL=222

    # 模拟宽屏
    COLUMNS=120
    LINES=30

    local output
    output=$(tui_render 2>&1)

    assert_contains "完整渲染包含 Logo" "$output" "LX-Music-Shell"
    assert_contains "完整渲染包含状态条" "$output" "音量"
    assert_contains "完整渲染包含歌曲" "$output" "稻香"
}

#==============================================================================
# 主流程
#==============================================================================
main() {
    test_layout_calculation
    test_status_bar
    test_list_empty
    test_list_with_songs
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
