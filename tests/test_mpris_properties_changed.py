#!/usr/bin/env python3
"""
测试 PropertiesChanged signal 是否发出.
"""
import sys
import os
import subprocess
import time
import signal
import socket
import tempfile
import threading

sys.path.insert(0, "/home/issac/Proj/LX-Music-Shell/lib")


def main():
    try:
        import dbus
        from gi.repository import GLib
    except ImportError:
        print("SKIP: dbus/gi not available")
        sys.exit(0)

    sock_dir = tempfile.mkdtemp(prefix="lxms-sig-test-")
    sock_path = os.path.join(sock_dir, "mpv.sock")
    state_file = os.path.join(sock_dir, "state")
    cmd_file = os.path.join(sock_dir, "cmd")

    # 假 mpv server
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(sock_path)
    server.listen(1)
    server.settimeout(0.3)

    responses = {
        b"pause": b'{"data":false,"error":"success"}\n',
        b"time-pos": b'{"data":1.0,"error":"success"}\n',
        b"duration": b'{"data":100.0,"error":"success"}\n',
        b"eof-reached": b'{"data":false,"error":"success"}\n',
        b"media-title": b'{"data":"Test","error":"success"}\n',
        b"volume": b'{"data":80,"error":"success"}\n',
    }

    def serve_loop():
        while True:
            try:
                conn, _ = server.accept()
                data = conn.recv(4096)
                # 默认响应: 任何未知命令返回 {"error":"success"}
                resp = b'{"error":"success"}\n'
                for key, val in responses.items():
                    if key in data:
                        resp = val
                        break
                try:
                    conn.sendall(resp)
                except Exception:
                    pass
                conn.close()
            except socket.timeout:
                continue
            except Exception:
                break

    server_thread = threading.Thread(target=serve_loop, daemon=True)
    server_thread.start()

    # 启动 bridge
    bridge_path = "/home/issac/Proj/LX-Music-Shell/lib/mpris_bridge.py"
    proc = subprocess.Popen(
        ["python3", bridge_path, sock_path, "Test", "Artist", "Album",
         "", state_file, cmd_file],
        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
    )

    # 等待 bridge 注册
    time.sleep(2)

    # 设置 D-Bus 主循环以接收 signal
    import dbus.mainloop.glib
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()

    captured = []

    def on_props_changed(iface, changed, invalidated):
        captured.append((str(iface), dict(changed), list(invalidated)))

    # 订阅 signal (必须指定 path, 因为 signal 是按路径发送的)
    bus.add_signal_receiver(
        on_props_changed,
        signal_name="PropertiesChanged",
        dbus_interface="org.freedesktop.DBus.Properties",
        bus_name="org.mpris.MediaPlayer2.lx-music-shell",
        path="/org/mpris/MediaPlayer2",
    )

    # 运行 GLib 主循环 (后才能 dispatch signal callback)
    from gi.repository import GLib
    loop = GLib.MainLoop()
    loop_ctx = GLib.MainContext.default()

    errors = []

    try:
        # 触发 Next (写入 cmd 文件但不直接发 signal, 需等 poll 检测状态变化)
        # poll() 每 1 秒执行一次, 所以我们要等至少 1.5s
        proxy = bus.get_object("org.mpris.MediaPlayer2.lx-music-shell", "/org/mpris/MediaPlayer2")
        player = bus.get_object("org.mpris.MediaPlayer2.lx-music-shell", "/org/mpris/MediaPlayer2")
        player_iface = dbus.Interface(player, "org.mpris.MediaPlayer2.Player")
        props_iface = dbus.Interface(player, "org.freedesktop.DBus.Properties")

        # 触发命令
        player_iface.Next()
        player_iface.Previous()
        player_iface.Pause()
        player_iface.PlayPause()
        props_iface.Set("org.mpris.MediaPlayer2.Player", "Volume", dbus.Double(0.5))
        props_iface.Set("org.mpris.MediaPlayer2.Player", "LoopStatus", dbus.String("Playlist"))
        props_iface.Set("org.mpris.MediaPlayer2.Player", "Shuffle", dbus.Boolean(True))

        # pump 主循环 2.5s, 让 signal callback 被 dispatch
        for _ in range(50):
            while loop_ctx.pending():
                loop_ctx.iteration(False)
            time.sleep(0.05)

        # 检查
        if not captured:
            errors.append("FAIL: No PropertiesChanged signal captured")
        else:
            print(f"PASS: Captured {len(captured)} PropertiesChanged signals:")
            for iface, changed, invalidated in captured:
                keys = list(changed.keys())
                print(f"  iface={iface}, keys={keys}")

        # 检查 cmd 文件内容
        if os.path.exists(cmd_file):
            with open(cmd_file) as f:
                cmds = f.read().strip().split("\n")
            print(f"PASS: cmd file has {len(cmds)} commands: {cmds}")
            expected_cmds = ["next", "previous", "pause", "playpause", "mode:loop", "mode:random"]
            for cmd in expected_cmds:
                if cmd not in cmds:
                    errors.append(f"FAIL: missing cmd '{cmd}'")
        else:
            errors.append("FAIL: cmd file not created")

    finally:
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
        server.close()
        try:
            os.unlink(sock_path)
        except Exception:
            pass
        try:
            import shutil
            shutil.rmtree(sock_dir, ignore_errors=True)
        except Exception:
            pass

    if errors:
        print("\n=== FAILED ===")
        for e in errors:
            print(e)
        sys.exit(1)
    else:
        print("\n=== ALL PASSED ===")


if __name__ == "__main__":
    main()