# Arch Linux AUR 安装指南

## 方式一: 从 AUR 安装 (推荐)

### 1. 使用 yay

```bash
# 安装 yay (如果还没有)
sudo pacman -S yay

# 安装 lx-music-shell
yay -S lx-music-shell
```

### 2. 使用 pacman 和 makepkg

```bash
# 克隆 AUR 仓库
git clone https://aur.archlinux.org/lx-music-shell.git
cd lx-music-shell

# 构建并安装
makepkg -si
```

## 方式二: 使用 PKGBUILD 构建

### 标准 PKGBUILD

```bash
# 下载 PKGBUILD
wget https://raw.githubusercontent.com/yourname/lx-music-shell/main/aur/PKGBUILD

# 或克隆整个仓库
git clone https://github.com/yourname/lx-music-shell.git
cd lx-music-shell/aur

# 编辑 PKGBUILD (可选)
nano PKGBUILD

# 构建包
makepkg -s

# 安装
sudo pacman -U lx-music-shell-*.pkg.tar.zst
```

## 方式三: 一键安装脚本

```bash
git clone https://github.com/yourname/lx-music-shell.git
cd lx-music-shell
chmod +x install-aur.sh
./install-aur.sh
```

## 依赖

### 必需依赖
- bash >= 4.0
- curl
- grep
- sed
- awk

### 可选依赖
- mpv (默认播放器后端)
- mplayer (替代播放器)
- jq (JSON 解析支持)

安装所有依赖:
```bash
sudo pacman -S bash curl grep sed awk mpv jq
```

## 安装后配置

### 首次运行
```bash
lx-music-shell
```

### 配置位置
- 主配置: `~/.config/lx-music-shell/config`
- 源配置: `~/.config/lx-music-shell/sources.list`
- 缓存: `~/.cache/lx-music-shell/`

### 测试安装
```bash
lx-music-shell --version
lx-music-shell --test-sources
```

## 卸载

```bash
# 如果是 AUR 安装
yay -R lx-music-shell

# 或 pacman
sudo pacman -R lx-music-shell

# 配置文件可以手动删除
rm -rf ~/.config/lx-music-shell
```

## 常见问题

### Q: 提示 "命令未找到"
A: 确保 `~/.local/bin` 在 PATH 中，或重新登录终端

### Q: 播放器不工作
A: 安装 mpv: `sudo pacman -S mpv`

### Q: 源连接失败
A: 使用 `/update-sources` 更新源配置
