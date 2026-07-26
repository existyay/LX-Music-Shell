#!/usr/bin/env bash
#==============================================================================
# LX-Music-Shell 源回退框架单元测试
#==============================================================================

# 注意: bash 4.x 关联数组在 set -u 下有 bug,不启用
# set -u

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$TEST_DIR")"
LIB_DIR="$PROJECT_DIR/lib"
SOURCES_DIR="$PROJECT_DIR/sources"

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
    fi
}

load_sources() {
    unset SOURCE_BASE_LOADED LXMS_SOURCE_BASE_LOADED 2>/dev/null || true
    # shellcheck disable=SC1091
    . "$SOURCES_DIR/_base.sh"
}

#==============================================================================
# 测试 1: 音质链计算
#==============================================================================
test_quality_chain() {
    printf '\n%b\n' "${YELLOW}=== 测试 1: 音质链计算 ===${NC}"

    load_sources
    SOURCE_BASE_QUALITY_MODE="highest"
    source_base_compute_chain
    assert_eq "highest 模式" "hires flac 320 128" "$source_base_quality_chain"

    SOURCE_BASE_QUALITY_MODE="balanced"
    source_base_compute_chain
    assert_eq "balanced 模式" "flac 320 128" "$source_base_quality_chain"

    SOURCE_BASE_QUALITY_MODE="fast"
    source_base_compute_chain
    assert_eq "fast 模式" "320 128" "$source_base_quality_chain"
}

#==============================================================================
# 测试 2: DEFAULT_QUALITY 移到链首
#==============================================================================
test_default_quality_priority() {
    printf '\n%b\n' "${YELLOW}=== 测试 2: DEFAULT_QUALITY 优先级 ===${NC}"

    load_sources
    SOURCE_BASE_QUALITY_MODE="highest"
    SOURCE_BASE_DEFAULT_QUALITY="320"
    source_base_compute_chain

    # "320" 应该在第一位
    local first
    first=$(printf '%s' "$source_base_quality_chain" | awk '{print $1}')
    assert_eq "DEFAULT_QUALITY=320 应在链首" "320" "$first"
}

#==============================================================================
# 测试 3: 音质标签
#==============================================================================
test_quality_label() {
    printf '\n%b\n' "${YELLOW}=== 测试 3: 音质标签 ===${NC}"

    load_sources

    assert_eq "HiRes 标签" "HiRes" "$(quality_label hires)"
    assert_eq "FLAC 标签" "FLAC" "$(quality_label flac)"
    assert_eq "320 → HQ" "HQ" "$(quality_label 320)"
    assert_eq "128 → SQ" "SQ" "$(quality_label 128)"
    assert_eq "unknown → ---" "---" "$(quality_label xyz)"
}

#==============================================================================
# 测试 4: 源注册
#==============================================================================
test_source_registration() {
    printf '\n%b\n' "${YELLOW}=== 测试 4: 源注册 ===${NC}"

    load_sources

    # Mock 一个源函数
    mock_search() {
        printf '1|Test Song|Test Artist|03:00|test_id\n'
    }
    mock_url() {
        local sid="$1"
        local q="$2"
        if [[ "$q" == "flac" ]]; then
            printf 'http://test.com/song.flac'
        elif [[ "$q" == "320" ]]; then
            printf 'http://test.com/song.mp3'
        else
            return 1
        fi
    }

    source_base_register "testsrc" "mock_search" "mock_url" "" "Test Source"

    # 通过 source_base_list 输出来验证注册成功
    local list_output
    list_output=$(source_base_list)
    assert_contains "源列表包含显示名" "$list_output" "Test Source"
    assert_contains "源列表包含 id" "$list_output" "testsrc"

}

#==============================================================================
# 测试 5: 音质保底回退
#==============================================================================
test_quality_fallback() {
    printf '\n%b\n' "${YELLOW}=== 测试 5: 音质保底回退 ===${NC}"

    load_sources

    # Mock: 只有 flac 和 320 可用,hires 失败
    mock_search() { printf '1|Song|Artist|03:00|sid1\n'; }
    mock_url_partial() {
        local sid="$1"
        local q="$2"
        case "$q" in
            flac) printf 'http://test.com/flac' ;;
            320)  printf 'http://test.com/mp3' ;;
            *)    return 1 ;;
        esac
    }


    source_base_register "partial" "mock_search" "mock_url_partial" "" "Partial"


    SOURCE_BASE_QUALITY_MODE="highest"
    SOURCE_BASE_DEFAULT_QUALITY="hires"
    source_base_compute_chain

    # 尝试 hires - 应该回退到 flac
    local result
    result=$(source_base_get_play_url "partial" "sid1" "hires")
    assert_eq "hires 不可用时应回退到 flac" \
        "flac:http://test.com/flac" "$result"
}

#==============================================================================
# 测试 6: 全部失败时返回 1
#==============================================================================
test_all_quality_fail() {
    printf '\n%b\n' "${YELLOW}=== 测试 6: 全部失败返回 1 ===${NC}"

    load_sources

    mock_search() { printf '1|Song|Artist|03:00|sid1\n'; }
    mock_url_fail() {
        return 1
    }


    source_base_register "broken" "mock_search" "mock_url_fail" "" "Broken"


    SOURCE_BASE_QUALITY_MODE="highest"
    source_base_compute_chain

    if source_base_get_play_url "broken" "sid1"; then
        assert_eq "所有音质都失败时应返回 1" "1" "0"
    else
        assert_eq "所有音质都失败时应返回 1" "1" "1"
    fi
}

#==============================================================================
# 主流程
#==============================================================================
main() {
    test_quality_chain
    test_default_quality_priority
    test_quality_label
    test_source_registration
    test_quality_fallback
    test_all_quality_fail

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
