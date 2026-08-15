# LX-Music-Shell

一个纯 Shell 编写的开源音乐 Shell 客户端，支持多个音乐源，可在终端播放音乐。

## 功能特点

- 🎵 **多源支持**: 网易云(真实) / 酷狗、酷我、QQ音乐、咪咕(聚合 API)
- 🖥️ **TUI 界面**: go-musicfox 风格终端界面 (kitty/iTerm/WezTerm 等)
- 🖱️ **键盘+鼠标双输入**: vim 风格键盘 + SGR 鼠标点击/滚轮/进度条拖拽
- 🔍 **真实搜索**: 网易云直连真实搜索 + 歌词 + 封面
- 🎤 **实时歌词**: bash 原生 LRC 解析, 逐行高亮
- 📊 **频谱可视化**: 随播放跳动 (纯 bash 动画)
- ⏯️ **真实播放控制**: mpv JSON IPC, 真实进度/暂停/seek/音量
- 🔄 **播放模式**: 列表播放、列表循环、单曲循环、随机播放
- 🎚️ **音质保底**: hires → flac → 320 → 128 回退链
- 📡 **网络监控**: 网络断线后自动重连并续播
- 📦 **Arch Linux AUR**: 可直接通过 yay/pacman 安装和卸载

## 支持的音乐源

| 源 | 命令关键字 | 状态 |
|---|---|---|
| 酷狗音乐 | kugou | ✅ |
| 酷我音乐 | kuwo | ✅ |
| QQ音乐 | qq | ✅ |
| 网易云音乐 | netease | ✅ |
| 咪咕音乐 | migu | ✅ |
| 喜马拉雅 | ximalaya | ✅ |

## 依赖

### 必需依赖
- bash >= 4.0
- curl
- grep
- sed
- awk

### 推荐依赖
- mpv (推荐，通过 JSON IPC 实现真实播放控制)
- python3 (URL 编码 / mpv IPC 客户端 / 歌词)
- ffmpeg (含 ffplay，替代播放器)

安装所有依赖:
```bash
sudo pacman -S bash curl grep sed awk mpv python3 ffmpeg
```

## 快速开始

### TUI 模式 (推荐, 鼠标+键盘)
```bash
lx-music-shell --tui
# 或无参数自动检测终端能力后进入 TUI
lx-music-shell
```

### 命令行模式
```bash
# 搜索
lx-music-shell --search "周杰伦"

# 测试所有源
lx-music-shell --test-sources

# 更新源配置
lx-music-shell --update-sources
```

## TUI 操作

```
键盘 (vim 风格):
  ↑↓ / jk     移动选择
  Enter       播放选中 / 确认菜单
  Space       播放/暂停
  /           搜索 (输入关键词后 Enter 确认)
  n / p       下一首 / 上一首
  m           循环播放模式
  s           切换音源
  c           切换音质
  + / -       音量
  g / G       列表顶部 / 底部
  Esc         返回菜单
  q           退出

鼠标:
  点击列表项   播放该歌曲
  点击菜单项   进入/确认
  点击搜索框   聚焦输入
  点击进度条   跳转到该时间点
  点击播放栏   暂停 (左) / 下一首 (右)
  滚轮         滚动列表
```

## 交互命令

```
播放控制:
  /play [n], /p [n]    播放 (第n首)
  /pause               暂停
  /resume, /r          继续播放
  /stop                停止
  /next, /n            下一首
  /prev                上一首

列表管理:
  /list, /l            显示播放列表
  /clear               清空播放列表
  /mode [mode]         播放模式 (list/loop/single/random)
  /volume [n]          设置音量 (0-100)

搜索播放:
  /search [关键词], /s 搜索音乐
  /source [源名]       切换音乐源

音乐源: kugou, kuwo, netease, qq, migu, ximalaya, all

系统:
  /test-sources        测试源连通性
  /update-sources      更新源配置
  /import-source <f>   导入源配置
  /status              显示状态
  /config              显示配置
  /help, /h            显示帮助
  /quit, /q            退出
```

## 安装

### Arch Linux (AUR) - 推荐

```bash
# 使用 yay
yay -S lx-music-shell

# 或使用 pacman + makepkg
git clone https://aur.archlinux.org/lx-music-shell.git
cd lx-music-shell
makepkg -si
```

### 一键安装脚本

```bash
git clone https://github.com/yourname/lx-music-shell.git
cd lx-music-shell
chmod +x install-aur.sh
./install-aur.sh
```

### 通用安装

```bash
git clone https://github.com/yourname/lx-music-shell.git
cd lx-music-shell
chmod +x install.sh
./install.sh
```

## 卸载

### 使用 pacman/yay (推荐)

```bash
# 仅卸载包 (保留配置)
sudo pacman -R lx-music-shell
yay -R lx-music-shell

# 卸载及依赖 (推荐)
sudo pacman -Rns lx-music-shell
yay -Rns lx-music-shell
```

### 使用卸载脚本

```bash
# AUR 安装版本
sudo lx-music-shell-uninstall

# 手动安装版本
./uninstall.sh
```

卸载脚本会询问是否保留用户配置。

### 手动清理 (完整)

```bash
# 卸载包
sudo pacman -Rns lx-music-shell

# 删除用户配置
rm -rf ~/.config/lx-music-shell
rm -rf ~/.cache/lx-music-shell
rm -rf ~/.local/share/lx-music-shell
rm -rf ~/Music/LX-Music-Shell
```

## 配置文件

- 主配置: `~/.config/lx-music-shell/config`
- 源配置: `~/.config/lx-music-shell/sources.list`
- 缓存: `~/.cache/lx-music-shell/`
- 数据: `~/.local/share/lx-music-shell/`
- 下载音乐: `~/Music/LX-Music-Shell/`

## 自定义音乐源

编辑 `~/.config/lx-music-shell/sources.list`:

```bash
# 示例：添加自定义源
SOURCE_CUSTOM="https://api.example.com/search"
```

或使用内置命令导入:
```bash
/import-source /path/to/sources.list
```

## 播放器后端

支持多种播放器后端，按优先级自动选择:

1. **mpv** (推荐) - 高品质播放，低资源占用
2. **ffplay** (ffmpeg) - 功能丰富
3. **mplayer** - 经典播放器

配置文件设置:
```bash
PLAYER_BACKEND="mpv"
```

## 开发

```bash
# 语法检查
bash -n lx-music-shell

# 测试源连通性
./lx-music-shell --test-sources

# 更新源
./sources-update.sh
```

## 许可证

MIT License

## 致谢

- [LX-Music-Desktop](https://github.com/lyswhut/lx-music-desktop) - 桌面音乐播放器
- [go-music-fox](https://github.com/soiqualang/go-music-fox) - Go 语言音乐客户端