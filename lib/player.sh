#!/usr/bin/env bash
#==============================================================================
# LX-Music-Shell 播放器后端 (mpv JSON IPC)
#
# 用 mpv --input-ipc-server 实现真实控制:
#   - 真实进度/总时长 (time-pos / duration)
#   - 真实暂停/继续 (pause 属性)
#   - seek (绝对/相对)
#   - 音量 (volume 属性)
#   - 曲目结束检测 (eof-reached)
#
# 相比 v2.x 的 kill -STOP/-CONT + 墙钟计时, 本模块:
#   1. 不再猜测进度 (直接读 mpv)
#   2. 不再猜测结束 (读 eof-reached)
#   3. 支持拖进度条 seek
#   4. 支持播放器未安装/启动失败时优雅降级
#
# 依赖: lib/mpv_ipc.py (纯 python3, 无 socat/nc)
#
# 全局变量 (由本模块维护):
#   PLAYER_PID       - mpv 进程 PID (空=未运行)
#   PLAYER_SOCKET    - IPC socket 路径
#   PLAYBACK_POSITION- 当前进度 (秒, 整数)
#   PLAYBACK_DURATION- 总时长 (秒, 整数)
#   PLAYER_STATUS    - playing|paused|stopped|buffering
#   PLAYER_EOF       - 1 表示已播完
#==============================================================================

[[ -n "${LXMS_PLAYER_LOADED:-}" ]] && return 0
readonly LXMS_PLAYER_LOADED=1

# mpv_ipc.py 路径 (自动定位)
if [[ -z "${LXMS_MPV_IPC:-}" ]]; then
    _player_self_dir="${BASH_SOURCE[0]%/*}"
    if [[ -f "$_player_self_dir/mpv_ipc.py" ]]; then
        LXMS_MPV_IPC="$_player_self_dir/mpv_ipc.py"
    fi
fi
# MPRIS D-Bus 桥接 (桌面媒体控制, 可选)
if [[ -z "${LXMS_MPRIS_BRIDGE:-}" ]]; then
    _player_self_dir="${BASH_SOURCE[0]%/*}"
    if [[ -f "$_player_self_dir/mpris_bridge.py" ]]; then
        LXMS_MPRIS_BRIDGE="$_player_self_dir/mpris_bridge.py"
    fi
fi

PLAYER_PID=""
PLAYER_SOCKET=""
MPRIS_BRIDGE_PID=""
# shellcheck disable=SC2034  # 播放状态供主脚本/tui 读取
PLAYBACK_POSITION=0
PLAYBACK_DURATION=0
PLAYER_STATUS="stopped"
PLAYER_EOF=0
PLAYER_VOLUME="${VOLUME:-80}"

#==============================================================================
# 工具: 调用 mpv_ipc.py
#==============================================================================
player_ipc() {
    local action="$1"; shift
    [[ -z "$LXMS_MPV_IPC" ]] || [[ ! -f "$LXMS_MPV_IPC" ]] && return 1
    [[ -z "$PLAYER_SOCKET" ]] || [[ ! -S "$PLAYER_SOCKET" ]] && return 1
    python3 "$LXMS_MPV_IPC" "$PLAYER_SOCKET" "$action" "$@" 2>/dev/null
}

# 等待 IPC socket 就绪
player_wait_ready() {
    local i
    for ((i = 0; i < 50; i++)); do
        [[ -S "$PLAYER_SOCKET" ]] && return 0
        if [[ -n "$PLAYER_PID" ]] && ! kill -0 "$PLAYER_PID" 2>/dev/null; then
            return 1  # mpv 已退出
        fi
        sleep 0.05
    done
    return 1
}

#==============================================================================
# 启动播放
#
# 用法: player_start <url> [title]
#==============================================================================
player_start() {
    local url="$1"
    local title="${2:-}"
    local artist="${3:-}"
    local album="${4:-}"
    local cover="${5:-}"
    [[ -z "$url" ]] && return 1

    # 先停止旧的
    player_stop

    # socket 放在缓存目录
    local sock_dir="${CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/lx-music-shell}"
    mkdir -p "$sock_dir"
    PLAYER_SOCKET="$sock_dir/mpv-$$.sock"
    rm -f "$PLAYER_SOCKET"

    local backend backend_name
    if declare -f get_player_backend >/dev/null 2>&1; then
        backend=$(get_player_backend 2>/dev/null || echo "")
    else
        # 独立运行时的兜底: 按优先级探测
        for _pb in "${PLAYER_BACKEND:-mpv}" mpv ffplay mplayer; do
            if command -v "$_pb" >/dev/null 2>&1; then backend="$_pb"; break; fi
        done
    fi
    [[ -z "$backend" ]] && return 1
    backend_name="${backend##*/}"

    case "$backend_name" in
        mpv)
            local args=(
                --no-video
                --really-quiet
                --no-terminal
                --audio-display=no
                "--input-ipc-server=$PLAYER_SOCKET"
                "--volume=$PLAYER_VOLUME"
                --input-media-keys=no
            )
            [[ -n "$title" ]] && args+=(--force-media-title="$title")
            args+=("$url")
            # nohup + stdio 重定向 + disown: 退出 UI 后播放器可继续后台运行
            nohup "$backend" "${args[@]}" </dev/null >/dev/null 2>&1 &
            PLAYER_PID=$!
            disown "$PLAYER_PID" 2>/dev/null || true
            ;;
        ffplay)
            # 非 mpv 后端: 无 IPC, 退化为传统控制 (进度用墙钟)
            PLAYER_SOCKET=""
            nohup "$backend" -nodisp -volume "$PLAYER_VOLUME" -autoexit "$url" </dev/null >/dev/null 2>&1 &
            PLAYER_PID=$!
            disown "$PLAYER_PID" 2>/dev/null || true
            ;;
        mplayer)
            PLAYER_SOCKET=""
            nohup "$backend" -novideo -volume "$PLAYER_VOLUME" -quiet "$url" </dev/null >/dev/null 2>&1 &
            PLAYER_PID=$!
            disown "$PLAYER_PID" 2>/dev/null || true
            ;;
        *)
            return 1
            ;;
    esac

    PLAYER_STATUS="playing"
    PLAYER_EOF=0
    PLAYBACK_POSITION=0
    PLAYBACK_DURATION=0
    PLAYBACK_START_TIME=$(date +%s)

    # 等待 mpv IPC 就绪
    if [[ "$backend_name" == "mpv" ]] && ! player_wait_ready; then
        PLAYER_STATUS="stopped"
        return 1
    fi

    # 启动 MPRIS 桥接 (桌面环境识别为活动媒体播放器)
    if [[ "$backend_name" == "mpv" ]] && [[ -n "${LXMS_MPRIS_BRIDGE:-}" ]] && [[ -f "${LXMS_MPRIS_BRIDGE:-}" ]] && [[ -n "$PLAYER_SOCKET" ]]; then
        local mpris_state mpris_cmd
        mpris_state="${CACHE_DIR:-$sock_dir}/mpris-state"
        mpris_cmd="${CACHE_DIR:-$sock_dir}/mpris-cmd"
        python3 "$LXMS_MPRIS_BRIDGE" "$PLAYER_SOCKET" "$title" "$artist" "$album" "$cover" "$mpris_state" "$mpris_cmd" &
        MPRIS_BRIDGE_PID=$!
        disown "$MPRIS_BRIDGE_PID" 2>/dev/null || true
    fi

    return 0
}

#==============================================================================
# 控制
#==============================================================================
player_stop() {
    if [[ -n "$MPRIS_BRIDGE_PID" ]]; then
        kill "$MPRIS_BRIDGE_PID" 2>/dev/null || true
        MPRIS_BRIDGE_PID=""
    fi
    if [[ -n "$PLAYER_PID" ]]; then
        player_ipc cmd '["quit"]' >/dev/null 2>&1 || true
        kill "$PLAYER_PID" 2>/dev/null || true
        wait "$PLAYER_PID" 2>/dev/null || true
        PLAYER_PID=""
    fi
    [[ -n "$PLAYER_SOCKET" ]] && rm -f "$PLAYER_SOCKET" 2>/dev/null || true
    PLAYER_SOCKET=""
    PLAYER_STATUS="stopped"
    PLAYER_EOF=0
}

player_pause() {
    if [[ -n "$PLAYER_SOCKET" ]]; then
        player_ipc set pause true >/dev/null 2>&1 || true
        PLAYER_STATUS="paused"
    elif [[ -n "$PLAYER_PID" ]]; then
        kill -STOP "$PLAYER_PID" 2>/dev/null || true
        PLAYER_STATUS="paused"
    fi
}

player_resume() {
    if [[ -n "$PLAYER_SOCKET" ]]; then
        player_ipc set pause false >/dev/null 2>&1 || true
        PLAYER_STATUS="playing"
    elif [[ -n "$PLAYER_PID" ]]; then
        kill -CONT "$PLAYER_PID" 2>/dev/null || true
        PLAYER_STATUS="playing"
    fi
}

player_toggle() {
    if [[ "$PLAYER_STATUS" == "playing" ]]; then
        player_pause
    elif [[ "$PLAYER_STATUS" == "paused" ]]; then
        player_resume
    fi
}

player_seek() {
    local sec="$1"
    [[ -z "$sec" ]] && return 1
    player_ipc cmd "[\"seek\",\"$sec\",\"absolute\"]" >/dev/null 2>&1 || true
}

player_seek_rel() {
    local sec="$1"
    [[ -z "$sec" ]] && return 1
    player_ipc cmd "[\"seek\",\"$sec\",\"relative\"]" >/dev/null 2>&1 || true
}

player_set_volume() {
    local vol="$1"
    [[ "$vol" =~ ^[0-9]+$ ]] || return 1
    [[ $vol -lt 0 ]] && vol=0
    [[ $vol -gt 100 ]] && vol=100
    PLAYER_VOLUME="$vol"
    if [[ -n "$PLAYER_SOCKET" ]]; then
        player_ipc set volume "$vol" >/dev/null 2>&1 || true
    fi
}

#==============================================================================
# 状态轮询: 从 mpv 读取真实进度/时长/暂停/结束
#
# 更新: PLAYBACK_POSITION, PLAYBACK_DURATION, PLAYER_STATUS, PLAYER_EOF
# 返回: 0 读到有效状态, 1 无 IPC/进程已死
#==============================================================================
player_poll() {
    if [[ -z "$PLAYER_SOCKET" ]] || [[ ! -S "$PLAYER_SOCKET" ]]; then
        # 无 IPC (非 mpv 后端): 墙钟估算
        if [[ -n "$PLAYER_PID" ]] && kill -0 "$PLAYER_PID" 2>/dev/null; then
            if [[ "$PLAYER_STATUS" == "playing" ]]; then
                PLAYBACK_POSITION=$(($(date +%s) - PLAYBACK_START_TIME))
            fi
            return 0
        fi
        # 进程已死 -> 播放结束
        if [[ "$PLAYER_STATUS" == "playing" ]] || [[ "$PLAYER_STATUS" == "paused" ]]; then
            PLAYER_STATUS="stopped"
            PLAYER_EOF=1
        fi
        return 1
    fi

    if [[ -n "$PLAYER_PID" ]] && ! kill -0 "$PLAYER_PID" 2>/dev/null; then
        # 进程退出
        PLAYER_STATUS="stopped"
        PLAYER_EOF=1
        rm -f "$PLAYER_SOCKET" 2>/dev/null || true
        PLAYER_SOCKET=""
        return 1
    fi

    local resp
    resp=$(player_ipc get time-pos duration pause eof-reached 2>/dev/null) || return 1
    [[ -z "$resp" ]] && return 1

    # 解析 JSON -> shell 变量 (无 jq, 用 python3)
    local parsed
    parsed=$(printf '%s' "$resp" | python3 -c '
import sys, json
try:
    d = json.loads(sys.stdin.read())
except Exception:
    sys.exit(0)
def num(v):
    if v is None:
        return ""
    if isinstance(v, bool):
        return "1" if v else "0"
    try:
        return str(int(round(float(v))))
    except Exception:
        return ""
pos = d.get("time-pos"); dur = d.get("duration")
paused = d.get("pause"); eof = d.get("eof-reached")
print("POS=%s" % num(pos))
print("DUR=%s" % num(dur))
print("PAUSED=%s" % ("1" if paused else "0"))
print("EOF=%s" % ("1" if eof else "0"))
' 2>/dev/null)
    [[ -z "$parsed" ]] && return 1

    local pos="" dur="" paused=0 eof=0
    while IFS='=' read -r k v; do
        case "$k" in
            POS) pos="$v" ;;
            DUR) dur="$v" ;;
            PAUSED) paused="$v" ;;
            EOF) eof="$v" ;;
        esac
    done <<< "$parsed"

    # shellcheck disable=SC2034  # 播放状态供主脚本/tui 读取
    if [[ "$pos" =~ ^[0-9]+$ ]]; then PLAYBACK_POSITION="$pos"; fi
    # shellcheck disable=SC2034
    if [[ "$dur" =~ ^[0-9]+$ ]] && [[ "$dur" -gt 0 ]]; then PLAYBACK_DURATION="$dur"; fi
    # shellcheck disable=SC2034
    PLAYER_EOF="$eof"

    if [[ "$eof" == "1" ]]; then
        PLAYER_STATUS="stopped"
    elif [[ "$paused" == "1" ]]; then
        PLAYER_STATUS="paused"
    else
        PLAYER_STATUS="playing"
    fi
    return 0
}

player_is_running() {
    [[ -n "$PLAYER_PID" ]] && kill -0 "$PLAYER_PID" 2>/dev/null
}

#==============================================================================
# 清理
#==============================================================================
player_cleanup() {
    player_stop
}
