#!/usr/bin/env bash
#==============================================================================
# LX-Music-Shell 输入处理模块
#
# 统一处理键盘和鼠标输入事件,转换为标准事件流。
#
# 事件类型:
#   EVENT_KEY_UP/DOWN/LEFT/RIGHT    - 方向键
#   EVENT_KEY_ENTER                  - 回车
#   EVENT_KEY_TAB                    - Tab 键
#   EVENT_KEY_SPACE                  - 空格
#   EVENT_KEY_QUIT                   - q/Q
#   EVENT_KEY_PAGE_UP/DOWN           - Page Up/Down
#   EVENT_KEY_HOME/END               - Home/End
#   EVENT_KEY_BACKSPACE              - 退格
#   EVENT_KEY_CHAR                   - 其他字符
#   EVENT_MOUSE_CLICK                - 鼠标单击
#   EVENT_MOUSE_DOUBLE               - 鼠标双击
#   EVENT_MOUSE_SCROLL_UP/DOWN       - 滚轮
#   EVENT_MOUSE_RELEASE              - 释放
#   EVENT_NONE                       - 无事件
#==============================================================================

# 防止重复加载
[[ -n "${LXMS_INPUT_LOADED:-}" ]] && return 0
readonly LXMS_INPUT_LOADED=1

#==============================================================================
# 事件类型常量
#==============================================================================
readonly EVENT_NONE=0
readonly EVENT_KEY_UP=1
readonly EVENT_KEY_DOWN=2
readonly EVENT_KEY_LEFT=3
readonly EVENT_KEY_RIGHT=4
readonly EVENT_KEY_ENTER=5
readonly EVENT_KEY_TAB=6
readonly EVENT_KEY_SPACE=7
readonly EVENT_KEY_QUIT=8
readonly EVENT_KEY_PAGE_UP=9
readonly EVENT_KEY_PAGE_DOWN=10
readonly EVENT_KEY_HOME=11
readonly EVENT_KEY_END=12
readonly EVENT_KEY_BACKSPACE=13
readonly EVENT_KEY_CHAR=14
readonly EVENT_KEY_ESC=15

readonly EVENT_MOUSE_CLICK=100
readonly EVENT_MOUSE_DOUBLE=101
readonly EVENT_MOUSE_SCROLL_UP=102
readonly EVENT_MOUSE_SCROLL_DOWN=103
readonly EVENT_MOUSE_RELEASE=104

#==============================================================================
# 内部状态: 已注册的 UI 区域
#==============================================================================
declare -a INPUT_REGIONS=()      # 每个区域一行: "name|row|col|height|width"
INPUT_LAST_CLICK_X=0
INPUT_LAST_CLICK_Y=0
INPUT_LAST_CLICK_TIME=0
INPUT_HIT_REGION=""              # 最近一次命中测试的区域名

#==============================================================================
# 区域注册 - 供 TUI 模块调用
#
# 用法: input_register_region "list" 5 0 20 40
#==============================================================================
input_register_region() {
    local name="$1"
    local row="$2"
    local col="$3"
    local height="$4"
    local width="$5"

    INPUT_REGIONS+=("${name}|${row}|${col}|${height}|${width}")
}

input_clear_regions() {
    INPUT_REGIONS=()
}

#==============================================================================
# 键盘解析
#
# 输入: 一个按键的字节或转义序列
# 输出: "event_type|event_data" 或设置全局变量
#==============================================================================
input_parse_keyboard() {
    local seq="$1"

    # 单字符处理
    case "$seq" in
        $'\n'|$'\r')   EVENT_TYPE=$EVENT_KEY_ENTER; return 0 ;;
        $'\t')         EVENT_TYPE=$EVENT_KEY_TAB; return 0 ;;
        ' ')           EVENT_TYPE=$EVENT_KEY_SPACE; return 0 ;;
        $'\177'|$'\b') EVENT_TYPE=$EVENT_KEY_BACKSPACE; return 0 ;;
        $'\033')       EVENT_TYPE=$EVENT_KEY_ESC; return 0 ;;
    esac

    # ANSI 转义序列 (e.g., \033[A = Up Arrow)
    if [[ "$seq" == $'\033'[A ]]; then
        EVENT_TYPE=$EVENT_KEY_UP
        return 0
    elif [[ "$seq" == $'\033'[B ]]; then
        EVENT_TYPE=$EVENT_KEY_DOWN
        return 0
    elif [[ "$seq" == $'\033'[C ]]; then
        EVENT_TYPE=$EVENT_KEY_RIGHT
        return 0
    elif [[ "$seq" == $'\033'[D ]]; then
        EVENT_TYPE=$EVENT_KEY_LEFT
        return 0
    elif [[ "$seq" == $'\033'[5~ ]] || [[ "$seq" == $'\033'[H ]]; then
        EVENT_TYPE=$EVENT_KEY_PAGE_UP
        return 0
    elif [[ "$seq" == $'\033'[6~ ]] || [[ "$seq" == $'\033'[F ]]; then
        EVENT_TYPE=$EVENT_KEY_PAGE_DOWN
        return 0
    elif [[ "$seq" == $'\033'[1~ ]] || [[ "$seq" == $'\033'[7~ ]] || [[ "$seq" == $'\033'[H ]]; then
        EVENT_TYPE=$EVENT_KEY_HOME
        return 0
    elif [[ "$seq" == $'\033'[4~ ]] || [[ "$seq" == $'\033'[8~ ]] || [[ "$seq" == $'\033'[F ]]; then
        EVENT_TYPE=$EVENT_KEY_END
        return 0
    fi

    # 一般字符
    if [[ -n "$seq" ]]; then
        EVENT_TYPE=$EVENT_KEY_CHAR
        EVENT_DATA="$seq"
        return 0
    fi

    EVENT_TYPE=$EVENT_NONE
    return 1
}

#==============================================================================
# SGR 鼠标协议解析 (\033[<button;x;y;M 或 m)
#
# 格式: CSI < button ; x ; y ; M (按下) 或 m (释放)
# button 编码:
#   0 = 左键, 1 = 中键, 2 = 右键
#   64 = 滚轮上, 65 = 滚轮下
#==============================================================================
input_parse_mouse() {
    local seq="$1"

    # 提取按钮和坐标
    if [[ "$seq" =~ ^$'\033'\[\<([0-9]+)\;([0-9]+)\;([0-9]+)\;([Mm])$ ]]; then
        local button="${BASH_REMATCH[1]}"
        local x="${BASH_REMATCH[2]}"
        local y="${BASH_REMATCH[3]}"
        local action="${BASH_REMATCH[4]}"

        EVENT_DATA_X="$x"
        EVENT_DATA_Y="$y"

        # 滚轮事件 (M 后跟 64/65)
        if [[ "$button" -eq 64 ]]; then
            EVENT_TYPE=$EVENT_MOUSE_SCROLL_UP
            EVENT_DATA=""
            return 0
        elif [[ "$button" -eq 65 ]]; then
            EVENT_TYPE=$EVENT_MOUSE_SCROLL_DOWN
            EVENT_DATA=""
            return 0
        fi

        # 忽略移动/拖拽事件 (SGR 按钮 bit 5 = 32 表示 motion)
        # 避免把拖拽误判为点击
        if (( button & 32 )); then
            EVENT_TYPE=$EVENT_NONE
            EVENT_DATA=""
            return 0
        fi

        # 释放事件
        if [[ "$action" == "m" ]]; then
            EVENT_TYPE=$EVENT_MOUSE_RELEASE
            EVENT_DATA=""
            return 0
        fi

        # 单击/双击 检测
        local now
        now=$(date +%s%3N 2>/dev/null || date +%s)
        local time_diff=$((now - ${INPUT_LAST_CLICK_TIME:-0}))

        # 双击窗口: 500ms 内相同位置
        if [[ "$time_diff" -lt 500 ]] && \
           [[ "$x" == "${INPUT_LAST_CLICK_X:-}" ]] && \
           [[ "$y" == "${INPUT_LAST_CLICK_Y:-}" ]]; then
            EVENT_TYPE=$EVENT_MOUSE_DOUBLE
            EVENT_DATA="${x},${y}"
            INPUT_LAST_CLICK_TIME=0  # 重置,避免三击被认作双击
        else
            EVENT_TYPE=$EVENT_MOUSE_CLICK
            EVENT_DATA="${x},${y}"
            INPUT_LAST_CLICK_X="$x"
            INPUT_LAST_CLICK_Y="$y"
            INPUT_LAST_CLICK_TIME="$now"
            true  # 防止 set -e 误以为这是命令失败
        fi

        return 0
    fi

    EVENT_TYPE=$EVENT_NONE
    return 1
}

#==============================================================================
# 区域命中测试
#
# 输入: 鼠标坐标 (x, y)
# 输出 (全局变量, 避免子 shell 丢失):
#   INPUT_HIT_REGION - 命中的区域名 (未命中 = "")
#   EVENT_DATA       - 区域内坐标 "local_x,local_y"
# 返回: 0 命中, 1 未命中
#==============================================================================
input_mouse_to_action() {
    local x="$1"
    local y="$2"

    INPUT_HIT_REGION=""
    EVENT_DATA=""

    for region in "${INPUT_REGIONS[@]}"; do
        IFS='|' read -r name row col height width <<< "$region"
        local end_row=$((row + height))
        local end_col=$((col + width))

        if [[ "$y" -ge "$row" ]] && [[ "$y" -lt "$end_row" ]] && \
           [[ "$x" -ge "$col" ]] && [[ "$x" -lt "$end_col" ]]; then
            # 找到区域,计算内部坐标
            local local_y=$((y - row))
            local local_x=$((x - col))
            # shellcheck disable=SC2034  # 命中区域供 tui 读取
            INPUT_HIT_REGION="$name"
            EVENT_DATA="${local_x},${local_y}"
            return 0
        fi
    done
    return 1
}

#==============================================================================
# 主事件循环 - 读取一个事件
#
# 输出全局变量:
#   EVENT_TYPE  - 事件类型常量
#   EVENT_DATA  - 事件附加数据 (按事件而异)
#   EVENT_DATA_X, EVENT_DATA_Y - 鼠标事件专用
#==============================================================================
input_read_event() {
    local timeout="${1:-0.1}"

    # shellcheck disable=SC2034  # 事件输出变量供主循环读取
    EVENT_TYPE=$EVENT_NONE
    # shellcheck disable=SC2034
    EVENT_DATA=""
    # shellcheck disable=SC2034
    EVENT_DATA_X=0
    # shellcheck disable=SC2034
    EVENT_DATA_Y=0

    # 读取第一个字节
    local first_byte
    if ! IFS= read -rsn1 -t "$timeout" first_byte 2>/dev/null; then
        return 1
    fi

    # ESC 序列 - 需要继续读取
    if [[ "$first_byte" == $'\033' ]]; then
        local next_byte
        if ! IFS= read -rsn1 -t 0.01 next_byte 2>/dev/null; then
            # 单独的 ESC 键
            input_parse_keyboard "$'\033'"
            return 0
        fi

        if [[ "$next_byte" == "[" ]] || [[ "$next_byte" == "O" ]]; then
            # CSI 或 SS3 序列
            # 尝试读取直到字符或数字结束
            local esc_seq="$first_byte$next_byte"
            local ch
            while IFS= read -rsn1 -t 0.01 ch 2>/dev/null; do
                esc_seq+="$ch"
                # 终止字符
                if [[ "$ch" =~ [A-Za-z~] ]]; then
                    break
                fi
                # 防止无限循环
                if [[ "${#esc_seq}" -gt 15 ]]; then
                    break
                fi
            done

            # 尝试解析为鼠标 (SGR 1006)
            if [[ "$esc_seq" == $'\033'\[* ]]; then
                if input_parse_mouse "$esc_seq"; then
                    return 0
                fi
            fi

            # 否则解析为键盘
            input_parse_keyboard "$esc_seq"
            return 0
        fi

        # ESC + 单字节
        input_parse_keyboard "$first_byte$next_byte"
        return 0
    fi

    # 单字节字符
    input_parse_keyboard "$first_byte"
    return 0
}

#==============================================================================
# 启用/禁用 SGR 鼠标模式
#==============================================================================
_input_write_tty_or_stdout() {
    # 尝试写 /dev/tty (交互终端),失败回退到 stdout (管道环境)
    # 用 %b 解释 \033 转义 (否则会把字面 "\033[?1006h" 打印成可见文本)
    local data="$1"
    if [[ -t 0 ]] && [[ -c /dev/tty ]]; then
        printf '%b' "$data" > /dev/tty 2>/dev/null || printf '%b' "$data"
    else
        printf '%b' "$data"
    fi
}

input_enable_mouse() {
    # 启用 SGR 鼠标模式 + 按钮事件 (按下/释放/拖拽, 不含裸移动)
    _input_write_tty_or_stdout '\033[?1006h\033[?1002h'
}

input_disable_mouse() {
    # 关闭 SGR 鼠标模式
    _input_write_tty_or_stdout '\033[?1006l\033[?1002l'
}

#==============================================================================
# 事件名称 (调试用)
#==============================================================================
input_event_name() {
    case "$1" in
        "$EVENT_NONE")                printf 'NONE' ;;
        "$EVENT_KEY_UP")              printf 'KEY_UP' ;;
        "$EVENT_KEY_DOWN")            printf 'KEY_DOWN' ;;
        "$EVENT_KEY_LEFT")            printf 'KEY_LEFT' ;;
        "$EVENT_KEY_RIGHT")           printf 'KEY_RIGHT' ;;
        "$EVENT_KEY_ENTER")           printf 'KEY_ENTER' ;;
        "$EVENT_KEY_TAB")             printf 'KEY_TAB' ;;
        "$EVENT_KEY_SPACE")           printf 'KEY_SPACE' ;;
        "$EVENT_KEY_QUIT")            printf 'KEY_QUIT' ;;
        "$EVENT_KEY_PAGE_UP")         printf 'KEY_PAGE_UP' ;;
        "$EVENT_KEY_PAGE_DOWN")       printf 'KEY_PAGE_DOWN' ;;
        "$EVENT_KEY_HOME")            printf 'KEY_HOME' ;;
        "$EVENT_KEY_END")             printf 'KEY_END' ;;
        "$EVENT_KEY_BACKSPACE")       printf 'KEY_BACKSPACE' ;;
        "$EVENT_KEY_CHAR")            printf 'KEY_CHAR' ;;
        "$EVENT_KEY_ESC")             printf 'KEY_ESC' ;;
        "$EVENT_MOUSE_CLICK")         printf 'MOUSE_CLICK' ;;
        "$EVENT_MOUSE_DOUBLE")        printf 'MOUSE_DOUBLE' ;;
        "$EVENT_MOUSE_SCROLL_UP")     printf 'MOUSE_SCROLL_UP' ;;
        "$EVENT_MOUSE_SCROLL_DOWN")   printf 'MOUSE_SCROLL_DOWN' ;;
        "$EVENT_MOUSE_RELEASE")       printf 'MOUSE_RELEASE' ;;
        *)                          printf 'UNKNOWN(%s)' "$1" ;;
    esac
}
