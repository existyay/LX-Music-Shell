#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
LX-Music-Shell LRC/YRC 歌词解析与渲染 (go-musicfox 同款体验)

参考 go-musicfox 的 lyric.go + lyric_renderer.go:
  - LRC 标准格式: [mm:ss.xx]歌词文本
  - YRC 逐字格式: [mm:ss.xx]<mm:ss.xx,mm:ss.xx>字</mm:ss.xx>字...
  - 渲染模式: smooth (平滑渐变), wave (波动), glow (发光)
  - 字符宽度: CJK=2, ASCII=1 (使用 unicodedata.east_asian_width)

输入: stdin JSON {"lrc": "...", "yrc": "...", "current_ms": 12345,
                  "center_lines": 5, "render_mode": "smooth"}
输出: stdout JSON {"lines": ["...", ..., ""], "center_index": 2}
退出码: 0 成功, 1 错误

调用示例:
  echo '{...}' | python3 lib/lyric.py
"""

import json
import re
import sys
import unicodedata
from dataclasses import dataclass, field
from typing import Optional


#==============================================================================
# 字符宽度 (CJK=2, ASCII=1, 控制字符=0)
#==============================================================================
def char_width(ch: str) -> int:
    if not ch:
        return 0
    if ord(ch) < 32:
        return 0
    cat = unicodedata.east_asian_width(ch)
    return 2 if cat in ('F', 'W') else 1


def str_width(s: str) -> int:
    return sum(char_width(c) for c in s)


#==============================================================================
# LRC 解析
#==============================================================================
LRC_TIME_RE = re.compile(r'\[(\d+):(\d+(?:\.\d+)?)\]')


@dataclass
class LRCLine:
    time_ms: int
    text: str


def parse_lrc(lrc_text: str) -> list[LRCLine]:
    """解析标准 LRC 格式"""
    if not lrc_text:
        return []
    lines = []
    for raw in lrc_text.splitlines():
        # 支持多个时间标签: [00:01.00][00:02.00]same text
        times = LRC_TIME_RE.findall(raw)
        if not times:
            continue
        text = LRC_TIME_RE.sub('', raw).strip()
        # 跳过元数据: [ti:title], [ar:artist], [al:album], [by:...]
        if not text or text.startswith(('ti:', 'ar:', 'al:', 'by:', 'offset:', 'id:')):
            continue
        for m, s in times:
            ms = int(m) * 60_000 + int(float(s) * 1000)
            lines.append(LRCLine(time_ms=ms, text=text))
    lines.sort(key=lambda l: l.time_ms)
    return lines


#==============================================================================
# YRC 逐字解析 (网易云音乐扩展格式)
#==============================================================================
# YRC 行内格式: [start_ms,duration_ms]<start_ms,duration_ms>字<...>字...
YRC_WORD_RE = re.compile(r'<(\d+),(\d+)>([^<]*)')


@dataclass
class YRCWord:
    start_ms: int
    duration_ms: int
    text: str


@dataclass
class YRCLine:
    time_ms: int
    words: list[YRCWord] = field(default_factory=list)
    translated: str = ''


def parse_yrc(yrc_text: str) -> list[YRCLine]:
    """解析网易云 YRC 逐字歌词"""
    if not yrc_text:
        return []
    lines = []
    for raw in yrc_text.splitlines():
        m = LRC_TIME_RE.match(raw)
        if not m:
            continue
        line_ms = int(m.group(1)) * 60_000 + int(float(m.group(2)) * 1000)
        body = raw[m.end():]
        # 翻译在末尾方括号: ...[翻译文本]
        trans_m = re.search(r'\[(.*?)\]\s*$', body)
        translated = trans_m.group(1) if trans_m else ''
        if trans_m:
            body = body[:trans_m.start()]
        words = []
        for wm in YRC_WORD_RE.finditer(body):
            words.append(YRCWord(
                start_ms=int(wm.group(1)),
                duration_ms=int(wm.group(2)),
                text=wm.group(3),
            ))
        if words:
            lines.append(YRCLine(time_ms=line_ms, words=words, translated=translated))
    lines.sort(key=lambda l: l.time_ms)
    return lines


#==============================================================================
# 渲染
#==============================================================================

# 颜色 (ANSI) — 模仿 go-musicfox 的 lyric_active / lyric_inactive
ANSI_RESET = '\033[0m'
ANSI_BOLD = '\033[1m'
ANSI_DIM = '\033[2m'

# go-musicfox 默认调色板 (扩展)
COLOR_ACTIVE = '\033[1;38;5;51m'         # 青色加粗 (当前行)
COLOR_INACTIVE = '\033[38;5;245m'        # 灰色 (其他行)
COLOR_TRANSLATION = '\033[2;38;5;245m'   # 翻译行 (灰色暗淡)


def _find_line_at_time(lrc_lines: list[LRCLine], time_ms: int) -> int:
    """二分查找当前应高亮的歌词行索引"""
    if not lrc_lines:
        return -1
    lo, hi = 0, len(lrc_lines) - 1
    if time_ms < lrc_lines[0].time_ms:
        return -1
    if time_ms >= lrc_lines[hi].time_ms:
        return hi
    while lo < hi:
        mid = (lo + hi + 1) // 2
        if lrc_lines[mid].time_ms <= time_ms:
            lo = mid
        else:
            hi = mid - 1
    return lo


def render_lrc(lrc_lines: list[LRCLine], current_ms: int,
               center_lines: int, render_mode: str = 'smooth') -> tuple[list[str], int]:
    """渲染 LRC 为 N 行 (前 N/2 + 当前 + 后 N/2)
    返回: (lines, center_index)
    """
    n = max(3, center_lines | 1)  # 奇数
    center = n // 2

    idx = _find_line_at_time(lrc_lines, current_ms)
    if idx < 0:
        return [''] * n, center

    out = [''] * n
    # 当前行
    out[center] = lrc_lines[idx].text

    # 前 N/2 行
    for i in range(1, center + 1):
        if idx - i >= 0:
            out[center - i] = lrc_lines[idx - i].text

    # 后 N/2 行
    for i in range(1, center + 1):
        if idx + i < len(lrc_lines):
            out[center + i] = lrc_lines[idx + i].text

    # 着色
    colored = []
    for i, line in enumerate(out):
        if i == center:
            colored.append(f'{ANSI_BOLD}{COLOR_ACTIVE}{line}{ANSI_RESET}')
        else:
            colored.append(f'{ANSI_DIM}{COLOR_INACTIVE}{line}{ANSI_RESET}')

    return colored, center


def _smooth_color(progress: float) -> str:
    """平滑模式: 进度 → 颜色 (从灰 → 亮青)"""
    # 0.0 → 90 灰, 1.0 → 51 亮青
    r1, g1, b1 = 90, 90, 90
    r2, g2, b2 = 0, 187, 187
    r = int(r1 + (r2 - r1) * progress)
    g = int(g1 + (g2 - g1) * progress)
    b = int(b1 + (b2 - b1) * progress)
    return f'\033[38;2;{r};{g};{b}m'


def render_yrc(yrc_lines: list[YRCLine], current_ms: int,
               center_lines: int, render_mode: str = 'smooth') -> tuple[list[str], int]:
    """渲染 YRC 逐字 (类似 go-musicfox renderSmooth/renderWave/renderGlow)"""
    n = max(3, center_lines | 1)
    center = n // 2

    idx = _find_line_at_time(yrc_lines, current_ms)
    if idx < 0:
        return [''] * n, center

    # 计算每行结束时间 (用于进度计算)
    def line_end_ms(line: YRCLine) -> int:
        if not line.words:
            return line.time_ms
        last = line.words[-1]
        return last.start_ms + last.duration_ms

    out = [''] * n
    for offset in range(-center, center + 1):
        i = idx + offset
        target = center + offset
        if 0 <= i < len(yrc_lines):
            line = yrc_lines[i]
            if offset == 0:
                # 当前行: 逐字渲染
                words_rendered = []
                line_duration = line_end_ms(line) - line.time_ms
                line_progress = 0.0
                if line_duration > 0:
                    line_progress = min(1.0, max(0.0,
                        (current_ms - line.time_ms) / line_duration))

                for w in line.words:
                    word_end = w.start_ms + w.duration_ms
                    if current_ms >= word_end:
                        words_rendered.append(f'{ANSI_BOLD}{COLOR_ACTIVE}{w.text}{ANSI_RESET}')
                    elif current_ms >= w.start_ms:
                        # 当前字: 平滑进度
                        word_progress = 0.0
                        if w.duration_ms > 0:
                            word_progress = (current_ms - w.start_ms) / w.duration_ms
                        word_progress = min(1.0, max(0.0, word_progress))
                        if render_mode == 'wave':
                            color = _smooth_color(word_progress)
                            words_rendered.append(f'{ANSI_BOLD}{color}{w.text}{ANSI_RESET}')
                        else:  # smooth or glow 都用平滑
                            words_rendered.append(f'{ANSI_BOLD}{COLOR_ACTIVE}{w.text}{ANSI_RESET}')
                    else:
                        # 未开始
                        words_rendered.append(f'{ANSI_DIM}{COLOR_INACTIVE}{w.text}{ANSI_RESET}')

                line_text = ''.join(words_rendered)
                if line.translated:
                    line_text += f' {COLOR_TRANSLATION}[{line.translated}]{ANSI_RESET}'
                out[target] = line_text
            else:
                # 非当前行: 灰色整行
                text = ''.join(w.text for w in line.words)
                if line.translated:
                    text += f' [{line.translated}]'
                out[target] = f'{ANSI_DIM}{COLOR_INACTIVE}{text}{ANSI_RESET}'
        # else: 留空字符串

    return out, center


#==============================================================================
# CLI
#==============================================================================
def main():
    try:
        data = json.loads(sys.stdin.read())
    except Exception as e:
        sys.stderr.write(f'JSON parse error: {e}\n')
        sys.exit(1)

    current_ms = int(data.get('current_ms', 0))
    center_lines = int(data.get('center_lines', 5))
    render_mode = data.get('render_mode', 'smooth')
    yrc_text = data.get('yrc', '')
    lrc_text = data.get('lrc', '')

    # 优先 YRC (逐字), 降级 LRC
    if yrc_text:
        yrc_lines = parse_yrc(yrc_text)
        lines, center = render_yrc(yrc_lines, current_ms, center_lines, render_mode)
    elif lrc_text:
        lrc_lines = parse_lrc(lrc_text)
        lines, center = render_lrc(lrc_lines, current_ms, center_lines, render_mode)
    else:
        lines = [''] * center_lines
        center = center_lines // 2

    sys.stdout.write(json.dumps({
        'lines': lines,
        'center_index': center,
    }, ensure_ascii=False))


if __name__ == '__main__':
    main()