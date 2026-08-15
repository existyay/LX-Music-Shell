#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
LX-Music-Shell mpv JSON IPC 客户端 (Unix socket)

与 mpv --input-ipc-server=<socket> 通信。无 socat/nc 依赖, 纯 Python。

用法:
  mpv_ipc.py <socket> get <prop> [<prop> ...]
      # 批量读取属性, 输出 {"prop": value, ...} (value 为 JSON 值, 可为 null)
  mpv_ipc.py <socket> set <prop> <json-value>
      # 设置属性, 输出 mpv 响应 (JSON) 或 {"error": "..."}
  mpv_ipc.py <socket> cmd '<json-array>'
      # 发送任意命令, 如 '["seek","10","absolute"]', 输出响应
  mpv_ipc.py <socket> raw '<json-object>'
      # 发送原始命令对象, 输出响应

退出码: 0 成功, 1 失败(连接失败/超时/协议错误)
"""

import json
import socket
import sys

CONNECT_TIMEOUT = 1.0
RECV_TIMEOUT = 1.0


class MpvError(Exception):
    pass


def _connect(path: str) -> socket.socket:
    if not path:
        raise MpvError("no socket path")
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(CONNECT_TIMEOUT)
    s.connect(path)
    return s


def _send_recv(sock: socket.socket, obj: dict):
    payload = json.dumps(obj, separators=(",", ":"))
    sock.sendall((payload + "\n").encode("utf-8"))
    sock.settimeout(RECV_TIMEOUT)
    data = b""
    while b"\n" not in data:
        chunk = sock.recv(4096)
        if not chunk:
            break
        data += chunk
    if not data.strip():
        raise MpvError("empty response")
    return json.loads(data.strip().decode("utf-8"))


def cmd_get(sock: socket.socket, props: list[str]) -> dict:
    out = {}
    for p in props:
        try:
            resp = _send_recv(sock, {"command": ["get_property", p]})
        except (MpvError, json.JSONDecodeError, OSError):
            out[p] = None
            continue
        if resp.get("error") == "success":
            out[p] = resp.get("data")
        else:
            out[p] = None
    return out


def cmd_set(sock: socket.socket, prop: str, value) -> dict:
    return _send_recv(sock, {"command": ["set_property", prop, value]})


def cmd_raw(sock: socket.socket, obj: dict) -> dict:
    return _send_recv(sock, obj)


def _parse_json_value(raw: str):
    """尽量按 JSON 解析, 失败则返回原字符串。"""
    try:
        return json.loads(raw)
    except (json.JSONDecodeError, TypeError):
        return raw


def main():
    if len(sys.argv) < 3:
        sys.stderr.write(__doc__)
        sys.exit(1)

    sock_path = sys.argv[1]
    action = sys.argv[2]

    sock = None
    try:
        sock = _connect(sock_path)
        if action == "get":
            props = sys.argv[3:] or []
            result = cmd_get(sock, props)
            print(json.dumps(result, separators=(",", ":"), ensure_ascii=False))
        elif action == "set":
            if len(sys.argv) < 5:
                raise MpvError("set requires <prop> <value>")
            prop = sys.argv[3]
            value = _parse_json_value(sys.argv[4])
            resp = cmd_set(sock, prop, value)
            print(json.dumps(resp, separators=(",", ":"), ensure_ascii=False))
        elif action == "cmd":
            if len(sys.argv) < 4:
                raise MpvError("cmd requires <json-array>")
            arr = json.loads(sys.argv[3])
            resp = cmd_raw(sock, {"command": arr})
            print(json.dumps(resp, separators=(",", ":"), ensure_ascii=False))
        elif action == "raw":
            if len(sys.argv) < 4:
                raise MpvError("raw requires <json-object>")
            obj = json.loads(sys.argv[3])
            resp = cmd_raw(sock, obj)
            print(json.dumps(resp, separators=(",", ":"), ensure_ascii=False))
        else:
            raise MpvError(f"unknown action: {action}")
        return
    except (MpvError, OSError, json.JSONDecodeError, ValueError) as e:
        print(json.dumps({"error": str(e)}, separators=(",", ":")))
        sys.exit(1)
    finally:
        if sock is not None:
            try:
                sock.close()
            except OSError:
                pass


if __name__ == "__main__":
    main()
