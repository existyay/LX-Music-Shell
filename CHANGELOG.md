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
- 歌词显示功能 (/lyric 命令)
- 播放队列管理 (/queue 命令)
- 真实搜索端点集成 (依赖完整 lxserver 用户)

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