#!/usr/bin/env bash
#==============================================================================
# LX-Music-Shell 播放列表 / 搜索结果同步回归测试 (v3)
#
# 验证统一 9 列轨道格式:
#   name|artist|album|duration|song_id|quality|cover|quals|url
# 以及 add_search_result (6 列搜索行 -> 9 列轨道) 的转换正确性。
#==============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
MAIN_SCRIPT="${PROJECT_ROOT}/lx-music-shell"

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

assert_not_contains() {
    local desc="$1" haystack="$2" needle="$3"
    ((TESTS_RUN++))
    if [[ "$haystack" != *"$needle"* ]]; then
        ((TESTS_PASSED++))
        printf '%b\n' "  ${GREEN}✓${NC} $desc"
    else
        ((TESTS_FAILED++))
        printf '%b\n' "  ${RED}✗${NC} $desc"
        printf '       不应包含: %s\n' "$needle"
    fi
}

extract_func() {
    local fname="$1"
    sed -n "/^${fname}()/,/^}/p" "$MAIN_SCRIPT"
}

echo -e "${YELLOW}=== 测试 1: add_to_playlist 追加 9 列轨道 ===${NC}"

test_add_to_playlist() {
    PLAYLIST=()
    LXMS_PLAYLIST=()
    eval "$(extract_func add_to_playlist)"

    add_to_playlist "稻香|周杰伦|魔杰座|03:42|185810|flac|http://c.jpg|flac,320|http://u.mp3"

    assert_eq "PLAYLIST 保留 9 列" \
        "稻香|周杰伦|魔杰座|03:42|185810|flac|http://c.jpg|flac,320|http://u.mp3" "${PLAYLIST[0]}"
    assert_eq "LXMS_PLAYLIST 同步 9 列" \
        "稻香|周杰伦|魔杰座|03:42|185810|flac|http://c.jpg|flac,320|http://u.mp3" "${LXMS_PLAYLIST[0]}"
}

test_add_to_playlist

echo -e "${YELLOW}=== 测试 2: add_search_result 6 列 -> 9 列转换 ===${NC}"

test_add_search_result() {
    PLAYLIST=()
    LXMS_PLAYLIST=()
    eval "$(extract_func add_to_playlist)"
    eval "$(extract_func add_search_result)"

    add_search_result "稻香|周杰伦|魔杰座|03:42|185810|http://c.jpg"
    add_search_result "晴天|周杰伦|叶惠美|04:29|186016|"

    assert_eq "10 列轨道 (含封面+来源)" \
        "稻香|周杰伦|魔杰座|03:42|185810||http://c.jpg|||netease" "${PLAYLIST[0]}"
    assert_eq "10 列轨道 (无封面+来源)" \
        "晴天|周杰伦|叶惠美|04:29|186016|||||netease" "${PLAYLIST[1]}"
    assert_eq "共 2 首" "2" "${#PLAYLIST[@]}"
}

test_add_search_result

echo -e "${YELLOW}=== 测试 3: add_to_playlist 无运行时错误 ===${NC}"

test_no_runtime_error() {
    local err
    err=$(bash -c "
        PLAYLIST=()
        LXMS_PLAYLIST=()
        $(extract_func add_to_playlist)
        add_to_playlist '稻香|周杰伦|魔杰座|03:42|185810|flac|http://c.jpg|flac,320|http://u.mp3'
    " 2>&1)

    assert_not_contains "无 local 标识符错误" "$err" "不是有效的标识符"
    assert_eq "stderr 为空" "" "$err"
}

test_no_runtime_error

echo -e "${YELLOW}=== 测试 4: 危险模式静态扫描 (排除注释) ===${NC}"

test_no_dangerous_pattern() {
    local hits
    hits=$(grep -rn "local .*read -r\|local IFS.*read" \
        --include="*.sh" "$PROJECT_ROOT/lib" \
        "$PROJECT_ROOT/sources" \
        "$PROJECT_ROOT/lx-music-shell" 2>/dev/null \
        | grep -v "references/" \
        | grep -vE ":\s*#" \
        || true)

    assert_eq "项目无 local...read 危险模式" "" "$hits"
}

test_no_dangerous_pattern

echo -e "${YELLOW}=== 测试 5: clear_playlist 同步清空 ===${NC}"

test_clear_playlist() {
    PLAYLIST=("稻香|周杰伦|魔杰座|03:42|185810|flac|http://c.jpg|flac,320|http://u.mp3")
    LXMS_PLAYLIST=("稻香|周杰伦|魔杰座|03:42|185810|flac|http://c.jpg|flac,320|http://u.mp3")

    do_stop() { :; }
    eval "$(extract_func clear_playlist)"
    clear_playlist 2>/dev/null

    assert_eq "PLAYLIST 已清空" "0" "${#PLAYLIST[@]}"
    assert_eq "LXMS_PLAYLIST 已清空" "0" "${#LXMS_PLAYLIST[@]}"
}

test_clear_playlist

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
