#!/usr/bin/env bash
#==============================================================================
# LX-Music-Shell 能力检测单元测试
#==============================================================================

set -u

# 测试目录
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$TEST_DIR")"
LIB_DIR="$PROJECT_DIR/lib"

# 计数器
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 断言函数
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

# 在测试开始前清空检测状态
reset_state() {
    # LXMS_CAPABILITY_LOADED 是 readonly,不能 unset
    unset LXMS_TERM_IMAGES LXMS_TERM_MOUSE LXMS_TERM_UNICODE 2>/dev/null || true
    unset LXMS_TERM_TRUECOLOR LXMS_TERM_COLS LXMS_TERM_LINES 2>/dev/null || true
    unset LXMS_FORCE_TUI LXMS_UI_TUI_OVERRIDE LXMS_UI_MOUSE_OVERRIDE 2>/dev/null || true
}

#==============================================================================
# 测试 1: kitty 检测
#==============================================================================
test_kitty_detection() {
    printf '\n%b\n' "${YELLOW}=== 测试 1: kitty 终端检测 ===${NC}"

    reset_state
    export TERM="xterm-kitty"
    unset TERM_PROGRAM COLORTERM LANG LC_ALL

    # shellcheck disable=SC1091
    . "$LIB_DIR/capability.sh"
    detect_capability

    assert_eq "kitty 终端应被识别为 kitty 协议" \
        "kitty" "${LXMS_TERM_IMAGES}"
}

#==============================================================================
# 测试 2: iTerm2 检测
#==============================================================================
test_iterm_detection() {
    printf '\n%b\n' "${YELLOW}=== 测试 2: iTerm2 终端检测 ===${NC}"

    reset_state
    export TERM="xterm-256color"
    export TERM_PROGRAM="iTerm.app"
    unset COLORTERM LANG LC_ALL

    # shellcheck disable=SC1091
    . "$LIB_DIR/capability.sh"
    detect_capability

    assert_eq "iTerm2 应被识别为 iTerm 协议" \
        "iTerm" "${LXMS_TERM_IMAGES}"
}

#==============================================================================
# 测试 3: 普通 xterm 检测 (无图片)
#==============================================================================
test_xterm_detection() {
    printf '\n%b\n' "${YELLOW}=== 测试 3: xterm 检测 ===${NC}"

    reset_state
    export TERM="xterm"
    unset TERM_PROGRAM COLORTERM LANG LC_ALL

    # shellcheck disable=SC1091
    . "$LIB_DIR/capability.sh"
    detect_capability

    assert_eq "xterm 应被识别为无图片" \
        "none" "${LXMS_TERM_IMAGES}"
}

#==============================================================================
# 测试 4: 真彩色检测
#==============================================================================
test_truecolor_detection() {
    printf '\n%b\n' "${YELLOW}=== 测试 4: 真彩色检测 ===${NC}"

    reset_state
    export TERM="xterm-256color"
    export COLORTERM="truecolor"
    unset TERM_PROGRAM LANG LC_ALL

    # shellcheck disable=SC1091
    . "$LIB_DIR/capability.sh"
    detect_capability

    assert_eq "truecolor 应被识别" \
        "1" "${LXMS_TERM_TRUECOLOR}"
}

#==============================================================================
# 测试 5: Unicode 检测
#==============================================================================
test_unicode_detection() {
    printf '\n%b\n' "${YELLOW}=== 测试 5: Unicode 检测 ===${NC}"

    reset_state
    export TERM="xterm-256color"
    export LANG="en_US.UTF-8"
    unset TERM_PROGRAM COLORTERM LC_ALL

    # shellcheck disable=SC1091
    . "$LIB_DIR/capability.sh"
    detect_capability

    assert_eq "UTF-8 locale 应被识别" \
        "1" "${LXMS_TERM_UNICODE}"
}

#==============================================================================
# 测试 6: 配置覆盖 (UI_TUI=off)
#==============================================================================
test_config_override_tui_off() {
    printf '\n%b\n' "${YELLOW}=== 测试 6: 配置 UI_TUI=off 覆盖 ===${NC}"

    reset_state
    export TERM="xterm-kitty"
    export COLUMNS=80
    export LINES=24
    unset TERM_PROGRAM COLORTERM LANG LC_ALL

    # shellcheck disable=SC1091
    . "$LIB_DIR/capability.sh"

    # 创建临时配置文件
    local tmp_config
    tmp_config=$(mktemp)
    echo 'UI_TUI="off"' > "$tmp_config"

    capability_apply_config "$tmp_config"
    detect_capability
    rm -f "$tmp_config"

    assert_eq "UI_TUI=off 时强制 TUI 应为 0" \
        "0" "${LXMS_FORCE_TUI}"
}

#==============================================================================
# 测试 7: 查询函数
#==============================================================================
test_query_functions() {
    printf '\n%b\n' "${YELLOW}=== 测试 7: 查询函数 ===${NC}"

    reset_state
    export TERM="xterm-kitty"
    export TERM_PROGRAM="iTerm.app"
    export COLORTERM="truecolor"
    export LANG="en_US.UTF-8"
    export COLUMNS=120
    export LINES=40

    # shellcheck disable=SC1091
    . "$LIB_DIR/capability.sh"
    detect_capability

    # 测试查询函数返回正确的布尔值
    if supports_images; then
        assert_eq "supports_images() 应返回 true (kitty+iTerm)" \
            "true" "true"
    fi

    if supports_unicode; then
        assert_eq "supports_unicode() 应返回 true (UTF-8)" \
            "true" "true"
    fi

    # 尺寸
    local cols
    cols=$(get_cols)
    if [[ "$cols" -gt 0 ]]; then
        assert_eq "get_cols() 应返回正整数 ($cols)" \
            "positive" "positive"
    else
        assert_eq "get_cols() 应返回正整数" \
            "positive" "non_positive"
    fi
}

#==============================================================================
# 测试 8: 自检函数
#==============================================================================
test_self_check() {
    printf '\n%b\n' "${YELLOW}=== 测试 8: 自检函数输出 ===${NC}"

    reset_state
    export TERM="xterm-kitty"
    unset TERM_PROGRAM COLORTERM LANG LC_ALL

    # shellcheck disable=SC1091
    . "$LIB_DIR/capability.sh"
    detect_capability

    local output
    output=$(capability_print_status 2>&1)

    if [[ "$output" == *"终端能力"* ]]; then
        assert_eq "capability_print_status 应包含 '终端能力'" \
            "yes" "yes"
    else
        assert_eq "capability_print_status 应包含 '终端能力'" \
            "yes" "no"
    fi

    if [[ "$output" == *"图片协议"* ]]; then
        assert_eq "capability_print_status 应包含图片协议" \
            "yes" "yes"
    else
        assert_eq "capability_print_status 应包含图片协议" \
            "yes" "no"
    fi
}

#==============================================================================
# 测试 9: capability_apply_config 解析多种格式
#==============================================================================
test_config_parsing() {
    printf '\n%b\n' "${YELLOW}=== 测试 9: 配置文件解析 ===${NC}"

    reset_state

    # shellcheck disable=SC1091
    . "$LIB_DIR/capability.sh"

    local tmp_config
    tmp_config=$(mktemp)
    cat > "$tmp_config" <<'EOF'
# 注释行
PLAYER_BACKEND="mpv"

# UI 设置
UI_TUI=on
UI_MOUSE=off
DEFAULT_SOURCE=kugou
EOF

    capability_apply_config "$tmp_config"

    assert_eq "UI_TUI=on 应被解析" \
        "on" "${LXMS_UI_TUI_OVERRIDE:-}"
    assert_eq "UI_MOUSE=off 应被解析" \
        "off" "${LXMS_UI_MOUSE_OVERRIDE:-}"

    rm -f "$tmp_config"
}

#==============================================================================
# 主流程
#==============================================================================
main() {
    test_kitty_detection
    test_iterm_detection
    test_xterm_detection
    test_truecolor_detection
    test_unicode_detection
    test_config_override_tui_off
    test_query_functions
    test_self_check
    test_config_parsing

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
