#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
LX-Music-Shell MPRIS D-Bus bridge.

让桌面环境 (GNOME/KDE/Plasma 等) 把当前 mpv 识别为活动媒体播放器,
支持 播放/暂停/停止/上一首/下一首/Seek/进度/元数据。

用法:
  mpris_bridge.py <mpv-ipc-socket> "<title>" ["<artist>"] ["<album>"] ["<cover-url>"] [<state-file>] [<cmd-file>]

依赖 (可选): python-dbus (Arch: python-dbus)
若未安装, 脚本静默退出, 不影响播放。
"""

import os
import socket
import sys
import time

MPRIS_NAME = "org.mpris.MediaPlayer2.lx-music-shell"
OBJECT_PATH = "/org/mpris/MediaPlayer2"
ROOT_IFACE = "org.mpris.MediaPlayer2"
PLAYER_IFACE = "org.mpris.MediaPlayer2.Player"
PROP_IFACE = "org.freedesktop.DBus.Properties"


def _dbus_available():
    try:
        import dbus  # noqa: F401
        import dbus.mainloop.glib  # noqa: F401
        from gi.repository import GLib  # noqa: F401
        return True
    except Exception:
        return False


def mpv_cmd(sock_path: str, command: list, timeout=1.5):
    if not sock_path or not os.path.exists(sock_path):
        return None
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(timeout)
        s.connect(sock_path)
        payload = '{"command":' + __import__('json').dumps(command, separators=(",", ":")) + '}\n'
        s.sendall(payload.encode("utf-8"))
        data = b""
        while b"\n" not in data:
            chunk = s.recv(4096)
            if not chunk:
                break
            data += chunk
        s.close()
        if not data.strip():
            return None
        return __import__('json').loads(data.strip().decode("utf-8"))
    except Exception:
        return None


def mpv_get(sock_path: str, prop: str):
    r = mpv_cmd(sock_path, ["get_property", prop])
    if r and r.get("error") == "success":
        return r.get("data")
    return None


def main():
    if not _dbus_available():
        sys.exit(0)

    import dbus
    import dbus.mainloop.glib
    import dbus.service
    from gi.repository import GLib

    sock_path = sys.argv[1] if len(sys.argv) > 1 else ""
    initial_title = sys.argv[2] if len(sys.argv) > 2 else "LX-Music-Shell"
    initial_artist = sys.argv[3] if len(sys.argv) > 3 else ""
    initial_album = sys.argv[4] if len(sys.argv) > 4 else ""
    initial_cover = sys.argv[5] if len(sys.argv) > 5 else ""
    state_file = sys.argv[6] if len(sys.argv) > 6 else ""
    cmd_file = sys.argv[7] if len(sys.argv) > 7 else ""

    state = {
        "title": initial_title,
        "artist": initial_artist,
        "album": initial_album,
        "cover": initial_cover,
        "duration_us": 0,
        "position_us": 0,
        "paused": False,
        "volume": 1.0,
        "play_mode": "list",
        "loop_status": "None",
        "shuffle": False,
        "can_go_next": True,
        "can_go_previous": True,
    }

    def append_cmd(cmd):
        if not cmd_file:
            return
        try:
            with open(cmd_file, "a", encoding="utf-8") as f:
                f.write(cmd + "\n")
        except Exception:
            pass

    def read_state_file():
        if not state_file or not os.path.exists(state_file):
            return
        try:
            with open(state_file, "r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if "=" not in line:
                        continue
                    k, v = line.split("=", 1)
                    v = v.strip().strip('"')
                    if k == "PLAY_MODE":
                        state["play_mode"] = v
                        if v == "loop":
                            state["loop_status"] = "Playlist"; state["shuffle"] = False
                        elif v == "single":
                            state["loop_status"] = "Track"; state["shuffle"] = False
                        elif v == "random":
                            state["loop_status"] = "Playlist"; state["shuffle"] = True
                        else:
                            state["loop_status"] = "None"; state["shuffle"] = False
                    elif k == "CURRENT_TRACK" and v:
                        state["title"] = v
        except Exception:
            pass

    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    if bus.name_has_owner(MPRIS_NAME):
        # 已有桥接实例, 不重复注册
        sys.exit(0)

    class Properties(dbus.service.Object):
        def __init__(self):
            super().__init__(bus, OBJECT_PATH)

        @dbus.service.method(PROP_IFACE, in_signature="ss", out_signature="v")
        def Get(self, iface, prop):
            return self._get(iface, prop)

        @dbus.service.method(PROP_IFACE, in_signature="ssv", out_signature="")
        def Set(self, iface, prop, value):
            if iface == PLAYER_IFACE and prop == "Volume":
                try:
                    v = float(value)
                except Exception:
                    return
                state["volume"] = max(0.0, min(1.0, v))
                vol = int(round(v * 100))
                mpv_cmd(sock_path, ["set_property", "volume", vol])
            elif iface == PLAYER_IFACE and prop == "LoopStatus":
                try:
                    loop = str(value)
                except Exception:
                    return
                if loop == "Track":
                    append_cmd("mode:single")
                elif loop == "Playlist":
                    append_cmd("mode:loop")
                else:
                    append_cmd("mode:list")
            elif iface == PLAYER_IFACE and prop == "Shuffle":
                try:
                    shuf = bool(value)
                except Exception:
                    return
                if shuf:
                    append_cmd("mode:random")
                else:
                    append_cmd("mode:list")

        @dbus.service.method(PROP_IFACE, in_signature="s", out_signature="a{sv}")
        def GetAll(self, iface):
            return self._get_all(iface)

        def _get(self, iface, prop):
            if iface == ROOT_IFACE:
                root = {
                    "CanQuit": dbus.Boolean(True),
                    "CanRaise": dbus.Boolean(False),
                    "Identity": dbus.String("LX-Music-Shell"),
                    "DesktopEntry": dbus.String("lx-music-shell"),
                    "SupportedUriSchemes": dbus.Array([], signature="s"),
                    "SupportedMimeTypes": dbus.Array([], signature="s"),
                }
                return root.get(prop, dbus.String(""))
            if iface == PLAYER_IFACE:
                player = self._player_props()
                return player.get(prop, dbus.String(""))
            return dbus.String("")

        def _get_all(self, iface):
            if iface == ROOT_IFACE:
                return dbus.Dictionary(
                    {
                        "CanQuit": dbus.Boolean(True),
                        "CanRaise": dbus.Boolean(False),
                        "Identity": dbus.String("LX-Music-Shell"),
                        "DesktopEntry": dbus.String("lx-music-shell"),
                        "SupportedUriSchemes": dbus.Array([], signature="s"),
                        "SupportedMimeTypes": dbus.Array([], signature="s"),
                    },
                    signature="sv",
                )
            if iface == PLAYER_IFACE:
                return dbus.Dictionary(self._player_props(), signature="sv")
            return dbus.Dictionary({}, signature="sv")

        def _player_props(self):
            meta = {
                "xesam:title": dbus.String(state["title"]),
                "mpris:length": dbus.Int64(state["duration_us"]),
                "mpris:trackid": dbus.ObjectPath("/org/mpris/MediaPlayer2/Track/1"),
            }
            if state["artist"]:
                meta["xesam:artist"] = dbus.Array([dbus.String(state["artist"])], signature="s")
            if state["album"]:
                meta["xesam:album"] = dbus.String(state["album"])
            if state["cover"]:
                meta["mpris:artUrl"] = dbus.String(state["cover"])

            status = "Paused" if state["paused"] else "Playing"
            return {
                "PlaybackStatus": dbus.String(status),
                "LoopStatus": dbus.String(state["loop_status"]),
                "Rate": dbus.Double(1.0),
                "Shuffle": dbus.Boolean(state["shuffle"]),
                "Metadata": dbus.Dictionary(meta, signature="sv"),
                "Volume": dbus.Double(state["volume"]),
                "Position": dbus.Int64(state["position_us"]),
                "MinimumRate": dbus.Double(1.0),
                "MaximumRate": dbus.Double(1.0),
                "CanGoNext": dbus.Boolean(True),
                "CanGoPrevious": dbus.Boolean(True),
                "CanPlay": dbus.Boolean(True),
                "CanPause": dbus.Boolean(True),
                "CanSeek": dbus.Boolean(True),
                "CanControl": dbus.Boolean(True),
            }

    class MprisPlayer(Properties):
        def __init__(self):
            super().__init__()

        @dbus.service.method(ROOT_IFACE, in_signature="", out_signature="")
        def Raise(self):
            pass

        @dbus.service.method(ROOT_IFACE, in_signature="", out_signature="")
        def Quit(self):
            pass

        @dbus.service.method(PLAYER_IFACE, in_signature="", out_signature="")
        def Play(self):
            append_cmd("play")

        @dbus.service.method(PLAYER_IFACE, in_signature="", out_signature="")
        def Pause(self):
            append_cmd("pause")

        @dbus.service.method(PLAYER_IFACE, in_signature="", out_signature="")
        def PlayPause(self):
            append_cmd("playpause")

        @dbus.service.method(PLAYER_IFACE, in_signature="", out_signature="")
        def Stop(self):
            append_cmd("stop")

        @dbus.service.method(PLAYER_IFACE, in_signature="", out_signature="")
        def Next(self):
            append_cmd("next")

        @dbus.service.method(PLAYER_IFACE, in_signature="", out_signature="")
        def Previous(self):
            append_cmd("previous")

        @dbus.service.method(PLAYER_IFACE, in_signature="x", out_signature="")
        def Seek(self, offset_us):
            sec = int(offset_us) / 1_000_000.0
            mpv_cmd(sock_path, ["seek", sec, "relative"])

        @dbus.service.method(PLAYER_IFACE, in_signature="ox", out_signature="")
        def SetPosition(self, trackid, position_us):
            sec = int(position_us) / 1_000_000.0
            mpv_cmd(sock_path, ["seek", sec, "absolute"])

        @dbus.service.method(PLAYER_IFACE, in_signature="s", out_signature="")
        def OpenUri(self, uri):
            mpv_cmd(sock_path, ["loadfile", uri])

    def poll():
        read_state_file()
        try:
            title = mpv_get(sock_path, "media-title")
            if title:
                state["title"] = title
            dur = mpv_get(sock_path, "duration")
            if isinstance(dur, (int, float)) and dur is not None:
                state["duration_us"] = int(dur * 1_000_000)
            pos = mpv_get(sock_path, "time-pos")
            if isinstance(pos, (int, float)) and pos is not None:
                state["position_us"] = int(pos * 1_000_000)
            paused = mpv_get(sock_path, "pause")
            if isinstance(paused, bool):
                state["paused"] = paused
            vol = mpv_get(sock_path, "volume")
            if isinstance(vol, (int, float)):
                state["volume"] = max(0.0, min(1.0, float(vol) / 100.0))
        except Exception:
            pass
        return True

    try:
        name = dbus.service.BusName(MPRIS_NAME, bus, allow_replacement=True, replace_existing=False)
    except Exception:
        sys.exit(0)

    player = MprisPlayer()
    GLib.timeout_add(1000, poll)
    loop = GLib.MainLoop()
    loop.run()


if __name__ == "__main__":
    main()
