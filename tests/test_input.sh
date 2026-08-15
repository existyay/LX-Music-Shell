#!/usr/bin/env bash
#==============================================================================
# LX-Music-Shell 输入处理单元测试
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

# 加载模块 (每次需要独立的常量)
load_input() {
    unset INPUT_REGIONS
    unset INPUT_LAST_CLICK_X INPUT_LAST_CLICK_Y INPUT_LAST_CLICK_TIME
    unset EVENT_TYPE EVENT_DATA EVENT_DATA_X EVENT_DATA_Y
    unset INPUT_LOADED LXMS_INPUT_LOADED 2>/dev/null || true

    # shellcheck disable=SC1091
    . "$LIB_DIR/input.sh"
}

#==============================================================================
# 测试 1: 方向键解析
#==============================================================================
test_arrow_keys() {
    printf '\n%b\n' "${YELLOW}=== 测试 1: 方向键解析 ===${NC}"

    load_input

    # 上箭头
    input_parse_keyboard $'\033[A'
    assert_eq "上箭头" "$EVENT_KEY_UP" "$EVENT_TYPE"

    # 下箭头
    input_parse_keyboard $'\033[B'
    assert_eq "下箭头" "$EVENT_KEY_DOWN" "$EVENT_TYPE"

    # 左箭头
    input_parse_keyboard $'\033[D'
    assert_eq "左箭头" "$EVENT_KEY_LEFT" "$EVENT_TYPE"

    # 右箭头
    input_parse_keyboard $'\033[C'
    assert_eq "右箭头" "$EVENT_KEY_RIGHT" "$EVENT_TYPE"
}

#==============================================================================
# 测试 2: 功能键
#==============================================================================
test_function_keys() {
    printf '\n%b\n' "${YELLOW}=== 测试 2: 功能键 ===${NC}"

    load_input

    input_parse_keyboard $'\n'
    assert_eq "Enter 键" "$EVENT_KEY_ENTER" "$EVENT_TYPE"

    input_parse_keyboard $'\t'
    assert_eq "Tab 键" "$EVENT_KEY_TAB" "$EVENT_TYPE"

    input_parse_keyboard ' '
    assert_eq "空格键" "$EVENT_KEY_SPACE" "$EVENT_TYPE"

    input_parse_keyboard 'q'
    assert_eq "q 键返回 KEY_CHAR" "$EVENT_KEY_CHAR" "$EVENT_TYPE"
    assert_eq "q 键数据" "q" "$EVENT_DATA"

    input_parse_keyboard 'Q'
    assert_eq "Q 键返回 KEY_CHAR" "$EVENT_KEY_CHAR" "$EVENT_TYPE"
    assert_eq "Q 键数据" "Q" "$EVENT_DATA"
}

#==============================================================================
# 测试 3: 普通字符
#==============================================================================
test_char_keys() {
    printf '\n%b\n' "${YELLOW}=== 测试 3: 普通字符 ===${NC}"

    load_input

    input_parse_keyboard 'a'
    assert_eq "字符 'a' 应为 KEY_CHAR" "$EVENT_KEY_CHAR" "$EVENT_TYPE"
    assert_eq "字符 'a' 数据" "a" "$EVENT_DATA"

    input_parse_keyboard '字'
    assert_eq "中文字符" "$EVENT_KEY_CHAR" "$EVENT_TYPE"
    assert_eq "中文字符数据" "字" "$EVENT_DATA"
}

#==============================================================================
# 测试 4: SGR 鼠标协议
#==============================================================================
test_mouse_sgr() {
    printf '\n%b\n' "${YELLOW}=== 测试 4: SGR 鼠标协议 ===${NC}"

    load_input

    # 鼠标左键点击
    input_parse_mouse $'\033[<0;15;10;M'
    assert_eq "鼠标点击类型" "$EVENT_MOUSE_CLICK" "$EVENT_TYPE"
    assert_eq "鼠标 X 坐标" "15" "$EVENT_DATA_X"
    assert_eq "鼠标 Y 坐标" "10" "$EVENT_DATA_Y"

    # 鼠标释放
    input_parse_mouse $'\033[<0;15;10;m'
    assert_eq "鼠标释放" "$EVENT_MOUSE_RELEASE" "$EVENT_TYPE"

    # 滚轮向上
    load_input
    input_parse_mouse $'\033[<64;15;10;M'
    assert_eq "滚轮向上" "$EVENT_MOUSE_SCROLL_UP" "$EVENT_TYPE"

    # 滚轮向下
    load_input
    input_parse_mouse $'\033[<65;15;10;M'
    assert_eq "滚轮向下" "$EVENT_MOUSE_SCROLL_DOWN" "$EVENT_TYPE"

    # 右键
    load_input
    input_parse_mouse $'\033[<2;30;5;M'
    assert_eq "右键点击" "$EVENT_MOUSE_CLICK" "$EVENT_TYPE"
    assert_eq "右键 X" "30" "$EVENT_DATA_X"
    assert_eq "右键 Y" "5" "$EVENT_DATA_Y"
}

#==============================================================================
# 测试 5: 双击检测
#==============================================================================
test_double_click() {
    printf '\n%b\n' "${YELLOW}=== 测试 5: 双击检测 ===${NC}"

    load_input

    # 第一次点击 - 重置时间状态
    LOAD_INPUT_LAST_TIME=0
    input_parse_mouse $'\033[<0;10;5;M'
    assert_eq "第一次点击" "$EVENT_MOUSE_CLICK" "$EVENT_TYPE"

    # 立即第二次点击 - 应该被识别为双击
    input_parse_mouse $'\033[<0;10;5;M'
    assert_eq "立即第二次相同位置点击应为双击" \
        "$EVENT_MOUSE_DOUBLE" "$EVENT_TYPE"
}

#==============================================================================
# 测试 6: 区域命中测试
#==============================================================================
test_region_hit() {
    printf '\n%b\n' "${YELLOW}=== 测试 6: 区域命中测试 ===${NC}"

    load_input

    input_register_region "list" 5 0 20 40
    input_register_region "detail" 5 40 20 60
    input_register_region "search" 1 0 3 100

    # 点击 list 区域
    local hit
    input_mouse_to_action 10 10
    hit="${INPUT_HIT_REGION:-}"
    assert_eq "点击 list 区域" "list" "$hit"

    # 点击 detail 区域
    input_mouse_to_action 50 10
    hit="${INPUT_HIT_REGION:-}"
    assert_eq "点击 detail 区域" "detail" "$hit"

    # 点击 search 区域
    input_mouse_to_action 50 1
    hit="${INPUT_HIT_REGION:-}"
    assert_eq "点击 search 区域" "search" "$hit"

    # 点击空白处 - 应返回错误
    if input_mouse_to_action 10 25 2>/dev/null; then
        assert_eq "点击空白处应失败" "no_hit" "hit_somehow"
    else
        assert_eq "点击空白处应失败" "no_hit" "no_hit"
    fi

    input_clear_regions
    if input_mouse_to_action 10 10 2>/dev/null; then
        assert_eq "清除区域后点击应失败" "no_hit" "hit_somehow"
    else
        assert_eq "清除区域后点击应失败" "no_hit" "no_hit"
    fi
}

#==============================================================================
# 测试 7: 事件名称
#==============================================================================
test_event_names() {
    printf '\n%b\n' "${YELLOW}=== 测试 7: 事件名称辅助函数 ===${NC}"

    load_input

    local name
    name=$(input_event_name $EVENT_KEY_UP)
    assert_eq "事件名称 - UP" "KEY_UP" "$name"

    name=$(input_event_name $EVENT_MOUSE_CLICK)
    assert_eq "事件名称 - MOUSE_CLICK" "MOUSE_CLICK" "$name"

    name=$(input_event_name $EVENT_NONE)
    assert_eq "事件名称 - NONE" "NONE" "$name"

    name=$(input_event_name $EVENT_KEY_QUIT)
    assert_eq "事件名称 - QUIT" "KEY_QUIT" "$name"
}

#==============================================================================
# 主流程
#==============================================================================
main() {
    test_arrow_keys
    test_function_keys
    test_char_keys
    test_mouse_sgr
    test_double_click
    test_region_hit
    test_event_names

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
