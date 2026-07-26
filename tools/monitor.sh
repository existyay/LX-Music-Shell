#!/usr/bin/env bash
# Simple runtime monitor for lx-music-shell
# Usage: sudo ./tools/monitor.sh /path/to/lx-music-shell [args...]

set -euo pipefail

BIN="$1"
shift || true
OUTDIR="/tmp/lx-monitor-$(date +%s)"
mkdir -p "$OUTDIR"

echo "Monitoring run, logs -> $OUTDIR"

# Start program in background
"$BIN" "$@" &
PID=$!

echo "pid=$PID" > "$OUTDIR/pid.txt"

# Collect samples until process exits
while kill -0 "$PID" 2>/dev/null; do
    ts=$(date +%s)
    ps -p "$PID" -o pid,ppid,cmd,%mem,%cpu,vsz,rss > "$OUTDIR/ps.$ts.log" 2>/dev/null || true
    pidstat -p "$PID" 1 1 > "$OUTDIR/pidstat.$ts.log" 2>/dev/null || true
    vmstat 1 2 > "$OUTDIR/vmstat.$ts.log" 2>/dev/null || true
    sleep 2
done

wait "$PID" 2>/dev/null || true

echo "Process finished" > "$OUTDIR/status.txt"

echo "Logs stored in $OUTDIR"
