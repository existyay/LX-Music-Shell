#!/usr/bin/env bash
#==============================================================================
# LX-Music-Shell 音源管理 (yinyuan) 单元测试
#==============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
YINYUAN_SH="${PROJECT_ROOT}/lib/yinyuan.sh"

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

assert_true() {
    local desc="$1" cond="$2"
    ((TESTS_RUN++))
    if [[ "$cond" == "1" ]]; then
        ((TESTS_PASSED++))
        printf '%b\n' "  ${GREEN}✓${NC} $desc"
    else
        ((TESTS_FAILED++))
        printf '%b\n' "  ${RED}✗${NC} $desc"
    fi
}

if ! command -v python3 >/dev/null 2>&1; then
    echo "  (跳过: python3 未安装)"
    exit 0
fi

# 隔离测试目录
export YINYUAN_DIR="/tmp/lxms-yinyuan-test-$$/yinyuan"
rm -rf "$(dirname "$YINYUAN_DIR")"

# shellcheck disable=SC1091
. "$YINYUAN_SH"

echo -e "${YELLOW}=== 测试 1: 混淆加密往返 ===${NC}"

plain="https://api.example.com/search?kw={{query}}&token=SECRET123&中文=值"
obf=$(yinyuan_obf "$plain")
assert_true "混淆结果非空" "$([[ -n "$obf" ]] && echo 1 || echo 0)"
assert_true "混淆结果 != 原文" "$([[ "$obf" != "$plain" ]] && echo 1 || echo 0)"
assert_eq "解混淆 == 原文" "$plain" "$(yinyuan_deobf "$obf")"

echo -e "${YELLOW}=== 测试 2: add/list/get/remove ===${NC}"

yinyuan_add "test-src" "$plain"
assert_true "add 后存在" "$(yinyuan_exists "test-src" && echo 1 || echo 0)"
assert_eq "get 返回原文" "$plain" "$(yinyuan_get_url "test-src")"

yinyuan_add "src2" "https://x.example.com/{{query}}"
assert_contains() {
    local desc="$1" haystack="$2" needle="$3"
    ((TESTS_RUN++))
    if [[ "$haystack" == *"$needle"* ]]; then
        ((TESTS_PASSED++))
        printf '%b\n' "  ${GREEN}✓${NC} $desc"
    else
        ((TESTS_FAILED++))
        printf '%b\n' "  ${RED}✗${NC} $desc"
    fi
}
assert_contains "list 含 test-src" "$(yinyuan_list)" "test-src"
assert_contains "list 含 src2" "$(yinyuan_list)" "src2"

yinyuan_remove "src2"
assert_true "remove 后不存在" "$(! yinyuan_exists "src2" && echo 1 || echo 0)"

echo -e "${YELLOW}=== 测试 3: 不落盘明文 ===${NC}"

f="$(yinyuan_path "test-src")"
assert_true "文件存在" "$([[ -f "$f" ]] && echo 1 || echo 0)"
assert_true "文件内容不含明文 token" "$(! grep -q "SECRET123" "$f" && echo 1 || echo 0)"
assert_true "文件内容不含明文 http" "$(! grep -q "http" "$f" && echo 1 || echo 0)"

echo -e "${YELLOW}=== 测试 4: GitHub 链接识别 ===${NC}"

assert_true "识别 raw.githubusercontent" "$(yinyuan_is_github_url "https://raw.githubusercontent.com/a/b/main/x.txt" && echo 1 || echo 0)"
assert_true "识别 github.com" "$(yinyuan_is_github_url "https://github.com/a/b" && echo 1 || echo 0)"
assert_true "普通 URL 非 GitHub" "$(! yinyuan_is_github_url "https://api.example.com/search" && echo 1 || echo 0)"

echo -e "${YELLOW}=== 测试 5: 非法名称拒绝 ===${NC}"

yinyuan_add "bad name" "https://x.com" 2>/dev/null
assert_true "带空格名称被拒绝" "$(! yinyuan_exists "bad name" && echo 1 || echo 0)"

#==============================================================================
# 结果
#==============================================================================
echo ""
echo "========================================"
echo "总计: $TESTS_RUN 运行"
echo "通过: $TESTS_PASSED"
echo "失败: $TESTS_FAILED"
echo "========================================"

rm -rf "$(dirname "$YINYUAN_DIR")"
[[ $TESTS_FAILED -eq 0 ]]
