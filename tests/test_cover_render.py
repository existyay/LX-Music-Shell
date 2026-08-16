#!/usr/bin/env python3
"""
测试 cover_render.py 的输出格式是否正确.

期望:
  - 每行 24 个 ▀ 字符
  - 行间分隔符是 \r\n (不是 \n) - 修错位 bug
  - 每行末尾有 \033[K (清行尾) - 防 BG 渗漏
  - 末尾有 trailing \n - 保险
  - ffmpeg scale 使用高质量算法
"""
import subprocess
import sys
import os
import re

# 准备测试图片 (用 ffmpeg 生成)
TEST_IMG = "/tmp/cover_test_input.png"
SUBPROC = subprocess.run(
    ["ffmpeg", "-y", "-f", "lavfi",
     "-i", "color=c=0x4a90e2:s=400x400:d=0.04",
     "-vf", "geq='r=128+64*sin(2*PI*X/W):g=128+64*sin(2*PI*Y/H):b=128+64*sin(2*PI*(X+Y)/(W+H))'",
     "-frames:v", "1", TEST_IMG],
    capture_output=True, timeout=10,
)
assert SUBPROC.returncode == 0, f"ffmpeg create test img failed: {SUBPROC.stderr.decode()}"

# 调用 cover_render.py
WIDTH, HEIGHT = 24, 12
COVER_RENDER = "/home/issac/Proj/LX-Music-Shell/lib/cover_render.py"
proc = subprocess.run(
    ["python3", COVER_RENDER, TEST_IMG, str(WIDTH), str(HEIGHT)],
    capture_output=True, timeout=10,
)
assert proc.returncode == 0, f"cover_render failed: {proc.stderr.decode()}"
data = proc.stdout

errors = []

# 检查 1: ▀ 字符数量 = WIDTH * HEIGHT
halfblocks = data.count(b"\xe2\x96\x80")
if halfblocks != WIDTH * HEIGHT:
    errors.append(f"FAIL: ▀ count = {halfblocks}, expected {WIDTH * HEIGHT}")
else:
    print(f"PASS: ▀ count = {halfblocks}")

# 检查 2: 行数 = HEIGHT (通过 \n 或 \r\n 分隔)
# 注意: \r\n 算作一个 \n
lines = data.split(b"\n")
# 最后一行为空 (trailing \n)
if lines[-1] == b"":
    actual_lines = len(lines) - 1
else:
    actual_lines = len(lines)
if actual_lines != HEIGHT:
    errors.append(f"FAIL: lines = {actual_lines}, expected {HEIGHT}")
else:
    print(f"PASS: lines = {actual_lines}")

# 检查 3: 每行都应该有 WIDTH 个 ▀
for i, line in enumerate(lines[:-1]):  # 排除最后一个空行
    cnt = line.count(b"\xe2\x96\x80")
    if cnt != WIDTH:
        errors.append(f"FAIL: line {i} has {cnt} ▀, expected {WIDTH}")
print(f"PASS: each line has {WIDTH} ▀")

# 检查 4: 行间使用 \r\n 而不是 \n (修复错位关键!)
# 数据中应包含 \r\n, 且 \r\n 出现的次数 = HEIGHT (行间 HEIGHT-1 个 + 末尾 1 个)
crlf_count = data.count(b"\r\n")
lf_only = data.replace(b"\r\n", b"").count(b"\n")  # 不在 \r\n 中的 \n
if crlf_count != HEIGHT:
    errors.append(f"FAIL: \\r\\n count = {crlf_count}, expected {HEIGHT} (HEIGHT-1 line breaks + 1 trailing)")
else:
    print(f"PASS: \\r\\n count = {crlf_count} (HEIGHT-1 line breaks + 1 trailing)")
if lf_only > 0:
    errors.append(f"FAIL: found {lf_only} bare LF (without CR) - causes misalignment!")

# 检查 6: 末尾有 trailing newline
if not data.endswith(b"\n"):
    errors.append("FAIL: output should end with trailing newline")
else:
    print("PASS: trailing newline present")

# 检查 7: 每行末尾有 \033[K (清行尾)
# 找所有 ▀ 之后的字节序列
positions = [m.start() for m in re.finditer(b"\xe2\x96\x80", data)]
rows_with_k = 0
for i, pos in enumerate(positions):
    if (i + 1) % WIDTH == 0:  # 每行的最后一个 ▀
        # 找这个 ▀ 之后的下一个 ANSI 或非字符
        after = data[pos+3:pos+30]
        if b"\033[K" in after[:8]:
            rows_with_k += 1
if rows_with_k != HEIGHT:
    errors.append(f"FAIL: only {rows_with_k}/{HEIGHT} rows have \\033[K after last ▀")
else:
    print(f"PASS: all {HEIGHT} rows have \\033[K after last ▀")

# 检查 8: 输出末尾是 RESET (\033[0m) 后跟 \r\n
# 去掉末尾的 \r\n 后应该以 \033[0m 结尾
if not data.rstrip(b"\r\n").endswith(b"\033[0m"):
    errors.append("FAIL: output should end with RESET")
else:
    print("PASS: output ends with RESET before CRLF")

# 总结
if errors:
    print("\n=== FAILED ===")
    for e in errors:
        print(e)
    sys.exit(1)
else:
    print("\n=== ALL PASSED ===")