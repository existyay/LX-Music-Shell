#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
封面半块渲染器 (参考 bilibili-tui 的 halfblocks fallback).

用 ffmpeg 解码图片并缩放到 宽x高 像素, 然后输出 ANSI 24bit 半块字符:
每个字符单元格显示上下两个像素 (▀), 实现终端内伪图像显示。

用法:
  cover_render.py <图片文件> <宽度(字符)> <高度(字符)>
"""
import subprocess
import sys
import os

FG = "\x1b[38;2;{};{};{}m"
BG = "\x1b[48;2;{};{};{}m"
RESET = "\x1b[0m"


def main():
    if len(sys.argv) < 4:
        return 1
    path = sys.argv[1]
    try:
        w = max(1, int(sys.argv[2]))
        h = max(1, int(sys.argv[3]))
    except Exception:
        return 1
    if not os.path.isfile(path):
        return 1

    # ffmpeg 解码到 RGB24 原始像素, 分辨率=w x (h*2)
    px_w, px_h = w, h * 2
    cmd = [
        "ffmpeg", "-v", "error", "-i", path,
        "-vf", f"scale={px_w}:{px_h}",
        "-f", "rawvideo", "-pix_fmt", "rgb24", "-",
    ]
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=10)
    if proc.returncode != 0:
        return 1
    data = proc.stdout
    need = px_w * px_h * 3
    if len(data) < need:
        data = data.ljust(need, b"\x00")

    out = []
    for y in range(h):
        row = []
        for x in range(w):
            top = (y * 2) * px_w + x
            bot = (y * 2 + 1) * px_w + x
            tr, tg, tb = data[top * 3], data[top * 3 + 1], data[top * 3 + 2]
            br, bg, bb = data[bot * 3], data[bot * 3 + 1], data[bot * 3 + 2]
            row.append(FG.format(tr, tg, tb) + BG.format(br, bg, bb) + "▀")
        out.append("".join(row) + RESET)
    sys.stdout.write("\n".join(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
