# LX-Music-Shell

一个纯 Shell 编写的开源音乐 Shell 客户端，支持多个音乐源，可在终端播放音乐。

## 功能特点

- 🎵 **多源支持**: 酷狗、酷我、QQ音乐、网易云、咪咕、喜马拉雅
- 🔍 **搜索播放**: 支持各平台音乐搜索和播放
- 📋 **播放列表**: 本地播放列表管理，支持 M3U 导入导出
- 🔄 **播放模式**: 列表播放、列表循环、单曲循环、随机播放
- 🎚️ **音量控制**: 0-100% 音量调节
- ✅ **源连通性测试**: 一键测试所有音乐源连接状态
- 🔗 **源自动获取/导入**: 自动从网络获取最新源配置，支持导入外部源
- 🎨 **友好界面**: ASCII 艺术界面，色彩输出
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

### 可选依赖
- mpv (推荐，默认播放器)
- mplayer (替代播放器)
- ffmpeg (含 ffplay，替代播放器)
- jq (JSON 解析增强)

安装所有依赖:
```bash
sudo pacman -S bash curl grep sed awk mpv jq ffmpeg
```

## 快速开始

### 交互模式
```bash
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