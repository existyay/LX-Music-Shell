#!/usr/bin/env bash
#==============================================================================
# LX-Music-Shell 一键安装脚本 (Arch Linux)
#==============================================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  LX-Music-Shell 一键安装脚本${NC}"
echo -e "${BLUE}  (Arch Linux)${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 检查是否为 Arch Linux
if [[ ! -f /etc/arch-release ]]; then
    echo -e "${YELLOW}警告: 此脚本专为 Arch Linux 设计${NC}"
    echo "在其他发行版上可能需要手动调整"
fi

# 检查依赖
echo -e "${YELLOW}检查依赖...${NC}"
MISSING_DEPS=()

check_dep() {
    if ! command -v "$1" &>/dev/null; then
        MISSING_DEPS+=("$1")
        echo -e "  ${RED}✗ $1${NC}"
    else
        echo -e "  ${GREEN}✓ $1${NC}"
    fi
}

echo "必需依赖:"
check_dep bash
check_dep curl
check_dep grep
check_dep sed

echo ""
echo "可选依赖:"
check_dep mpv
check_dep jq

# 安装缺失的依赖
if [[ ${#MISSING_DEPS[@]} -gt 0 ]]; then
    echo ""
    echo -e "${YELLOW}发现缺失依赖: ${MISSING_DEPS[*]}${NC}"
    echo ""
    echo "是否自动安装? (需要 sudo 权限) [y/N]"
    read -r answer
    
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        echo "安装依赖..."
        sudo pacman -S --noconfirm "${MISSING_DEPS[@]}"
    else
        echo "请手动安装: sudo pacman -S ${MISSING_DEPS[*]}"
    fi
fi

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 安装
echo ""
echo -e "${YELLOW}开始安装 LX-Music-Shell...${NC}"

# 安装主程序
echo "安装主程序..."
sudo install -Dm755 "$SCRIPT_DIR/lx-music-shell" /usr/local/bin/lx-music-shell

# 创建配置目录
CONFIG_DIR="${HOME}/.config/lx-music-shell"
mkdir -p "$CONFIG_DIR"

# 创建配置文件
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
    echo "创建配置文件: $CONFIG_DIR/config"
fi

# 创建源配置
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
    echo "创建源配置: $CONFIG_DIR/sources.list"
fi

# 安装 man 页面
if [[ -f "$SCRIPT_DIR/aur/lx-music-shell.1" ]]; then
    sudo install -Dm644 "$SCRIPT_DIR/aur/lx-music-shell.1" /usr/local/share/man/man1/lx-music-shell.1
fi

# 刷新 man 数据库
mandb 2>/dev/null || true

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  安装完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "运行方式:"
echo "  lx-music-shell          # 交互模式"
echo "  lx-music-shell --help   # 查看帮助"
echo "  lx-music-shell --test-sources  # 测试源连通性"
echo ""
echo "配置文件位置: $CONFIG_DIR/"
echo ""

# 测试安装
echo -e "${YELLOW}测试安装...${NC}"
if command -v lx-music-shell &>/dev/null; then
    echo -e "${GREEN}✓ 安装成功！${NC}"
else
    echo -e "${RED}✗ 安装可能有问题，请检查 PATH${NC}"
fi
