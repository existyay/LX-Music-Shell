# LX-Music-Shell 更新日志

所有显著的更改都将记录在此文件中。版本遵循 [Semantic Versioning](https://semver.org/) 规范。

## 版本发布规则

- **Patch (小版本)**: bug 修复、代码优化、文档更新 (例如 2.0.0 → 2.0.1)
- **Minor (中版本)**: 新功能、非破坏性变更 (例如 2.0.x → 2.1.0)
- **Major (大版本)**: 重大变更、破坏性 API 变更 (每 10 次小版本后)

**频率建议**:
- 小版本：每完成 1-3 个 bug 修复就发布
- 中版本：每完成 1-2 个功能就发布
- 大版本：每 10 次小版本（即累计 10 次迭代）

## [未发布]

### 计划中
- 更多音源真实搜索端点 (依赖完整 lxserver 用户)
- 播放队列管理 (/queue 命令)
- 桌面歌词 (desktop lyrics)

---

## [3.13.1] - 2026-08-16

### 修复 (Patch)

- 修复正在播放页封面未走真实封面渲染的问题
- 封面渲染统一优先使用 ffmpeg 半块真彩 (bilibili-tui 同款 fallback)
- 调整播放页封面尺寸与歌曲信息行位置, 避免重叠

---

## [3.13.0] - 2026-08-16

### 新增 (Minor)

- 封面显示方案参考 bilibili-tui: Kitty 原生图形协议 + 其他终端 ffmpeg 半块真彩渲染
- 新增 lib/cover_render.py: ffmpeg 解码 + ANSI 24bit 半块字符 (▀) 显示真实封面
- 非 Kitty 终端也能看到封面, 不再只是 ASCII 占位

---

## [3.12.0] - 2026-08-16

### 新增/修复 (Minor)

- MPRIS 状态栏与软件完全同步: 桌面控制可 播放/暂停/下一首/上一首/停止
- 桌面控制可切换播放模式 (list/loop/single/random)
- 软件播放模式/歌曲/状态变化会实时写回 MPRIS
- 修复旧 mpris_bridge 进程占用 D-Bus 名称导致新桥接不生效的问题 (通过 stop 清理)

---

## [3.11.1] - 2026-08-16

### 修复 (Patch)

- 修复窗口 resize 后不实时重绘的问题 (SIGWINCH 触发 dirty)
- 修复 COLUMNS/LINES 缓存导致 resize 后尺寸不更新
- 开屏动画不再打印换行, 退出后普通屏幕无加载动画残留

---

## [3.11.0] - 2026-08-16

### 新增/修复 (Minor)

- TUI 布局按窗口高度自适应: 歌词/提示根据可用行数显示或隐藏
- 显式 --tui 不再因窗口小于 20 行而退回 CLI, 小窗口也能用 TUI
- 菜单行距自适应, 小窗口不裁切菜单项
- 修复窗口较小时 q 无法退出 TUI 的问题

---

## [3.10.2] - 2026-08-16

### 修复 (Patch)

- 修复 LRC 歌词时间含 08/09 等前导零时被当作八进制导致算术报错
- 歌词解析改用 10# 显式十进制, 兼容所有前导零时间标签

---

## [3.10.1] - 2026-08-16

### 修复 (Patch)

- 修复主菜单在 9 项且终端行数较小时底部项被裁切的问题
- 菜单自动切换单/双行间距, 鼠标区域同步
- 歌单结果列表标签预留安全宽度, 避免方向键移动时折行

---

## [3.10.0] - 2026-08-16

### 新增 (Minor)

- 搜索框支持完整光标操作: 左右移动/Home/End/退格/Delete
- 搜索框光标可视化 (▏), 插入和删除更直观
- 新增 Delete 键事件解析 (ESC[3~)
- 覆盖性测试新增搜索框光标操作与 Delete 键解析

---

## [3.9.0] - 2026-08-16

### 新增/修复 (Minor)

- TUI 鼠标统一启用 (SGR 1006), 不再依赖能力探测结果, 提升兼容性
- 终端标题与当前播放同步, 停止后清空
- 清理上一首未完成的封面/歌词后台任务, 避免 curl 堆积
- 覆盖性测试新增: 进度条无字面量转义、歌词提前显示、鼠标点击
- 状态栏同步: TUI 底栏/CLI 状态栏/终端标题一致显示当前播放

---

## [3.8.1] - 2026-08-16

### 修复 (Patch)

- 修复进度条百分比前出现字面量 \033[1m 残留的问题 (改用 T_BOLD 真转义)
- 修复歌词在播放位置早于第一句时显示"暂无歌词"的问题, 现在显示第一句
- 歌词/封面拉取完成后可正常渲染

---

## [3.8.0] - 2026-08-16

### 修复 (Patch)

- 修复封面/歌词后台拉取因子 shell 变量不回流导致封面不显示的问题
- 封面/歌词改为写缓存文件 + ready 标记, 主循环检测后渲染
- 修复提示行/歌词/播放页文本超宽折行导致的菜单错行
- 所有渲染文本统一按终端宽度截断, 避免乱行/错行

---

## [3.7.0] - 2026-08-16

### 新增/修复 (Minor)

- 歌单搜索后使用专用结果页: 左侧列表 + 右侧预览 (名称/歌曲数/播放量/封面地址)
- 歌单封面地址已获取, 播放页/结果页展示封面占位与信息
- 选择歌单后自动加载全部歌曲到播放列表并播放
- 修复搜索框/菜单/选择项文本过长导致折行成两行的问题
- 统一截断所有列表项和输入框, 提升稳定性

---

## [3.6.0] - 2026-08-16

### 新增 (Minor)

- 新增 MPRIS D-Bus 桥接: 桌面环境可识别 lx-music-shell 为活动媒体播放器
- 支持桌面媒体键 播放/暂停/停止/上一首/下一首/Seek
- 上报歌曲标题/歌手/专辑/封面/时长/播放位置/音量
- 依赖 (可选): python-dbus, python-gobject; 未安装时自动跳过不影响播放

---

## [3.5.0] - 2026-08-16

### 新增 (Minor)

- 新增「正在播放」展示页: 歌曲封面(ASCII/kitty) + 歌名/歌手/专辑/来源/音质/作曲占位
- 从搜索结果播放后自动进入正在播放页
- 菜单新增「正在播放」, 快捷键 `i` 可随时打开
- 展示页包含现代居中排布和封面盒设计

---

## [3.4.0] - 2026-08-16

### 新增/变更 (Minor)

- 移除 TUI 音源切换选项, 搜索歌曲/歌单播放改为自动匹配可用源
- 自动搜索: 并行测试所有内置源 + yinyuan/自定义源, 无感聚合结果
- 播放失败自动回退: 当前源无法解析时, 自动搜索同名歌曲并切换到可用源
- 所有 yinyuan 内嵌源均参与自动匹配, 无需手动切换
- 测试/切换过程无可见提示, 对用户透明

---

## [3.3.0] - 2026-08-16

### 新增 (Minor)

- **双缓冲渲染**: 每帧先完整生成再一次性输出, 基本消除播放/切换时的闪屏
- **搜索歌单**: TUI 新增「搜索歌单」菜单, CLI 新增 `/playlist <关键词>`
- **歌单加载**: 选择歌单后加载歌曲到播放列表, CLI 支持 `/load-playlist <歌单ID>`
- **今日推荐**: TUI 菜单与 CLI `/recommend` 加载网易云今日推荐新歌
- **实时状态栏**: `/statusbar` 变为可开关的实时状态栏, 显示当前播放歌曲/进度
- 菜单项扩展为 9 项: 搜索音乐 / 搜索歌单 / 今日推荐 / 播放列表 / 切换音源 / 切换音质 / 播放模式 / 帮助 / 退出

---

## [3.2.1] - 2026-08-16

### 优化/修复 (Patch)

- TUI 渲染时缓存终端尺寸, 单帧内不再重复调用 tput
- 播放器状态轮询由每 0.2s 降为约 0.6s, 降低 python 子进程开销
- 播放栏使用分隔线重新排布 (模式 │ 音量 │ 状态 │ 曲目)
- 帮助页快捷键描述修正: c 切换音质, q/Esc/Ctrl-C 退出
- 后台播放退出 TUI 时输出提示空行, 避免和后续 shell 提示粘连

---

## [3.2.0] - 2026-08-16

### 新增/优化 (Minor)

- **后台播放**: 退出 TUI/CLI 后音乐继续播放; 自动保存播放器状态, 下次启动可接管控制
- 新增 CLI 命令 `--stop` / `--pause` / `--resume` / `--status`, 用于控制后台播放
- **防闪屏**: TUI 改为状态/进度变化时重绘, 无变化不再每帧全屏重绘
- **现代进度条**: 当前时间 + 渐变细进度条 (▰/▱) + 总时长 + 百分比
- 播放栏在后台播放且无播放列表时回退显示当前曲目
- 播放器启动使用 nohup + stdio 重定向, 确保退出后不被 SIGHUP 杀掉

---

## [3.1.2] - 2026-08-16

### 新增/完善 (Patch)

- TUI 音源切换改为独立选择子菜单: 列出真实可用音源 (内置 + 自定义), Enter 确认并持久化
- TUI 音质切换改为独立选择子菜单: HiRes / FLAC / HQ / SQ 明确可选并持久化
- 播放列表轨道增加来源列 (10 列), 切换音源后旧结果仍按原来源解析播放
- 新增 CLI `/quality [hires|flac|320|128]` 与 `--quality` 命令
- `/source <name>` 切换后立即生效并写入配置, 同时更新当前源显示名
- `save_config` 完整持久化音质/回退模式/TUI/网络/API 等所有运行配置
- 切换音源/音质/播放模式后自动保存, 重启后保持

---

## [3.1.1] - 2026-08-16

### 修复 (Patch)

- 修复 TUI 中 Enter 键无响应 (`read -n1` 对换行符返回空变量导致 Enter 被丢弃)
- 修复单独 ESC 键被解析为普通字符, 搜索框无法返回菜单
- 修复 Ctrl-C/TERM 信号只清理不退出, 导致 Kitty 中 UI 看似卡死
- 修复屏幕切换/列表缩短后旧行残留造成的界面乱码
- 移除 TUI 实时频谱动画, 改为仅开屏加载动画 (ASCII 帧, 避免乱码)
- 播放状态栏/状态页改用 mpv IPC 真实进度 (time-pos/duration), 不再用墙钟估算
- UI 源名统一显示中文, 不再显示内部英文 id (如 netease)
- 修复自定义 yinyuan 音源启动时未加载的问题 (load_modules/load_sources 顺序)
- 退出时清理后台网络监控/状态栏任务, 避免退出后残留写终端
- TUI 切源循环覆盖自定义音源

---

## [3.1.0] - 2026-08-16

### 新增 (Minor)

#### 音源管理 (yinyuan)
- 新增 `lib/yinyuan.sh`: 用户自定义音源自动添加 + 管理
- 音源存储在 `~/.config/lx-music-shell/yinyuan/` 目录, **混淆加密** (XOR + base64),
  不落盘明文 URL (规避版权/敏感 URL 风险)
- 三种添加方式:
  1. 直接输入搜索 URL (`/source add <name> <url>`)
  2. 输入 **GitHub 链接** 自动拉取配置 (`/source add <name> <raw-url>`,
     支持纯文本 URL 或 `{"search_url":"..."}` JSON)
  3. **选择式** (`/source select`): 内置精选源列表, 选中后输入 URL/链接
- `yinyuan/` 已列入 `.gitignore`, 不上传到 GitHub
- 启动时自动从 yinyuan 解混淆加载音源到内存 (不落盘明文)

---

## [3.0.2] - 2026-08-16

### 修复 (Patch)

- **修复鼠标控制序列被打印成可见文本**: `_input_write_tty_or_stdout` 用 `printf '%s'`
  输出单引号字符串 `'\033[?1006h'` (字面 `\033` 而非 ESC 字节), 导致:
  1. 鼠标报告从未真正启用 (终端收到的是字面文本)
  2. 退出后屏幕上残留 `\033[?1006h\033[?1002h` 字面文本
  修复: 改用 `printf '%b'` 解释转义, 现在输出真正的 ESC 字节



## [3.0.1] - 2026-08-16

### 修复 (Patch)

- **消除 TUI 闪屏**: 逐帧渲染不再做 `\033[2J` 全屏清屏, 改为光标归位 + 逐行清行,
  仅在终端 resize (SIGWINCH) 时全屏清屏一次, 消除刷屏闪烁
- **恢复自定义音源**: `/source add <name> <url>` 添加的自定义源现在可真实搜索
  (泛化 JSON 解析, 兼容 LX-Music 协议 / iTunes 等常见格式), 不再只显示预览
- **自定义源直接播放**: 若 song_id 本身是可播放 URL (某些自定义源直接返回), 直接播放
- 内置源 (netease/kugou/kuwo/qq/migu) 与自定义源正确区分, 不再互相覆盖



## [3.0.0] - 2026-08-16

### 重构 (Major Architecture Overhaul)

#### 真实播放 (mpv JSON IPC 后端)
- 新增 `lib/mpv_ipc.py` (纯 python3 客户端, 无 socat/nc 依赖)
- 新增 `lib/player.sh` 后端: 真实进度/时长 (time-pos/duration)、
  真实暂停/继续 (pause 属性)、seek、音量 (volume 属性)、曲目结束 (eof-reached)
- 取代旧的 `kill -STOP/-CONT` + 墙钟计时 (进度不再靠猜)

#### 统一 TUI (单一状态机)
- 重写 `lib/tui.sh`: 屏幕状态机 (menu/search/help)
- 完整 go-musicfox 视觉: 顶红标题线 / 副标题 / 菜单 / 结果列表 /
  歌词 (bash 原生 LRC 解析) / 频谱 (纯 bash 动画) / 播放栏 / 真实进度条
- 删除冗余 `lib/tui_fox.sh` (与 tui.sh 合并)

#### 键盘 + 鼠标双输入
- vim 风格键盘: j/k/g/G/Enter/Space/n/p/m/s/c/+/-/q
- SGR 1006 鼠标: 点击列表播放 / 点击菜单 / 点击搜索框聚焦 /
  点击进度条 seek / 点击播放栏暂停切歌 / 滚轮滚动
- 修复鼠标移动误判为点击的 bug (SGR button bit 5 过滤)

#### 网易云真实源
- 新增 `sources/netease.sh`: 真实搜索 (实测可用)、真实歌词、
  封面 (img1v1Url)、播放 URL (尽力而为, 版权曲目受限)
- 默认音源改为 netease (原先 kugou 默认走已失效的公益 API)

#### 打包修复
- PKGBUILD / install.sh 现在安装 `lib/` 与 `sources/` 到 `/usr/share/lx-music-shell/`
  (此前 AUR 安装后 TUI 模块缺失)

#### 测试
- 新增 `tests/test_player.sh` (mpv IPC 集成, 11 断言)
- 重写 `test_tui.sh` (44 断言) / `test_playlist.sh` (10 断言)
- 更新 `test_input.sh` (q/Q 改为 KEY_CHAR, 鼠标移动过滤)
- shellcheck 0 error / 0 warning



## [2.3.0] - 2026-07-28

### 重构 (Major UI Overhaul)

#### Fox-style TUI - 完整复现 go-musicfox 视觉

参考项目本地化深魔入:
- references/go-musicfox/internal/ui/cover_renderer.go (封面渲染)
- references/go-musicfox/internal/ui/lyric_renderer.go (歌词渲染)
- references/go-musicfox/internal/ui/song_info_renderer.go (播放栏)
- references/go-musicfox/internal/ui/menu_main.go (主菜单)
- references/go-musicfox/internal/ui/layout_const.go (布局常量)

新增 lib/tui_fox.sh (411 行):
- 顶部水平红线: 行 1 ── musicfox ── (logo 可配置)
- 副标题区: 行 2 显示用户昵称或 [未登录]
- 主菜单: 16 项 Fox-style 入口 (搜索/我的歌单/专辑/榜单/精选歌单/
  热门歌手/最近播放/云盘/主播电台/私人FM/账号/收藏/每日推荐/帮助/检查更新)
- 双列布局 (cols >= 88), 单列布局 (cols < 88)
- 选中项: => N. 标题 红色加粗
- 歌词区: 5 行居中 (与 go-musicfox 一致, CompactLyricLines=3, FullLyricLines=5)
- 底部播放栏: [模式] 音量% ♫ ♪ ♫ ♪ ♥ 歌名 歌手
- 进度条: █▰▰▱▱ + mm:ss/mm:ss (已播/总时长)

新增 lib/lyric.py (290 行, python3):
- LRC 标准解析: [mm:ss.xx]text
- YRC 逐字解析: [mm:ss.xx]<start,duration>字</start>字...
- smooth/wave/glow 三种渲染模式
- CJK=2 / ASCII=1 字符宽度 (unicodedata.east_asian_width)
- 100ms 粒度缓存 (与 go-musicfox lyricCacheKey 一致)

新增交互入口:
- lx-music-shell --fox 启动 Fox-style TUI
- UI_FOX=on 配置项设置后自动选用新 TUI

#### 技术变更

多语言混合架构:
- bash: 主循环/键盘事件/菜单导航/mpv 控制/ANSI 渲染/Kitty 协议
- python3: LRC/YRC 歌词解析与渲染 (未来: 频谱数据处理, 封面下载重采样)
- 通信: stdin/stdout JSON (2ms 子进程启动 + 100ms 缓存避免频繁调用)

行为改进:
- interactive_mode_fox 新增函数 (与 interactive_mode_tui 并存)
- interactive_mode 退出时还原终端状态 (备屏关闭 + 光标显示 + 鼠标禁用)
- EOF 检测: stdin 不是 tty 时自动退出 TUI 循环
- LXMS_PLAYLIST 访问改为 set-u 安全 (使用 +set 检测代替默认值语法)

#### 测试增强
- tests/test_fox.sh (39 断言): 字符宽度/填充/截断/菜单/渲染/
  双列布局/python3 集成/危险模式扫描/vim 操作
- 全部测试套件 144/144 通过 (capability 13 + fox 39 + input 33 +
  playlist 11 + sources 13 + tui 35)
- shellcheck 0 errors / namcap 0 warnings

---

## [2.2.1] - 2026-07-28

### 修复 (Critical)
- **add_to_playlist 运行时错误**: `local IFS='|' read -r ... <<< "$track"`
  是非法结构 — local 会把 `read`/`-r` 当作变量名声明,
  运行时抛出 `local: "-r": 不是有效的标识符`, read 从未执行,
  导致 LXMS_PLAYLIST 同步为空字段 (TUI 列表无歌名/歌手)
  修复: 先 `local _idx name artist duration song_id` 声明,
  再用 `IFS='|' read -r ...` 环境前缀形式调用
- 新增 tests/test_playlist.sh 回归测试 (12 断言):
  字段同步/无运行时错误/全项目危险模式静态扫描/clear_playlist 同步

## [2.2.0] - 2026-07-27

### 重构 (Major UI Overhaul)

#### TUI 完全重设计

参考项目:
- [references/go-musicfox](https://github.com/go-musicfox/go-musicfox) - vim-style 键盘映射
- [references/bilibili-tui](https://github.com/MareDevi/bilibili-tui) - 图片协议 + 多区块布局

新设计:
1. vim-style 键盘接口
   - jk = 上下 (仿 vim)
   - gg/G = 顶/底
   - Space = 播放/暂停
   - [/] = 上一首/下一首
   - +- = 音量
   - / = 搜索
   - p = 切换播放模式
   - q = 退出
2. 多区块响应式布局
   - cols >= 100: 左右分栏 (列表/详情)
   - cols < 100: 上下堆叠
3. 多主题 (dark/green/light/mono) 配置项 UI_THEME
4. 封面自动处理: kitty / iTerm2 / Sixel / ASCII fallback
5. 顶部动态状态条
   - 标题 + 网络状态 + 音量条
6. 底部帮助提示行
   - 动态按键提示
7. vim-style 操作接口 (tui_op_* 函数)
   - tui_op_move_up / move_down / move_top / move_bottom / play_selected / rerender / quit / back
   - 主事件循环调用这些函数统一处理

#### 技术变更
- add_to_playlist 同时同步到 LXMS_PLAYLIST (9字段格式)
- clear_playlist 同时清空 LXMS_PLAYLIST
- lx-music-shell--tui 现以 vim 风格交互
- TUI 状态变量以 LXMS_ 为前缀 (与 PLAYLIST 区分)

#### 测试增强
- test_tui.sh 重写: 7 个测试场景 35 个断言
  - 主题切换 (4)
  - vim 风格操作 (6)
  - 状态条 (4)
  - 搜索框 (2)
  - 列表 (6 含空白验证)
  - 详情 (5)
  - 封面占位符 (2)
  - 完整渲染 (5 含宽/窄屏)
- 元余接口 (tui_op_quit 返回 2 等)

### 参照项目 (本地使用, 未提交)
- [references/go-musicfox] - 键盘映射参考
- [references/bilibili-tui] - 图片渲染参考
- 均加入 .gitignore 作为本地推导项目

### 修复
- lx-music-shell 中 SC1090/SC2034/SC2155 等 shellcheck 警告全部修复 (-o pipefail 模式下)
- load_modules 使用 declare -gA 保证全局可用
- add_to_playlist 拆装 9 列格式供 TUI 直接读取

---

## [2.1.0] - 2026-07-27

### 新增 (Minor)

#### LX-Music 聚合 API 客户端 (sources/lx_api.sh)
新增统一的 LX-Music 自定义源协议客户端,对接用户自建/公益的 LX-Music API 服务器
(如 lxmusicapi.onrender.com 或自建的 lx-server),通过统一协议解析 5 大音源的真实播放 URL。

特性:
- 配置项 (写入 ~/.config/lx-music-shell/config):
  - LX_API_URL  - API 服务器地址 (默认: https://lxmusicapi.onrender.com)
  - LX_API_KEY  - 访问令牌 (默认: share-v3)
  - LX_API_TIMEOUT - 请求超时秒 (默认: 15)
- 自动探测搜索端点可用性:
  - 完整 lxserver 用户:返回真实 API 搜索结果
  - 公益服务器 (lxmusicapi.onrender.com 等只提供 URL 解析): 
    自动回退到本地演示数据 (含真实 song_id)
- 5 大音源统一注册到源框架 (netease/kugou/kuwo/qq/migu)
- 通过 Huibq 风格 URL 端点 GET /url/{source}/{song_id}/{quality}
  支持音质保底链 (hires → flac → 320k → 128k)

#### do_play 集成 LX-Music API
播放时若 URL 为 null,v2.1.0 会自动:
1. 根据当前源 (netease/kugou/kuwo/qq/migu) 映射到 LX 协议源代码
2. 调用 source_base_get_play_url 走音质保底链解析
3. 返回真实的 http(s) URL 传给 mpv/mplayer/ffplay

#### do_search 智能参数识别
修复 `/search` 命令参数解析的多个 bugs:
- `/search 关键词 limit` (用默认源)
- `/search 关键词 源名 limit` (显式指定源)
- 之前 `/search 周杰伦 3` 被误解为 source="3"

#### search_mock 返回真实 song_id
mock 数据中每首歌都包含真实的 song_id (网易云 ID/酷狗 hash/酷我 rid/QQ songmid),
即使公益服务器不提供搜索端点,do_play 时仍能通过 LX-Music API 解析真实 URL。

### 变更
- 修复 .install hook 的 pkill -f 自杀问题导致 yay SIGTERM (v2.0.1 紧急修复)
- 删除独立的 sources/netease.sh (被 lx_api.sh 替代)
- 改用 ps -eo pid,comm | awk 精确匹配 lx-music-shell 进程
- 配置模板加入 LX_API_URL/LX_API_KEY/QUALITY_MODE/DEFAULT_QUALITY/UI_TUI/UI_MOUSE

### 验证
- 80/80 单元测试通过
- shellcheck 0 errors / namcap 0 warnings
- 6/6 源连通测试通过
- 实测 LX-Music API URL 解析成功返回真实 mp3 URL

---

## [2.0.0] - 2026-07-27

### 新增 (Major)

#### TUI 界面 (v2.0 核心功能)
- **简化分栏布局**: 顶部状态条 + 主区(列表+详情)
- **自适应布局**: cols>=100 左右分栏,cols<100 上下堆叠
- **封面图渲染**: 支持 kitty/iTerm2/sixel 三种协议,自动检测

#### 终端能力检测 (`lib/capability.sh`)
- 检测图片协议 (kitty / iTerm / sixel / none)
- 检测鼠标支持 (SGR 1006)
- 检测 Unicode / 真彩色 / 颜色深度
- 配置覆盖: `UI_TUI=off|on|auto`, `UI_MOUSE=off|on|auto`

#### 输入处理 (`lib/input.sh`)
- 键盘事件解析 (方向键/Enter/Tab/Space/Quit/等)
- SGR 鼠标协议解析 (单击/双击/滚轮/释放)
- 区域命中测试 (`input_register_region`/`input_mouse_to_action`)
- 鼠标双击检测 (500ms 时间窗口)

#### 音质保底 (`sources/_base.sh`)
- 音质回退链: hires → flac → 320 → 128
- 用户配置: `QUALITY_MODE=highest|balanced|fastest`, `DEFAULT_QUALITY`
- 标准源接口: `source_search`, `source_get_url`, `source_get_cover`

#### 网易云真实 API (`sources/netease.sh`)
- 真实搜索 API (`/api/search/get/web`)
- 多音质播放 URL (`/song/url?br=128000|320000|999000`)
- 封面获取 (`/api/v1/song/detail`)
- 歌词获取 (`/api/song/lyric`)

#### 主入口 (`lx-music-shell`)
- 新 `--tui` 参数, 显式启用 TUI 模式
- 新 `--cli` 参数, 显式启用 CLI 模式 (向后兼容)
- 新 `--tui-status` 参数, 显示终端能力检测结果
- 自动检测终端能力, TUI 不够走 CLI 兜底
- 退出时清理鼠标/光标/备屏, 防止终端状态污染

### 文档与建设
- 新增 `CHANGELOG.md`
- 新增 `tools/release.sh` 自动化版本发布脚本
- 新增完整测试套件 (80+ 单元测试): `tests/test_capability.sh`, `test_input.sh`, `test_tui.sh`, `test_sources.sh`
- 新增详细设计文档 (本地保留): `docs/superpowers/specs/`

### 修复 (Patch)
- 修复 `search_netease` 子 shell 中 `((i++))` 变量不传回导致歌曲序号全是 1
- 修复 `do_play` 中 `wait "$PLAYER_PID"` 在 PID 为空时的处理
- 修复 `DEFAULT_SOURCE` 自赋值默认值 bug
- 加固 `add_source` 中 `eval` 的 URL 格式验证
- 清理 `handle_network_loss` 重复计数逻辑
- `init_terminal` 改为显式 no-op
- 安装脚本现在安装所有 3 个 man 页面
- 关联数组在 sourced 环境下的关键 bug (用 `declare -gA` 解决)

### 文件
- 新增: `lib/capability.sh`, `lib/input.sh`, `lib/tui.sh`
- 新增: `sources/_base.sh`, `sources/netease.sh`
- 新增: `tests/test_capability.sh`, `test_input.sh`, `test_tui.sh`, `test_sources.sh`
- 新增: `tools/release.sh`, `CHANGELOG.md`
- 新增: `aur/lx-music-sources.1`, `aur/lx-music-shell-uninstall.1`
- 更新: `lx-music-shell`, `install.sh`, `uninstall.sh`, `sources-update.sh`, `aur/PKGBUILD`, `.gitignore`-

---

## [1.1.1] - 2026-07-27

### 修复 (Patch)

#### Bug 修复
- **search_netease 子 shell 序号 bug**: 修复 `while` 管道中 `((i++))` 变量不传回导致所有歌曲显示序号 1 的问题
- **do_play 中 PLAYER_PID race condition**: 在 `wait "$PLAYER_PID"` 前验证 PID 是数字
- **DEFAULT_SOURCE 自赋值默认值**: `${DEFAULT_SOURCE:-$DEFAULT_SOURCE}` 改为 `${DEFAULT_SOURCE:-kugou}`
- **eval 注入风险**: add_source 增加 URL 格式验证 (必须 http/https)
- **init_terminal 死代码**: 改用 `:` 显式 no-op 而不是 `true`
- **echo -n -e 顺序**: 改为 `printf '%b'`
- **handle_network_loss 重复计数**: 用 `for attempt in $(seq 1 ...)` 重构
- **sources-update.sh discover_api 未用参数**: 删除未使用的 source_url 参数

#### 代码质量
- 所有 shellcheck 警告已修复 (0 errors, 0 warnings)
- namcap PKGBUILD 检查通过 (0 errors, 0 warnings)
- 5 个 mock 搜索函数现在标注 "(演示数据)" 提示用户

#### 文档
- 添加专属 man pages: `lx-music-sources.1`, `lx-music-shell-uninstall.1`
- install.sh 现在安装全部 3 个 man 页面
- 添加 `tools/release.sh` 自动化发布脚本
- 添加 `CHANGELOG.md`

#### AUR
- 修复 Maintainer 字段 (之前是 "Demo User")
- AUR 包升级到 1.1.1

---

## [1.1.0] - 2026-07-26

### 新增
- 初始 AUR 提交
- 多源音乐搜索 (6 个中国音乐平台)
- 网络自动重连功能
- 实时状态栏
- 启动动画

---

## 如何升级版本

使用自动化脚本：

```bash
# 小版本 (1.1.1 → 1.1.2)
./tools/release.sh patch

# 中版本 (1.1.x → 1.2.0)
./tools/release.sh minor

# 大版本 (1.x.x → 2.0.0) - 每 10 次小版本
./tools/release.sh major

# 指定版本
./tools/release.sh 1.2.3
```

脚本会自动：
1. 更新 `lx-music-shell` 中的 `VERSION=`
2. 更新 `aur/PKGBUILD` 中的 `pkgver=` 和 `source=` URL
3. 重新生成 `aur/.SRCINFO`
4. 创建 git tag `v{VERSION}`
5. 提交所有变更
6. 推送到 GitHub (master + tag)
7. 推送到 AUR

## 链接

- GitHub: https://github.com/existyay/LX-Music-Shell
- AUR: https://aur.archlinux.org/packages/lx-music-shell
- Issues: https://github.com/existyay/LX-Music-Shell/issues

[未发布]: https://github.com/existyay/LX-Music-Shell/compare/v1.1.1...HEAD
[1.1.1]: https://github.com/existyay/LX-Music-Shell/releases/tag/v1.1.1
[1.1.0]: https://github.com/existyay/LX-Music-Shell/releases/tag/v1.1.0