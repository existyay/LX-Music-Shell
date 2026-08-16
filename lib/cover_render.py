#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
封面半块渲染器 (参考 bilibili-tui 的 halfblocks fallback).

用 ffmpeg 解码图片并缩放到 宽x高 像素, 然后输出 ANSI 24bit 半块字符:
每个字符单元格显示上下两个像素 (▀), 实现终端内伪图像显示。

输出格式 (每一行):
  <FG><BG><▀>  (重复 WIDTH 次)
  <\033[K>      清行尾, 防止 BG 颜色渗漏到行末
  <\033[0m>     RESET
  <\r\n>        CRLF 换行 (不能用裸 LF: kitty/alacritty/wezterm 默认 ONLCR 关闭,
                 会导致下一行内容从上一行的列位置继续绘制, 造成严重错位)

用法:
  cover_render.py <图片文件> <宽度(字符)> <高度(字符)>
"""
import subprocess
import sys
import os

FG = "\x1b[38;2;{};{};{}m"
BG = "\x1b[48;2;{};{};{}m"
RESET = "\x1b[0m"
CLR_EOL = "\x1b[K"  # 清行尾: 防止 BG 颜色从最后一格渗到行末
CRLF = "\r\n"
HALF_BLOCK = b"\xe2\x96\x80"  # ▀ (U+2580) bytes - 避免字符串的 UTF-8 双重编码


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
    # -vf scale 用 lanczos (高质量重采样) + force_original_aspect_ratio=decrease +
    #   pad 到精确尺寸, 防止非正方形图片被拉伸变形.
    px_w, px_h = w, h * 2
    cmd = [
        "ffmpeg", "-v", "error", "-i", path,
        "-vf", (
            f"scale={px_w}:{px_h}:flags=lanczos:force_original_aspect_ratio=decrease,"
            f"pad={px_w}:{px_h}:(ow-iw)/2:(oh-ih)/2:color=black@0"
        ),
        "-f", "rawvideo", "-pix_fmt", "rgb24", "-",
    ]
    try:
        proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
    except Exception:
        return 1
    if proc.returncode != 0:
        return 1
    data = proc.stdout
    need = px_w * px_h * 3
    if len(data) < need:
        data = data.ljust(need, b"\x00")

    out = bytearray()
    for y in range(h):
        for x in range(w):
            top = (y * 2) * px_w + x
            bot = (y * 2 + 1) * px_w + x
            tr, tg, tb = data[top * 3], data[top * 3 + 1], data[top * 3 + 2]
            br, bg, bb = data[bot * 3], data[bot * 3 + 1], data[bot * 3 + 2]
            out.extend(FG.format(tr, tg, tb).encode("ascii"))
            out.extend(BG.format(br, bg, bb).encode("ascii"))
            out.extend(HALF_BLOCK)
        # 每行: WIDTH 个半块字符 + 清行尾 (\033[K) + RESET (\033[0m) + CRLF (\r\n)
        # \033[K 必须在 RESET 之前: 这样被清的位置不会有 BG 残留
        # RESET 在 \033[K 之后: 防止下一行的 FG/BG 颜色被上一行残留污染
        out.extend(CLR_EOL.encode("ascii"))
        out.extend(RESET.encode("ascii"))
        out.extend(CRLF.encode("ascii"))
    sys.stdout.buffer.write(bytes(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())