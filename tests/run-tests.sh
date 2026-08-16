#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$TEST_DIR/.." && pwd)"

TMPROOT="$(mktemp -d)"
cleanup() {
  rm -rf "$TMPROOT"
}
trap cleanup EXIT

export XDG_CONFIG_HOME="$TMPROOT/.config"
export XDG_CACHE_HOME="$TMPROOT/.cache"
export HOME="$TMPROOT/home"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$HOME"

source "$PROJECT_DIR/lx-music-shell"

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="${3:-}" 
  if [[ "$expected" != "$actual" ]]; then
    echo "FAIL: $message"
    echo "  expected: '$expected'"
    echo "  actual:   '$actual'"
    exit 1
  fi
}

assert_contains() {
  local needle="$1"
  local haystack="$2"
  local message="${3:-}"
  if ! grep -qF "$needle" <<< "$haystack"; then
    echo "FAIL: $message"
    echo "  missing: $needle"
    echo "  output:  "$haystack""
    exit 1
  fi
}

run_test() {
  local name="$1"
  shift
  printf '==== %s ====' "$name"
  if "$@"; then
    echo " PASSED"
  else
    echo " FAILED"
    exit 1
  fi
}

run_bash_syntax() {
  bash -n "$PROJECT_DIR/lx-music-shell"
}

run_load_config() {
  rm -f "$XDG_CONFIG_HOME/lx-music-shell/config"
  load_config
  assert_eq "true" "$AUTO_UPDATE_SOURCES" "AUTO_UPDATE_SOURCES default"
  assert_eq "true" "$UI_COLOR" "UI_COLOR default"
  assert_eq "true" "$AUTO_RECONNECT" "AUTO_RECONNECT default"
}

run_fetch_source_api() {
  fetch_source_api
  local content
  content=$(<"$SOURCES_FILE")
  assert_contains "SOURCE_KUGOU=" "$content" "fetch_source_api should add kugou"
  assert_contains "SOURCE_NETEASE=" "$content" "fetch_source_api should add netease"
}

run_set_source() {
  set_source add custom "https://example.com/search?q={{query}}&limit={{limit}}" >/dev/null 2>&1
  assert_eq "https://example.com/search?q={{query}}&limit={{limit}}" "${SOURCE_URLS[custom]}" "custom source loaded into SOURCE_URLS"
  local output
  output=$(show_sources)
  assert_contains "custom" "$output" "show_sources should list custom source"
}

run_do_search_mock() {
  PLAYLIST=()
  LXMS_PLAYLIST=()
  local output_file
  output_file=$(mktemp)
  do_search "测试" "kugou" 2 >"$output_file" 2>&1
  local output
  output=$(<"$output_file")
  rm -f "$output_file"
  assert_contains "找到" "$output" "do_search should report result count"
  assert_eq "2" "${#PLAYLIST[@]}" "mock search should add two tracks"
}

run_show_panel() {
  local output
  output=$(show_panel 2>&1)
  assert_contains "LX-Music-Shell 面板" "$output" "show_panel output header"
}

run_commands() {
  bash -c "cd '$PROJECT_DIR' && XDG_CONFIG_HOME='$XDG_CONFIG_HOME' XDG_CACHE_HOME='$XDG_CACHE_HOME' bash ./lx-music-shell --search '测试'" >/dev/null 2>&1 || true
}

run_optional_shellcheck() {
  if command -v shellcheck >/dev/null 2>&1; then
    shellcheck -x "$PROJECT_DIR/lx-music-shell" || true
  fi
}

run_test "bash syntax" run_bash_syntax
run_test "load config" run_load_config
run_test "fetch source api" run_fetch_source_api
run_test "set custom source" run_set_source
run_test "mock search" run_do_search_mock
run_test "show panel" run_show_panel
run_test "run command mode" run_commands
run_optional_shellcheck

echo "All tests passed."
