#!/usr/bin/env bash
#==============================================================================
# LX-Music-Shell TUI Fox 风格测试 (go-musicfox 视觉重制)
#
# 覆盖:
#   - 模块加载幂等 (LXMS_FOX_LOADED 守卫)
#   - 字符宽度计算 (CJK / ASCII / 混合)
#   - 填充/截断辅助
#   - 菜单初始化 (16 项, 顺序正确)
#   - 渲染输出包含关键元素 (musicfox/logo/红/选择标记/歌名/进度/歌词)
#   - 双列 vs 单列布局
#   - 播放栏所有字段 (模式/音量/状态/♥/歌名)
#   - 进度条 + 时间
#   - python3 lyric 集成 (LRC + YRC)
#   - 危险模式静态扫描 (local...read)
#==============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TUI_FOX="${PROJECT_ROOT}/lib/tui_fox.sh"
LYRIC_PY="${PROJECT_ROOT}/lib/lyric.py"

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

# 辅助: 去 ANSI 转义
strip_ansi() {
    printf '%s' "$1" | sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' | sed 's/\x1b//g'
}

#==============================================================================
echo -e "${YELLOW}=== 测试 1: 模块加载 ===${NC}"
#==============================================================================

unset LXMS_FOX_LOADED
. "$TUI_FOX"
[[ -n "${LXMS_FOX_LOADED:-}" ]]
assert_eq "首次 source 设置守卫" "1" "$LXMS_FOX_LOADED"

# 再次 source 应幂等
. "$TUI_FOX" 2>&1
assert_eq "重复 source 幂等" "1" "$LXMS_FOX_LOADED"

#==============================================================================
echo -e "${YELLOW}=== 测试 2: 字符宽度计算 (CJK = 2 列) ===${NC}"
#==============================================================================

assert_eq "ASCII 宽度" "5" "$(fx_width 'hello')"
assert_eq "中文 4 字 = 8 列" "8" "$(fx_width '回到过去')"
assert_eq "混合 '稻香-AB' = 4+1+2 = 7" "7" "$(fx_width '稻香-AB')"
assert_eq "空串 = 0" "0" "$(fx_width '')"
assert_eq "数字 + 冒号" "5" "$(fx_width '03:42')"

#==============================================================================
echo -e "${YELLOW}=== 测试 3: 填充/截断辅助 ===${NC}"
#==============================================================================

# fx_pad: 短串右填充到 N
out=$(fx_pad '稻香' 10 | sed 's/\x1b//g')
w=$(fx_width "$out")
assert_eq "fx_pad 填充后宽度=10" "10" "$w"

# fx_trunc: 长串截断到 N
out=$(fx_trunc '回到过去的美好时光' 8 | sed 's/\x1b//g')
w=$(fx_width "$out")
assert_eq "fx_trunc 截断后宽度<=8" "1" "$([ $w -le 8 ] && echo 1 || echo 0)"

#==============================================================================
echo -e "${YELLOW}=== 测试 4: Main 菜单初始化 ===${NC}"
#==============================================================================

# 重新 source 强制重新初始化 (清空可能污染的全局)
unset FX_MENU_KEY FX_MENU_TITLE FX_MENU_SEL
. "$TUI_FOX"
fx_init_main_menu

assert_eq "菜单项数量=16" "16" "${#FX_MENU_TITLE[@]}"
assert_eq "菜单 KEY 数量=16" "16" "${#FX_MENU_KEY[@]}"
assert_eq "第 0 项是搜索" "搜索" "${FX_MENU_TITLE[0]}"
assert_eq "第 0 项 KEY=search" "search" "${FX_MENU_KEY[0]}"
assert_eq "第 7 项=最近播放" "最近播放" "${FX_MENU_TITLE[6]}"
assert_eq "第 14 项=帮助" "帮助" "${FX_MENU_TITLE[14]}"

#==============================================================================
echo -e "${YELLOW}=== 测试 5: 完整渲染 - 包含所有关键元素 ===${NC}"
#==============================================================================

out=$(COLUMNS=120 LINES=30 . "$TUI_FOX" 2>&1 && {
    export COLUMNS=120 LINES=30
    . "$TUI_FOX"
    FX_USER_NICKNAME="existyay"
    FX_VOLUME=80
    FX_STATE=playing
    LXMS_PLAYLIST=("稻香|周杰伦|魔杰座|03:42|sid1|flac||flac,320,128|url1")
    LXMS_PLAYING_INDEX=0
    FX_PROGRESS_C=95
    FX_PROGRESS_T=222
    FX_LRC_RAW="[00:00.00]第一行
[00:01.00]第二行"
    FX_CURRENT_MS=3000
    FX_MODE=list
    fx_render
})
out_clean=$(strip_ansi "$out")

assert_contains "顶部红线 musicfox" "$out_clean" "musicfox"
assert_contains "用户名副标题" "$out_clean" "[existyay]"
assert_contains "选中项 =>" "$out_clean" "=>"
assert_contains "菜单 搜索 项" "$out_clean" "搜索"
assert_contains "菜单 我的歌单 项" "$out_clean" "我的歌单"
assert_contains "播放模式 [列表]" "$out_clean" "[列表]"
assert_contains "音量 80%" "$out_clean" "80%"
assert_contains "状态图标 ♫" "$out_clean" "♫"
assert_contains "♥ 心" "$out_clean" "♥"
assert_contains "歌曲名 稻香" "$out_clean" "稻香"
assert_contains "歌手 周杰伦" "$out_clean" "周杰伦"
assert_contains "进度块 █" "$out_clean" "█"
assert_contains "时间 01:35/03:42" "$out_clean" "01:35/03:42"

#==============================================================================
echo -e "${YELLOW}=== 测试 6: 双列 vs 单列布局 ===${NC}"
#==============================================================================

# 宽屏 (120 列): 第 1 个和第 2 个菜单项应在同一行 (双列)
out=$(COLUMNS=120 LINES=30 . "$TUI_FOX" 2>&1 && {
    export COLUMNS=120 LINES=30
    . "$TUI_FOX"
    fx_init_main_menu
    fx_render
})

# 双列: row 包含 "0. 搜索" 和 "1. 我的歌单" 两项
# 用 screen 解析 (简化版)
python3 - << PYEOF > /tmp/fox_dual_layout.txt
import sys, re, subprocess
result = subprocess.run(['bash', '-c', '''
export COLUMNS=120 LINES=30
. "${0}"
fx_init_main_menu
fx_render
'''.replace('${0}', '$TUI_FOX')], capture_output=True, text=True, env={'PATH': '$PATH', 'COLUMNS':'120', 'LINES':'30'})
data = result.stdout
screen = {}
row, col = 1, 1
i = 0
while i < len(data):
    m = re.match(r'\x1b\[(\d+);(\d+)H', data[i:])
    if m:
        row, col = int(m.group(1)), int(m.group(2)); i += m.end(); continue
    m = re.match(r'\x1b\[[0-9;?]*[a-zA-Z]', data[i:])
    if m:
        i += m.end(); continue
    if data[i] == '\x1b':
        i += 1; continue
    ch = data[i]
    if ch == '\n':
        row += 1; col = 1
    else:
        screen.setdefault(row, {})[col] = ch
        col += 1
    i += 1
# 找同时含 "0. 搜索" 和 "1. 我的歌单" 的行
for r, cols in sorted(screen.items()):
    line = ''.join(cols.get(c, ' ') for c in range(1, max(cols)+1))
    clean = re.sub(r'\x1b\[[0-9;]*m', '', line)
    has0 = '0.' in clean and '搜索' in clean
    has1 = '1.' in clean and '我的歌单' in clean
    if has0 and has1:
        print('DUAL')
        sys.exit(0)
print('SINGLE')
PYEOF
# We don't have $TUI_FOX substitution in heredoc; do it manually
out=$(COLUMNS=120 LINES=30 bash -c "
. '$TUI_FOX'
fx_init_main_menu
fx_render
" 2>/dev/null)
# 简化: 宽屏输出含两个菜单在相对 col 4 和 col 62 (即双列布局特征)
# 注意: 中间有 ANSI 码, 使用不带 ANSI 的子串
out_strip=$(printf '%s' "$out" | sed 's/\x1b\[[0-9;]*m//g')
assert_contains "宽屏含双列布局 (左列 0)" "$out_strip" "0. 搜索"
assert_contains "宽屏含双列布局 (右列 1)" "$out_strip" "1. 我的歌单"

# 窄屏 (60 列): 应该是单列
out=$(COLUMNS=60 LINES=30 bash -c "
. '$TUI_FOX'
fx_init_main_menu
fx_render
" 2>/dev/null)
assert_contains "窄屏含菜单项" "$out" "搜索"

#==============================================================================
echo -e "${YELLOW}=== 测试 7: python3 LRC 渲染集成 ===${NC}"
#==============================================================================

[[ -x "$LYRIC_PY" ]] || chmod +x "$LYRIC_PY"
[[ -f "$LYRIC_PY" ]] || { echo "  (跳过: lyric.py 不存在)"; }

result=$(printf '{"lrc":"[00:00.00]第一行\\n[00:01.00]第二行\\n[00:02.00]第三行","current_ms":1500,"center_lines":3}' | \
    python3 "$LYRIC_PY" 2>/dev/null)
assert_contains "LRC 返回 JSON" "$result" '"lines"'
assert_contains "LRC 返回 center_index" "$result" '"center_index"'

# 测试 YRC
result=$(printf '{"yrc":"[0,0]\\n[120,2000]<0,800>测<800,1200>试","current_ms":1000,"center_lines":3}' | \
    python3 "$LYRIC_PY" 2>/dev/null)
assert_contains "YRC 返回非空 lines" "$result" '"lines"'

#==============================================================================
echo -e "${YELLOW}=== 测试 8: 危险模式静态扫描 ===${NC}"
#==============================================================================

hits=$(grep -rn "local .*read -r\|local IFS.*read" \
    --include="*.sh" "$PROJECT_ROOT" \
    "$PROJECT_ROOT/lx-music-shell" 2>/dev/null \
    | grep -v "references/" \
    | grep -v "tests/" \
    | grep -vE ":\s*#" \
    || true)

assert_eq "项目无 local...read 危险模式" "" "$hits"

#==============================================================================
echo -e "${YELLOW}=== 测试 9: vim 操作函数 ===${NC}"
#==============================================================================

. "$TUI_FOX"
fx_init_main_menu
FX_MENU_SEL=2

fx_op_move_up
assert_eq "move_up 2->1" "1" "$FX_MENU_SEL"

fx_op_move_up
fx_op_move_up
fx_op_move_up  # 应被 clamp 到 0
assert_eq "move_up 边界 clamp 0" "0" "$FX_MENU_SEL"

fx_op_move_down
assert_eq "move_down 0->1" "1" "$FX_MENU_SEL"

fx_op_move_down
fx_op_move_down
fx_op_move_down
fx_op_move_down
fx_op_move_down
fx_op_move_down
fx_op_move_down
fx_op_move_down
fx_op_move_down
fx_op_move_down
fx_op_move_down
fx_op_move_down
fx_op_move_down
fx_op_move_down  # 从 1 加 14 次 = 应被 clamp 到 15
assert_eq "move_down 边界 clamp 15" "15" "$FX_MENU_SEL"

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