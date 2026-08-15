#!/usr/bin/env bash
#==============================================================================
# LX-Music-Shell 安装脚本
#==============================================================================

set -e

# shellcheck disable=SC2034  # 版本变量,供未来更新检查使用
VERSION="3.0.1"
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

# 安装 TUI 模块和音乐源 (到 /usr/share/lx-music-shell)
echo "安装 TUI 模块和音乐源..."
SHARE_DIR="/usr/share/lx-music-shell"
mkdir -p "$SHARE_DIR/lib" "$SHARE_DIR/sources"
if [[ -d "$SCRIPT_DIR/lib" ]]; then
    cp -f "$SCRIPT_DIR"/lib/*.sh "$SCRIPT_DIR"/lib/*.py "$SHARE_DIR/lib/" 2>/dev/null || true
    echo "  ✓ lib -> $SHARE_DIR/lib"
fi
if [[ -d "$SCRIPT_DIR/sources" ]]; then
    cp -f "$SCRIPT_DIR"/sources/*.sh "$SHARE_DIR/sources/" 2>/dev/null || true
    echo "  ✓ sources -> $SHARE_DIR/sources"
fi

# 安装配置文件
echo "安装配置文件..."
if [[ ! -f "$CONFIG_DIR/config" ]]; then
    cat > "$CONFIG_DIR/config" << 'EOF'
# LX-Music-Shell 配置文件

# 播放器后端 (mpv/mplayer/ffplay)
PLAYER_BACKEND="mpv"

# 默认音乐源
DEFAULT_SOURCE="netease"

# 搜索结果数量限制
SEARCH_LIMIT="20"

# 自动更新源列表
AUTO_UPDATE_SOURCES="true"

# 播放模式 (list/loop/single/random)
PLAY_MODE="list"

# LX-Music 聚合 API 服务器 (用于解析 5 大音源真实 URL)
LX_API_URL="https://lxmusicapi.onrender.com"
LX_API_KEY="share-v3"
LX_API_TIMEOUT="15"

# 音质 (hires/flac/320/128) + 保底模式 (highest/balanced/fastest)
QUALITY_MODE="highest"
DEFAULT_QUALITY="flac"

# UI 模式 (auto/on/off)
UI_TUI="auto"
UI_MOUSE="auto"
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
for manpage in lx-music-shell.1 lx-music-sources.1 lx-music-shell-uninstall.1; do
    if [[ -f "$SCRIPT_DIR/aur/$manpage" ]]; then
        install -Dm644 "$SCRIPT_DIR/aur/$manpage" "$MAN_DIR/$manpage"
        echo "  ✓ man 页面 -> $MAN_DIR/$manpage"
    fi
done

# 设置 PATH（如果是用户级安装）
if [[ "$INSTALL_DIR" == "${HOME}/.local/bin" ]]; then
    SHELL_RC="${HOME}/.bashrc"
    if [[ -f "${HOME}/.zshrc" ]]; then
        SHELL_RC="${HOME}/.zshrc"
    fi
    
    if ! grep -q "export PATH=.*\.local/bin" "$SHELL_RC" 2>/dev/null; then
        {
            echo ""
            echo "# LX-Music-Shell"
            # shellcheck disable=SC2016  # 字面值,会在用户的 shell rc 中展开
            echo 'export PATH="$HOME/.local/bin:$PATH"'
        } >> "$SHELL_RC"
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
