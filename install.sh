#!/usr/bin/env bash
#==============================================================================
# LX-Music-Shell 安装脚本
#==============================================================================

set -e

VERSION="1.0.0"
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="${HOME}/.config/lx-music-shell"
MAN_DIR="/usr/local/share/man/man1"

echo "========================================"
echo "  LX-Music-Shell 安装脚本"
echo "========================================"
echo ""

# 检查是否以 root 权限运行
if [[ $EUID -ne 0 ]]; then
    echo "提示: 建议使用 sudo 运行此脚本以进行系统级安装"
    echo ""
    INSTALL_DIR="${HOME}/.local/bin"
    MAN_DIR="${HOME}/.local/share/man/man1"
fi

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "安装目录: $INSTALL_DIR"
echo "配置目录: $CONFIG_DIR"
echo ""

# 创建目录
echo "创建目录..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$CONFIG_DIR"
mkdir -p "$MAN_DIR"

# 安装主程序
echo "安装主程序..."
if [[ -f "$SCRIPT_DIR/lx-music-shell" ]]; then
    install -Dm755 "$SCRIPT_DIR/lx-music-shell" "$INSTALL_DIR/lx-music-shell"
    echo "  ✓ lx-music-shell -> $INSTALL_DIR/lx-music-shell"
else
    echo "  ✗ 错误: 找不到 lx-music-shell 脚本"
    exit 1
fi

# 安装配置文件
echo "安装配置文件..."
if [[ ! -f "$CONFIG_DIR/config" ]]; then
    cat > "$CONFIG_DIR/config" << 'EOF'
# LX-Music-Shell 配置文件

# 播放器后端 (mpv/mplayer/ffplay)
PLAYER_BACKEND="mpv"

# 默认音乐源
DEFAULT_SOURCE="kugou"

# 搜索结果数量限制
SEARCH_LIMIT="20"

# 自动更新源列表
AUTO_UPDATE_SOURCES="true"

# 播放模式 (list/loop/single/random)
PLAY_MODE="list"
EOF
    echo "  ✓ 创建配置文件: $CONFIG_DIR/config"
fi

if [[ ! -f "$CONFIG_DIR/sources.list" ]]; then
    cat > "$CONFIG_DIR/sources.list" << 'EOF'
# LX-Music-Shell 音乐源配置
# 格式: SOURCE_ID="API_URL"

# 酷狗音乐
SOURCE_KUGOU="https://www.kugou.com/yy/index.php"

# 酷我音乐
SOURCE_KUWO="http://www.kuwo.cn/api/www/search/searchMusicBykeyWord"

# QQ音乐
SOURCE_QQ="https://c.y.qq.com/soso/fcgi-bin/client_search_cp"

# 网易云音乐
SOURCE_NETEASE="https://music.163.com/api/search/get/web"

# 咪咕音乐
SOURCE_MIGU="https://music.migu.cn/v1/api/search/search"

# 喜马拉雅
SOURCE_XIMALAYA="https://www.ximalaya.com/revision/search"
EOF
    echo "  ✓ 创建源配置: $CONFIG_DIR/sources.list"
fi

# 安装 man 页面
if [[ -f "$SCRIPT_DIR/aur/lx-music-shell.1" ]]; then
    install -Dm644 "$SCRIPT_DIR/aur/lx-music-shell.1" "$MAN_DIR/lx-music-shell.1"
    echo "  ✓ man 页面 -> $MAN_DIR/lx-music-shell.1"
fi

# 设置 PATH（如果是用户级安装）
if [[ "$INSTALL_DIR" == "${HOME}/.local/bin" ]]; then
    SHELL_RC="${HOME}/.bashrc"
    if [[ -f "${HOME}/.zshrc" ]]; then
        SHELL_RC="${HOME}/.zshrc"
    fi
    
    if ! grep -q "export PATH=.*\.local/bin" "$SHELL_RC" 2>/dev/null; then
        echo "" >> "$SHELL_RC"
        echo "# LX-Music-Shell" >> "$SHELL_RC"
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$SHELL_RC"
        echo "  ✓ 添加 PATH 到 $SHELL_RC"
    fi
fi

echo ""
echo "========================================"
echo "  安装完成！"
echo "========================================"
echo ""
echo "运行方式:"
echo "  lx-music-shell          # 交互模式"
echo "  lx-music-shell --help   # 查看帮助"
echo "  lx-music-shell --test-sources  # 测试源连通性"
echo ""
echo "配置文件: $CONFIG_DIR/"
echo ""

# 提示安装依赖
echo "可选依赖（建议安装）:"
echo "  sudo pacman -S mpv mplayer jq curl"
echo ""
