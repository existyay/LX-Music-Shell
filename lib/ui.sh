#!/usr/bin/env bash
# UI helpers for LX-Music-Shell
# Provides a minimal, consistent TUI interface that other modules can call.

# Hide/show cursor
hide_cursor() { printf '\e[?25l'; }
show_cursor() { printf '\e[?25h'; }

# Save/restore screen
ui_save() { printf '\e7'; }
ui_restore() { printf '\e8'; }

# Enable/disable mouse reporting (xterm-style)
ui_enable_mouse() { printf '\e[?1000h\e[?1002h\e[?1006h'; }
ui_disable_mouse() { printf '\e[?1000l\e[?1002l\e[?1006l'; }

# Clear screen and draw a simple header/footer
ui_clear() { printf '\033[2J\033[H'; }
ui_draw_header() {
    local title="${1:-LX-Music-Shell}"
    local cols
    cols=$(tput cols 2>/dev/null || echo 80)
    local bar
    bar=$(printf '%*s' "$cols" '' | tr ' ' '─')
    printf '%b\n' "${CYAN}${bar}${NC}"
    printf '%b\n' "${BOLD}${title}${NC}"
    printf '%b\n' "${CYAN}${bar}${NC}"
}

ui_draw_footer() {
    local hint="$1"
    printf '%b\n' "\n${GRAY}${hint}${NC}"
}

# Simple spinner (non-blocking caller should sleep)
ui_spinner_frame() {
    local frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    local i=${1:-0}
    printf '%b' "${frames[$((i % ${#frames[@]}))]}"
}

# Progress bar: caller should compute percent and call
ui_progress_bar() {
    local percent=${1:-0}
    local width=${2:-30}
    local filled=$((percent * width / 100))
    local rem=$((width - filled))
    printf '%b' "${GREEN}["
    printf '%*s' "$filled" '' | tr ' ' '█'
    printf '%*s' "$rem" '' | tr ' ' '░'
    printf '%b' "] ${NC}%3d%%" "$percent"
}

# Page template helper: draw centered box of lines
ui_draw_box() {
    local -n lines=$1
    local cols
    cols=$(tput cols 2>/dev/null || echo 80)
    for line in "${lines[@]}"; do
        local padding=$(( (cols - ${#line}) / 2 ))
        printf '%*s%b%*s\n' "$padding" '' "${line}" "$padding" ''
    done
}

# Minimal cleanup to restore terminal state
ui_cleanup() {
    ui_disable_mouse 2>/dev/null || true
    show_cursor 2>/dev/null || true
    stty sane 2>/dev/null || true
}

# Exported API list (for discovery)
_ui_functions=(hide_cursor show_cursor ui_save ui_restore ui_enable_mouse ui_disable_mouse ui_clear ui_draw_header ui_draw_footer ui_spinner_frame ui_progress_bar ui_draw_box ui_cleanup)

# shellcheck disable=SC2034
UI_LIB_LOADED=1
