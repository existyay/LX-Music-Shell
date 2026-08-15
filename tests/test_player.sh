#!/usr/bin/env bash
#==============================================================================
# LX-Music-Shell 播放器后端集成测试 (mpv JSON IPC)
#
# 用真实 mpv + 生成的短音频验证:
#   - player_start 启动 mpv 并建立 IPC
#   - player_poll 读取真实进度/时长
#   - player_pause / player_resume / player_seek / player_set_volume
#   - player_stop 清理
#
# 无 mpv/ffmpeg/python3 时优雅跳过 (exit 0)。
#==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

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
    local desc="$1" actual="$2"
    ((TESTS_RUN++))
    if [[ "$actual" == "1" ]]; then
        ((TESTS_PASSED++))
        printf '%b\n' "  ${GREEN}✓${NC} $desc"
    else
        ((TESTS_FAILED++))
        printf '%b\n' "  ${RED}✗${NC} $desc"
    fi
}

# 环境检查
if ! command -v mpv >/dev/null 2>&1; then
    echo "  (跳过: mpv 未安装)"
    exit 0
fi
if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "  (跳过: ffmpeg 未安装)"
    exit 0
fi
if ! command -v python3 >/dev/null 2>&1; then
    echo "  (跳过: python3 未安装)"
    exit 0
fi

TONE="/tmp/lxms-test-tone-$$.wav"
ffmpeg -loglevel error -f lavfi -i "sine=frequency=440:duration=3" -c:a pcm_s16le "$TONE" -y 2>/dev/null || {
    echo "  (跳过: 无法生成测试音频)"
    exit 0
}

cleanup() {
    [[ -n "${PLAYER_PID:-}" ]] && player_stop >/dev/null 2>&1
    rm -f "$TONE"
}
trap cleanup EXIT

# shellcheck disable=SC1091
source "$PROJECT_ROOT/lib/player.sh"
export CACHE_DIR="/tmp/lxms-player-test-$$"
mkdir -p "$CACHE_DIR"

echo -e "${YELLOW}=== 测试 1: player_start ===${NC}"
PLAYER_VOLUME=70
player_start "$TONE" "Test Tone" 2>/dev/null
assert_true "player_start 成功且 PID 非空" "$([[ -n "$PLAYER_PID" ]] && echo 1 || echo 0)"
assert_true "IPC socket 已建立" "$([[ -S "$PLAYER_SOCKET" ]] && echo 1 || echo 0)"

echo -e "${YELLOW}=== 测试 2: player_poll 真实进度 ===${NC}"
sleep 1.2
player_poll
assert_eq "时长 3 秒" "3" "$PLAYBACK_DURATION"
assert_true "进度 > 0" "$([[ $PLAYBACK_POSITION -gt 0 ]] && echo 1 || echo 0)"
assert_eq "状态 playing" "playing" "$PLAYER_STATUS"

echo -e "${YELLOW}=== 测试 3: 暂停/继续 ===${NC}"
player_pause
sleep 0.3
player_poll
assert_eq "暂停后状态 paused" "paused" "$PLAYER_STATUS"
player_resume
sleep 0.3
player_poll
assert_eq "继续后状态 playing" "playing" "$PLAYER_STATUS"

echo -e "${YELLOW}=== 测试 4: seek + 音量 ===${NC}"
player_seek 2.0
sleep 0.3
player_poll
assert_true "seek 后进度 >= 2" "$([[ $PLAYBACK_POSITION -ge 2 ]] && echo 1 || echo 0)"
player_set_volume 40
assert_eq "音量设为 40" "40" "$PLAYER_VOLUME"

echo -e "${YELLOW}=== 测试 5: player_stop ===${NC}"
player_stop
assert_eq "停止后状态 stopped" "stopped" "$PLAYER_STATUS"
assert_eq "停止后 PID 空" "" "$PLAYER_PID"

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
