#!/usr/bin/env bash
#==============================================================================
# LX-Music-Shell 终端能力检测模块
#
# 探测当前终端的能力并提供统一接口供其他模块使用。
# 检测完成后,以下变量被设置:
#   LXMS_TERM_IMAGES    - 图片协议: kitty|iTerm|sixel|none
#   LXMS_TERM_MOUSE     - 鼠标支持: 1|0
#   LXMS_TERM_UNICODE   - Unicode 支持: 1|0
#   LXMS_TERM_TRUECOLOR - 24位真彩色: 1|0
#   LXMS_TERM_COLS      - 终端列数
#   LXMS_TERM_LINES     - 终端行数
#   LXMS_FORCE_TUI      - 强制 TUI: 1|0
#
# 配置覆盖 (在 $LXMS_CONFIG_FILE 中):
#   UI_TUI=auto|on|off
#   UI_MOUSE=auto|on|off
#==============================================================================

# 防止重复加载
[[ -n "${LXMS_CAPABILITY_LOADED:-}" ]] && return 0
readonly LXMS_CAPABILITY_LOADED=1

#==============================================================================
# 内部辅助函数
#==============================================================================

# 安全读取值 (避免 set -u 错误)
_cap_safe_read() {
    local var_name="$1"
    local default="${2:-}"
    local val
    # shellcheck disable=SC2016  # 这是字面变量名
    val=$(eval "printf '%s' \"\${$var_name:-}\"")
    if [[ -z "$val" ]]; then
        printf '%s' "$default"
    else
        printf '%s' "$val"
    fi
}

# 检测变量是否匹配模式
_cap_match() {
    local var_name="$1"
    local pattern="$2"
    local val
    val=$(_cap_safe_read "$var_name")
    [[ "$val" == *"$pattern"* ]]
}

#==============================================================================
# 核心: detect_capability
#==============================================================================
detect_capability() {
    # ----- 图片协议检测 -----
    LXMS_TERM_IMAGES="none"

    # kitty: 终端标识是 xterm-kitty 或 kitty
    if _cap_match TERM "kitty" || _cap_match TERM "xterm-kitty"; then
        LXMS_TERM_IMAGES="kitty"
    elif _cap_match TERM_PROGRAM "iTerm" || _cap_match TERM_PROGRAM "WezTerm"; then
        # iTerm2 或 WezTerm 支持内联图片
        LXMS_TERM_IMAGES="iTerm"
    else
        # sixel 检测 - 通过查询设备属性 (DA1)
        # 现代支持 sixel 的终端响应包含 '4' (表明支持 sixel)
        if _cap_match TERM "xterm-256color" && _cap_query_sixel; then
            LXMS_TERM_IMAGES="sixel"
        fi
    fi

    # ----- 鼠标支持检测 -----
    LXMS_TERM_MOUSE=0
    # 多数现代终端 (xterm/kitty/iTerm/alacritty) 默认支持 SGR 1006
    # 通过 DECRQM 查询 (CSI ? 1006 $ p)
    local mouse_resp
    mouse_resp=$(_cap_query_mouse)
    if [[ "$mouse_resp" == *"1"* ]] || _cap_match TERM "xterm" || _cap_match TERM "st-"; then
        LXMS_TERM_MOUSE=1
    fi

    # ----- Unicode 检测 -----
    LXMS_TERM_UNICODE=0
    if _cap_match LC_ALL "UTF-8" || _cap_match LANG "UTF-8" || _cap_match LC_CTYPE "UTF-8"; then
        LXMS_TERM_UNICODE=1
    fi

    # ----- 真彩色检测 -----
    LXMS_TERM_TRUECOLOR=0
    if _cap_match COLORTERM "truecolor" || _cap_match COLORTERM "24bit"; then
        LXMS_TERM_TRUECOLOR=1
    elif _cap_match TERM "truecolor" || _cap_match TERM "-256color"; then
        # 256 色默认非真彩,但可作为兜底信号
        # 仅在显式标记为 24bit 时开启
        :
    fi

    # ----- 终端尺寸 -----
    LXMS_TERM_COLS=$(get_cols)
    LXMS_TERM_LINES=$(get_lines)

    # ----- 强制覆盖 (从配置) -----
    LXMS_FORCE_TUI=0
    local ui_tui
    ui_tui=$(_cap_safe_read LXMS_UI_TUI_OVERRIDE)
    case "$ui_tui" in
        on|true|1|yes)
            LXMS_FORCE_TUI=1
            ;;
        off|false|0|no)
            LXMS_FORCE_TUI=0
            ;;
        *)
            # auto - 根据终端能力默认决策
            if [[ "$LXMS_TERM_COLS" -ge 60 ]] && [[ "$LXMS_TERM_LINES" -ge 20 ]]; then
                LXMS_FORCE_TUI=1
            fi
            ;;
    esac

    # 鼠标覆盖
    local ui_mouse
    ui_mouse=$(_cap_safe_read LXMS_UI_MOUSE_OVERRIDE)
    case "$ui_mouse" in
        on|true|1|yes)
            LXMS_TERM_MOUSE=1
            ;;
        off|false|0|no)
            LXMS_TERM_MOUSE=0
            ;;
        *)
            # auto - 保持自动检测结果
            ;;
    esac
}

#==============================================================================
# 内部探测 (不期望所有终端都响应)
#==============================================================================

# sixel 查询 - 发送 DA1 (Primary Device Attributes)
_cap_query_sixel() {
    # 真正查询会写 tty; 这里用启发式检测
    # st, mlterm, foot 等列在已知支持列表
    case "${TERM:-}" in
        st-*|foot-*|contour-*|xterm-256color)
            # 多数现代终端支持,但需要终端响应 DCS 字符串
            # 由于运行环境多为非交互,保守返回 1
            return 1
            ;;
        *)
            return 1
            ;;
    esac
}

# 鼠标查询
_cap_query_mouse() {
    # 类似地,这里是启发式探测
    case "${TERM:-}" in
        xterm*|st-*|alacritty|kitty|*kitty)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

#==============================================================================
# 查询函数 (供其他模块调用)
#==============================================================================

get_cols() {
    local cols
    cols=$(tput cols 2>/dev/null || true)
    if [[ -z "$cols" ]]; then
        cols="${COLUMNS:-80}"
    fi
    if [[ -z "$cols" ]] || [[ "$cols" -lt 1 ]]; then
        cols=80
    fi
    printf '%d' "$cols"
}

get_lines() {
    local lines
    lines=$(tput lines 2>/dev/null || true)
    if [[ -z "$lines" ]]; then
        lines="${LINES:-24}"
    fi
    if [[ -z "$lines" ]] || [[ "$lines" -lt 1 ]]; then
        lines=24
    fi
    printf '%d' "$lines"
}

supports_images() {
    [[ "${LXMS_TERM_IMAGES:-none}" != "none" ]]
}

supports_mouse() {
    [[ "${LXMS_TERM_MOUSE:-0}" == "1" ]]
}

supports_unicode() {
    [[ "${LXMS_TERM_UNICODE:-0}" == "1" ]]
}

supports_truecolor() {
    [[ "${LXMS_TERM_TRUECOLOR:-0}" == "1" ]]
}

#==============================================================================
# 应用配置覆盖 - 由主脚本调用
#
# 用法: capability_apply_config "$CONFIG_FILE"
#==============================================================================
capability_apply_config() {
    local config_file="${1:-}"

    if [[ -z "$config_file" ]] || [[ ! -f "$config_file" ]]; then
        return 0
    fi

    # 只提取我们关心的变量 (避免 source 整个配置的安全风险)
    local line key value
    while IFS= read -r line; do
        # 跳过注释和空行
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$line" ]] && continue

        if [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            # 移除首尾引号
            value="${value#\"}"
            value="${value%\"}"
            value="${value#\'}"
            value="${value%\'}"

            case "$key" in
                UI_TUI)
                    # shellcheck disable=SC2034  # 通过 _cap_safe_read eval 读取
                    LXMS_UI_TUI_OVERRIDE="$value"
                    ;;
                UI_MOUSE)
                    # shellcheck disable=SC2034
                    LXMS_UI_MOUSE_OVERRIDE="$value"
                    ;;
            esac
        fi
    done < "$config_file"
}

#==============================================================================
# 自检: 打印当前能力
#==============================================================================
capability_print_status() {
    printf '终端能力:\n'
    printf '  图片协议: %s\n' "${LXMS_TERM_IMAGES:-none}"
    printf '  鼠标支持: %s\n' "${LXMS_TERM_MOUSE:-0}"
    printf '  Unicode:  %s\n' "${LXMS_TERM_UNICODE:-0}"
    printf '  真彩色:   %s\n' "${LXMS_TERM_TRUECOLOR:-0}"
    printf '  尺寸:     %sx%s\n' "${LXMS_TERM_COLS:-?}" "${LXMS_TERM_LINES:-?}"
    printf '  强制TUI:  %s\n' "${LXMS_FORCE_TUI:-0}"
}
