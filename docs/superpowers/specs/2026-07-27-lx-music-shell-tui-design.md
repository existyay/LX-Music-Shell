# LX-Music-Shell TUI/鼠标/封面设计规范

> **作者**: existyay
> **日期**: 2026-07-27
> **状态**: 已批准待实现
> **关联项目**: LX-Music-Shell v1.1.1+ (目标 v2.0)

## 1. 背景与目标

### 1.1 项目当前状态
LX-Music-Shell 是一个基于纯 Bash 的终端音乐播放器，已在 AUR 发布 v1.1.1。它能够：
- 搜索并播放来自 6 个中国音乐平台（酷狗/酷我/网易云/QQ/咪咕/喜马拉雅）的歌曲
- 网络自动重连
- 实时状态栏
- 完整的 AUR 打包流程

### 1.2 现有局限
- **5/6 源使用 mock 数据** —— 只有网易云使用了真实 API
- **纯 CLI 交互** —— 命令列表式 (`/search`、`/play`)，缺乏可视化层次
- **不支持鼠标** —— 仅靠键盘命令行
- **无专辑封面显示** —— 终端功能未充分利用
- **粗糙的元数据展示** —— 不显示音质等级

### 1.3 设计目标
将 LX-Music-Shell 演化为具备 **TUI 界面 / 鼠标交互 / 专辑封面 / 音质保底** 能力的"终端音乐客户端"，同时**保持纯 Bash 核心**，向后兼容现有用户。

---

## 2. 设计原则

设计中遵循的 5 条核心原则：

| # | 原则 | 说明 |
|---|------|------|
| 1 | **核心代码保持纯 Bash** | 业务逻辑不引入新解释器依赖 |
| 2 | **能力渐进增强** | 检测到能力即启用，未检测到则优雅降级 |
| 3 | **向后兼容** | 现有 CLI 入口完全保留，用户无需迁移 |
| 4 | **音质优先** | 用户明确选择音质档，回退链路透明 |
| 5 | **键盘鼠标同权** | 两种输入设备可完成相同任务 |

---

## 3. 架构总览

### 3.1 分层架构

```
┌─────────────────────────────────────────────────────┐
│  UI 渲染层 (lib/tui.sh)                               │
│    • 简化分栏布局（自适应宽屏/窄屏）                    │
│    • 顶部状态条 + 主区（列表+详情）                    │
│    • 可选封面图渲染（kitty / iTerm2 / sixel）         │
└─────────────────────────────────────────────────────┘
              ↓                  ↑
┌─────────────────────────────────────────────────────┐
│  输入处理层 (lib/input.sh)                             │
│    • 键盘事件（↑↓/Enter/Tab/Space/Q 等）             │
│    • 鼠标事件（SGR 1006 协议：单击/双击/滚轮）        │
│    • 区域命中测试（点击坐标 → 面板）                  │
└─────────────────────────────────────────────────────┘
              ↓                  ↑
┌─────────────────────────────────────────────────────┐
│  能力检测层 (lib/capability.sh)                        │
│    • 图片协议检测（kitty / iTerm2 / sixel / 无）      │
│    • 鼠标支持检测（SGR 1006）                         │
│    • Unicode / 真彩色 / 颜色深度检测                  │
└─────────────────────────────────────────────────────┘
              ↓                  ↑
┌─────────────────────────────────────────────────────┐
│  业务核心层（已有 + 重构）                             │
│    • lx-music-shell 主脚本                            │
│    • sources/ — 6 个源适配器                          │
│    • player backends (mpv/mplayer/ffplay)            │
└─────────────────────────────────────────────────────┘
```

### 3.2 模块接口

#### 3.2.1 `lib/capability.sh`
**职责**: 探测终端能力，并缓存结果供后续模块使用。

**导出变量**:
- `LXMS_TERM_IMAGES` (kitty / iTerm / sixel / none)
- `LXMS_TERM_MOUSE` (1 / 0)
- `LXMS_TERM_UNICODE` (1 / 0)
- `LXMS_TERM_TRUECOLOR` (1 / 0)
- `LXMS_TERM_COLS`, `LXMS_TERM_LINES`
- `LXMS_FORCE_TUI` (1 / 0) — 用户手动强制覆盖

**主函数**: `detect_capability()` — 初始化上述变量。

#### 3.2.2 `lib/tui.sh`
**职责**: 渲染 TUI 界面。接受数据模型，返回 ANSI 序列。

**主函数**:
- `tui_render(state)` — 渲染整个界面
- `tui_render_status_bar(state)` — 渲染顶部状态条
- `tui_render_main_layout(state)` — 渲染主区分栏
- `tui_render_cover(cover_url)` — 渲染封面图（可选）
- `tui_render_lyrics()` — 渲染歌词区（未来扩展）

**输入参数 `state` 结构**: 当前播放信息 + 播放列表 + 选中项。

#### 3.2.3 `lib/input.sh`
**职责**: 读取并解析输入事件（键盘 + 鼠标）。

**主函数**:
- `input_read_event()` — 读取一个事件（阻塞/非阻塞可选）
- `input_parse_keyboard(seq)` — 解析键盘序列
- `input_parse_mouse(seq)` — 解析 SGR 鼠标序列
- `input_mouse_to_action(coords, regions)` — 鼠标坐标 → UI 动作

**事件类型**: KEY_DOWN / KEY_UP / KEY_ENTER / KEY_TAB / MOUSE_CLICK / MOUSE_DOUBLE / MOUSE_SCROLL / KEY_QUIT。

#### 3.2.4 `sources/*.sh`（重构现有 6 个）
**职责**: 每个源实现标准接口。

**统一接口**:
```bash
source_get_playlist_url(query, limit)  # 搜索歌曲
source_get_play_url(song_id, quality)  # 获取播放 URL（支持音质回退）
source_get_cover(song_id)              # 获取封面 URL
source_get_lyrics(song_id)             # 获取歌词（可选）
```

---

## 4. TUI 界面设计

### 4.1 顶部状态条

```
┌──────────────────────────────────────────────────────────────┐
│ 🎵 LX-Music-Shell  v2.0  │ 网络: ●已连接 │ 音量: ▰▰▰▰ 80%   │
└──────────────────────────────────────────────────────────────┘
```

**固定 1 行**，高 1。

### 4.2 主区分栏布局（cols >= 100 时）

```
┌──────────────────────┬───────────────────────────┐
│  列表区 (40%)          │  详情区 (60%)               │
│ ▶ 1. 稻香              │  [封面图（如支持）          │
│   2. 晴天              │   ─────────────          │
│   3. 七里香            │   🎵 🎵 🎵               │
│   4. 夜曲              │   ─────────────          │
│   5. 简单爱            │                          │
│   ...                 │  歌名: 稻香                │
│                      │  歌手: 周杰伦              │
│ [键盘提示]            │  专辑: 魔杰座              │
│ ↑↓: 移动              │  时长: 03:42              │
│ Enter: 播放           │  音质: FLAC ✓             │
│ Tab: 切面板            │                          │
│ Q: 退出               │  [进度]                   │
└──────────────────────┴───────────────────────────┘
```

### 4.3 折叠布局（cols < 100 时）

```
┌─────────────────────────────────────────┐
│ [状态条]                                  │
├─────────────────────────────────────────┤
│ [详情区]                                  │
│   封面 / 元数据 / 音质                     │
├─────────────────────────────────────────┤
│ [列表区]                                  │
│   ▶ 稻香                                  │
│     ...                                  │
└─────────────────────────────────────────┘
```

### 4.4 自适应规则

| 宽度 (cols) | 高度 (lines) | 布局 | 封面尺寸 |
|-------------|--------------|------|----------|
| >= 100      | >= 24        | 左右分栏 | medium |
| <  100      | >= 24        | 上下堆叠 | small |
| *           | <  24        | 最小化 | none |
| *           | 不支持图片  | 占位 | none |

### 4.5 视觉约定

- **选中项**: 高亮背景（蓝色/青色背景 + 白字）
- **当前播放**: 行首 `▶ ` 标记
- **音质标签**: `HiRes` / `FLAC` / `HQ` / `SQ` / `---`
- **网络状态**: `●已连接`(绿) / `●已断开`(红) / `○检测中`(黄)
- **进度条**: 字符 `▰▱`

---

## 5. 鼠标交互设计

### 5.1 启用条件

```
SGR 1006 支持: 1
且配置 UI_MOUSE != off
→ 自动启用
```

启用序列: `\033[?1006h` (SGR 模式)
退出序列: `\033[?1006l` (在 `on_exit` 时调用)

### 5.2 事件处理

| 事件 | 参数 | 动作 |
|------|------|------|
| 单击列表项 | (row, col) | 选中该项 |
| 双击列表项 | (row, col) | 立即播放 |
| 单击"搜索"按钮 | (row, col) | 触发搜索 |
| 单击"音量 +/-" | (row, col) | 调整音量 |
| 滚轮向上 | - | 列表上滚 |
| 滚轮向下 | + | 列表下滚 |
| 单击进度条 | (col) | 跳转到该时间点 |

### 5.3 区域命中测试

`input_mouse_to_action(coords)` 通过对比点击坐标与每个面板的边界矩形，决定点击属于哪个面板和哪个元素。

每个面板在每帧渲染时记录其几何信息（起始行/列、宽/高），由 `tui_render()` 维护。

---

## 6. 音质保底策略

### 6.1 音质等级

| 等级 | 标签 | 比特率/格式 | 优先级 (highest 模式) |
|------|------|-------------|----------------------|
| hires | HiRes | 24bit/96kHz+ | 1 (最佳) |
| flac  | FLAC  | ~1000 kbps | 2 |
| 320   | HQ    | 320 kbps MP3 | 3 |
| 128   | SQ    | 128 kbps MP3 | 4 (兜底) |

### 6.2 用户配置 (`~/.config/lx-music-shell/config`)

```bash
# 音质偏好模式
QUALITY_MODE=highest      # highest|balanced|fastest

# 默认音质请求 (会按音质回退链尝试)
DEFAULT_QUALITY=flac      # hires|flac|320|128

# 是否自动跳过无法获取的音质
SKIP_UNAVAILABLE_QUALITY=true
```

`QUALITY_MODE` 影响回退链长度：
- `highest`: 完整回退链 (hires → flac → 320 → 128)
- `balanced`: 跳过 hires (flac → 320 → 128)
- `fastest`: 只用 320 → 128

### 6.3 播放 URL 获取回退

每个 `sources/*.sh` 实现统一回退：

```bash
source_get_play_url() {
    local song_id="$1"
    local requested="${2:-$DEFAULT_QUALITY}"

    for q in $requested $QUALITY_FALLBACK; do
        local url
        url=$(fetch_url_for_quality "$song_id" "$q") || continue
        [[ -n "$url" ]] && {
            printf '%s\n' "$q:$url"
            return 0
        }
    done
    return 1
}
```

### 6.4 UI 反馈

播放列表的歌曲条目后追加音质标签：

```
▶ 1. 稻香                          [FLAC]
  2. 晴天                            [HQ]
  3. 模拟音源                          [---]
```

---

## 7. 配置扩展

### 7.1 新增配置项 (`~/.config/lx-music-shell/config`)

```bash
# === UI 模式 (v2.0 新增) ===
UI_TUI=auto            # auto=自动检测  on=强制启用  off=纯 CLI
UI_MOUSE=auto          # auto=检测启用   on=强制启用  off=禁用

# === 音质 (v2.0 新增) ===
QUALITY_MODE=highest   # highest|balanced|fastest
DEFAULT_QUALITY=flac   # hires|flac|320|128

# === 视觉显示 (v2.0 新增) ===
DISPLAY_ALBUM=true     # 显示专辑信息
DISPLAY_COVER=true     # 显示封面（如支持）
COVER_SIZE=medium      # small|medium|large

# === 已有配置（保持兼容） ===
PLAYER_BACKEND="mpv"
DEFAULT_SOURCE="kugou"
SEARCH_LIMIT="20"
PLAY_MODE="list"
VOLUME="80"
AUTO_UPDATE_SOURCES="true"
UI_COLOR="true"
AUTO_RECONNECT="true"
```

### 7.2 向后兼容规则

- v1.x 用户的 `~/.config/lx-music-shell/config` 中**没有**的新增项，加载时使用默认值
- 已有的旧项保持原值
- 旧版 `lx-music-shell` 不应读取新项（最简单的兼容：忽略未知变量）

---

## 8. 文件结构

### 8.1 新增/重构文件

```
lx-music-shell/
├── lx-music-shell                # 主入口 (v2.0 启用 UI 调度)
├── lib/
│   ├── capability.sh             # 新增：终端能力检测
│   ├── tui.sh                    # 新增：TUI 渲染
│   ├── input.sh                  # 新增：输入处理
│   └── ui.sh                     # 已有（保留）
├── sources/                      # 重构：每个源独立文件
│   ├── _base.sh                  # 通用接口与回退逻辑
│   ├── netease.sh                # 真实实现（已可用）
│   ├── kugou.sh                  # 待实现（需签名）
│   ├── kuwo.sh                   # 待实现（需 cookie）
│   ├── qq.sh                     # 待实现（需 vkey）
│   ├── migu.sh                   # 占位（需特殊 header）
│   └── ximalaya.sh               # 占位（需加密参数）
├── tools/
│   └── release.sh                # 已有
└── docs/
    └── superpowers/
        └── specs/
            └── 2026-07-27-lx-music-shell-tui-design.md  # 本文档
```

---

## 9. 数据模型

### 9.1 播放列表条目（扩展）

**v1.x 格式**: `"序号|歌名|歌手|时长|URL"`

**v2.0 格式**:
```
"序号|歌名|歌手|时长|song_id|quality|cover_url|available_qualities|URL"
```

字段说明:
1. 序号: 1, 2, 3, ...
2. 歌名: 字符串
3. 歌手: 字符串
4. 时长: mm:ss
5. song_id: 源内部 ID
6. quality: 当前 URL 使用的音质 (hires/flac/320/128)
7. cover_url: 封面图片 URL（可为空）
8. available_qualities: 空格分隔的支持列表
9. URL: 当前播放 URL

### 9.2 选中状态

```bash
SELECTED_INDEX=3       # 列表中当前选中项 (0-based)
PLAYING_INDEX=2        # 当前播放项
```

---

## 10. 输入输出规范

### 10.1 输入事件流

```
键盘: read -rsn1 KEY   → 按键转 action
鼠标: read -rs 序列    → SGR 解析 → 坐标 → 命中测试 → action
```

**统一为内部事件**:
```
EVENT_DOWN        →  SELECT_NEXT
EVENT_UP          →  SELECT_PREV
EVENT_ENTER       →  PLAY_SELECTED
EVENT_TAB         →  SWITCH_PANEL
EVENT_SPACE       →  PAUSE_TOGGLE
EVENT_Q           →  QUIT
MOUSE_CLICK(2,5)  →  PLAY_INDEX=2, ROW=5
```

### 10.2 渲染触发

- 输入事件触发 state 更新 → 重新渲染受影响面板
- 状态条由 `render_status_bar_loop()` 后台每 200ms 更新一次
- 进度条更新独立 tick

---

## 11. 性能考虑

### 11.1 输入循环性能

- 使用 `read -t 0` 非阻塞轮询
- 鼠标事件必须及时消化以避免事件堆积
- 后台 keepalive 在 `interactive_mode` 启动后才启用

### 11.2 渲染性能

- TUI 重绘限制: 顶层每帧 < 50ms
- 状态条独立 tick（200ms）
- 封面图缓存（按 song_id 缓存 60s）

---

## 12. 错误处理

### 12.1 能力检测失败

- 图片协议未检测到 → 自动降级为 ASCII 封面
- 鼠标未启用 → 键盘可用
- Unicode 不支持 → 退化为 ASCII 字符

### 12.2 音质回退失败

- 所有音质都失败 → 标记为 `---` 并跳过
- UI 显示警告："该歌曲无可用音质"

### 12.3 终端信号

- `trap on_exit INT TERM`
- on_exit:
  - `\033[?1006l` 关闭鼠标
  - `\033[?25h` 显示光标
  - `\033[?1049l` 退出备用屏幕
  - `stty sane` 恢复终端状态

---

## 13. 测试策略

### 13.1 自动化测试

- **shellcheck**: 所有新增文件必须 0 warning
- **unit**: bash 函数级测试（mock state 测试渲染输出）
- **集成**: 模拟输入事件流，验证状态机

### 13.2 终端测试矩阵

| 终端 | 图片 | 鼠标 | 真彩色 | Unicode |
|------|------|------|--------|---------|
| kitty | ✓ | ✓ | ✓ | ✓ |
| iTerm2 | ✓ | ✓ | ✓ | ✓ |
| Alacritty | ✗ | ✓ | ✓ | ✓ |
| WezTerm | ✓ | ✓ | ✓ | ✓ |
| xterm | ✗ | ✓ | ✗ | ✗ |
| Linux tty | ✗ | ✗ | ✗ | ✗ |

### 13.3 音质回退测试

- mock 源返回不同 HTTP 状态码验证回退链
- 验证最终选定的音质级别

---

## 14. 风险与缓解

| # | 风险 | 影响 | 缓解措施 |
|---|------|------|----------|
| 1 | Bash TUI 性能瓶颈 | 大量输入时卡顿 | 后台 read + 显示更新节流（>50ms） |
| 2 | 鼠标协议兼容性 | 老终端不响应 | 严格用 SGR 1006，启用条件检测 |
| 3 | 各终端图片协议差异 | 部分终端图不显示 | 三协议自动降级 |
| 4 | 现有用户升级后 UI 改变 | 习惯打乱 | UI_TUI=off 时 100% 保持 v1.x 行为 |
| 5 | 真实 API 复杂度 | kugou/qq 等需要签名 | 先支持 netease 完整流程，作为模板 |
| 6 | Bash 浮点限制 | 进度计算精度 | 用整数百分比 |
| 7 | 终端 resize | 布局错乱 | 监听 SIGWINCH，重新计算 cols/lines |

---

## 15. 实施阶段（不展开）

实施计划将在 `writing-plans` 阶段生成，包含：
- **阶段 1**: `lib/capability.sh` + 检测函数单元测试
- **阶段 2**: `lib/input.sh` + SGR 鼠标解析
- **阶段 3**: `lib/tui.sh` + 简化分栏布局
- **阶段 4**: `sources/_base.sh` 回退逻辑
- **阶段 5**: `sources/netease.sh` 真实实现重写
- **阶段 6**: 其他源的真实实现（如技术可行）
- **阶段 7**: 集成 + 端到端测试
- **阶段 8**: 文档 + AUR 升级 + 发布

---

## 16. 成功标准

v2.0 完成时满足：

1. ✅ kitty 终端检测到 → 自动启用 TUI + 封面
2. ✅ 鼠标点击列表项可播放
3. ✅ 滚轮滚动列表
4. ✅ 网易云源完整支持（搜索 + 多音质播放）
5. ✅ 默认音质 flac，回退至 320/128 透明
6. ✅ 现有 v1.1.1 用户升级零迁移
7. ✅ shellcheck 0 warning / namcap 0 warning
8. ✅ AUR 包成功发布 v2.0

---

## 17. 已知限制

1. **真实 API 集成成本高**: kugou/qq 等需要加密签名，纯 bash 实现困难
   - **缓解**: 优先确保 netease 完美，kugou 等提供"占位 + 提示"实现

2. **Bash 性能上限**: 复杂 TUI 渲染在低性能机器上不够流畅
   - **缓解**: 渲染节流（re-render > 50ms 跳过）

3. **不同终端能力差异**: 100% 覆盖所有终端不可行
   - **缓解**: 三档布局降级 + ASCII fallback

---

## 附录 A: 关键决策摘要

| 决策项 | 选择 | 原因 |
|--------|------|------|
| TUI 技术栈 | 纯 Bash + 检测增强 | 不破坏现有安装 |
| 能力启用方式 | 自动检测即启用 | 用户零配置 |
| TUI 布局 | 简化分栏（D） | 简单清晰 |
| 音质策略 | 固定偏好 + 回退链 | 最简单实用 |
| 输入方式 | 键盘+鼠标同权 | 体验最完整 |
| 文件结构 | 新增 lib/capability.sh/tui.sh/input.sh | 模块化 |
| 配置兼容 | 仅追加新配置项 | 向后兼容 |

---

**文档结束**
