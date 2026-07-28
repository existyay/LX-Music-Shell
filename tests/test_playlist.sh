#!/usr/bin/env bash
#==============================================================================
# LX-Music-Shell 播放列表同步回归测试
#
# 回归背景 (v2.2.0 → v2.2.1):
#   add_to_playlist 曾写成 `local IFS='|' read -r ... <<< "$track"`,
#   local 把 read/-r 当作变量名声明, read 从未执行, LXMS_PLAYLIST 同步为空字段.
#   运行时错误: "local: "-r": 不是有效的标识符"
#
# 本测试从 lx-music-shell 提取函数实体并在隔离环境验证, 防止同类回归.
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

#==============================================================================
# 从主脚本提取函数实体 (避免 source 全文件的副作用)
#==============================================================================
extract_func() {
    local fname="$1"
    sed -n "/^${fname}()/,/^}/p" "$MAIN_SCRIPT"
}

echo -e "${YELLOW}=== 测试 1: add_to_playlist 字段同步 ===${NC}"

test_add_to_playlist_sync() {
    PLAYLIST=()
    LXMS_PLAYLIST=()

    eval "$(extract_func add_to_playlist)"

    add_to_playlist "0|稻香|周杰伦|03:42|sid001"
    add_to_playlist "1|晴天|周杰伦|04:29|sid002"

    assert_eq "PLAYLIST 原始条目保留" \
        "0|稻香|周杰伦|03:42|sid001" "${PLAYLIST[0]}"

    assert_eq "LXMS_PLAYLIST[0] 9 列格式" \
        "稻香|周杰伦||03:42|sid001||||" "${LXMS_PLAYLIST[0]}"

    assert_eq "LXMS_PLAYLIST[1] 9 列格式" \
        "晴天|周杰伦||04:29|sid002||||" "${LXMS_PLAYLIST[1]}"

    # 字段非空 (回归核心: read 必须真的执行)
    local name artist duration
    IFS='|' read -r name artist _ duration _ <<< "${LXMS_PLAYLIST[0]}"
    assert_eq "name 字段非空" "稻香" "$name"
    assert_eq "artist 字段非空" "周杰伦" "$artist"
    assert_eq "duration 字段非空" "03:42" "$duration"
}

test_add_to_playlist_sync

echo -e "${YELLOW}=== 测试 2: add_to_playlist 无运行时错误 ===${NC}"

test_no_runtime_error() {
    local err
    err=$(bash -c "
        PLAYLIST=()
        LXMS_PLAYLIST=()
        $(extract_func add_to_playlist)
        add_to_playlist '0|稻香|周杰伦|03:42|sid001'
    " 2>&1)

    assert_not_contains "无 local 标识符错误" "$err" "不是有效的标识符"
    assert_not_contains "无 read 错误" "$err" "read:"
    assert_eq "stderr 为空" "" "$err"
}

test_no_runtime_error

echo -e "${YELLOW}=== 测试 3: 危险模式静态扫描 ===${NC}"

test_no_dangerous_pattern() {
    # 扫描整个项目: local 与 read 不能出现在同一声明里
    local hits
    hits=$(grep -rn "local .*read -r\|local IFS.*read" \
        --include="*.sh" "$PROJECT_ROOT" \
        "$PROJECT_ROOT/lx-music-shell" 2>/dev/null \
        | grep -v "references/" \
        | grep -v "tests/test_playlist.sh" \
        | grep -v "不能写成" \
        || true)

    assert_eq "项目无 local...read 危险模式" "" "$hits"
}

test_no_dangerous_pattern

echo -e "${YELLOW}=== 测试 4: clear_playlist 同步清空 ===${NC}"

test_clear_playlist() {
    if ! grep -q "^clear_playlist()" "$MAIN_SCRIPT"; then
        echo "  (跳过: clear_playlist 不存在)"
        return
    fi

    PLAYLIST=("0|稻香|周杰伦|03:42|sid001")
    LXMS_PLAYLIST=("稻香|周杰伦||03:42|sid001||||")

    do_stop() { :; }  # 桩: clear_playlist 依赖主脚本的 do_stop
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
