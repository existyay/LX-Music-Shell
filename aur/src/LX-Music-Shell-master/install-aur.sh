#!/usr/bin/env bash
#==============================================================================
# LX-Music-Shell 一键安装脚本 (Arch Linux)
# 自动安装所有必需和推荐的依赖
#==============================================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

#==============================================================================
# 必需依赖 - 程序无法运行所需
#==============================================================================
REQUIRED_DEPS=(
    "bash"           # Shell 解释器
    "curl"           # HTTP 请求
    "coreutils"      # timeout, cat, tr, etc.
    "grep"           # 文本搜索
    "sed"            # 流编辑器
    "gawk"           # 文本处理
    "procps-ng"      # 进程管理 (kill, ps, wait)
    "iputils"        # 网络工具 (ping)
    "ncurses"        # 终端控制
    "glibc"          # 系统核心库
)

#==============================================================================
# 推荐依赖 - 提供核心功能
#==============================================================================
RECOMMENDED_DEPS=(
    "mpv"            # 默认播放器
    "jq"             # JSON 解析
    "ffmpeg"         # 音频处理 + ffplay 后端
)

#==============================================================================
# 可选依赖 - 增强功能
#==============================================================================
OPTIONAL_DEPS=(
    "bluez"          # 蓝牙支持
    "bluez-utils"    # 蓝牙工具
    "networkmanager" # 网络管理
    "wireless_tools" # WiFi 工具
    "alsa-utils"     # ALSA 音频
    "pulseaudio"     # PulseAudio
    "pipewire"       # PipeWire
)

#==============================================================================
# 检查依赖函数
#==============================================================================
check_dep() {
    local dep="$1"
    local pkg_name="${2:-$dep}"
    
    if pacman -Q "$pkg_name" &>/dev/null; then
        return 0
    elif command -v "$dep" &>/dev/null; then
        return 0
    fi
    return 1
}

#==============================================================================
# 第一阶段: 检查所有依赖
#==============================================================================
echo -e "${YELLOW}[1/5] 检查系统依赖...${NC}"
echo ""

MISSING_REQUIRED=()
MISSING_RECOMMENDED=()
MISSING_OPTIONAL=()

# 检查必需依赖
echo "必需依赖:"
for dep in "${REQUIRED_DEPS[@]}"; do
    if check_dep "$dep"; then
        echo -e "  ${GREEN}✓${NC} $dep"
    else
        echo -e "  ${RED}✗${NC} $dep (缺失)"
        MISSING_REQUIRED+=("$dep")
    fi
done
echo ""

# 检查推荐依赖
echo "推荐依赖:"
for dep in "${RECOMMENDED_DEPS[@]}"; do
    if check_dep "$dep"; then
        echo -e "  ${GREEN}✓${NC} $dep"
    else
        echo -e "  ${YELLOW}○${NC} $dep (未安装，建议安装)"
        MISSING_RECOMMENDED+=("$dep")
    fi
done
echo ""

# 检查可选依赖
echo "可选依赖 (蓝牙/网络/音频系统):"
for dep in "${OPTIONAL_DEPS[@]}"; do
    if check_dep "$dep"; then
        echo -e "  ${GREEN}✓${NC} $dep"
    else
        echo -e "  ${GRAY:-${NC}}-${NC} $dep (未安装)"
        MISSING_OPTIONAL+=("$dep")
    fi
done
echo ""

#==============================================================================
# 第二阶段: 询问是否自动安装
#==============================================================================
NEED_INSTALL=false
INSTALL_LIST=()

if [[ ${#MISSING_REQUIRED[@]} -gt 0 ]]; then
    NEED_INSTALL=true
    INSTALL_LIST+=("${MISSING_REQUIRED[@]}")
fi

if [[ ${#MISSING_RECOMMENDED[@]} -gt 0 ]]; then
    NEED_INSTALL=true
    INSTALL_LIST+=("${MISSING_RECOMMENDED[@]}")
fi

if [[ $NEED_INSTALL == true ]]; then
    echo -e "${YELLOW}[2/5] 发现缺失依赖${NC}"
    echo ""
    echo "需要安装的包: ${INSTALL_LIST[*]}"
    echo ""
    echo -n "是否自动安装? (Y/n): "
    read -r answer
    
    if [[ ! "$answer" =~ ^[Nn]$ ]]; then
        echo ""
        echo "正在安装依赖..."
        sudo pacman -S --needed --noconfirm "${INSTALL_LIST[@]}" || {
            echo -e "${RED}部分依赖安装失败${NC}"
            echo "请手动安装: sudo pacman -S ${INSTALL_LIST[*]}"
        }
    else
        echo -e "${YELLOW}跳过依赖安装${NC}"
        if [[ ${#MISSING_REQUIRED[@]} -gt 0 ]]; then
            echo -e "${RED}警告: 必需依赖未安装，程序可能无法运行${NC}"
        fi
    fi
else
    echo -e "${GREEN}[2/5] 所有必需和推荐依赖已安装${NC}"
fi
echo ""

#==============================================================================
# 第三阶段: 安装可选蓝牙/网络/音频依赖
#==============================================================================
if [[ ${#MISSING_OPTIONAL[@]} -gt 0 ]]; then
    echo -e "${YELLOW}[3/5] 可选依赖安装${NC}"
    echo ""
    echo "以下可选依赖提供增强功能:"
    echo "  - bluez/bluez-utils: 蓝牙耳机播放支持"
    echo "  - networkmanager: 网络状态监控"
    echo "  - pulseaudio/pipewire: 音频系统支持"
    echo ""
    echo -n "是否安装可选依赖? (y/N): "
    read -r answer
    
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        echo ""
        sudo pacman -S --needed --noconfirm "${MISSING_OPTIONAL[@]}" 2>/dev/null || \
            echo -e "${YELLOW}部分可选依赖安装失败${NC}"
    else
        echo -e "${YELLOW}跳过可选依赖安装${NC}"
    fi
else
    echo -e "${GREEN}[3/5] 所有可选依赖已安装${NC}"
fi
echo ""

#==============================================================================
# 第四阶段: 安装主程序
#==============================================================================
echo -e "${YELLOW}[4/5] 安装 LX-Music-Shell 主程序...${NC}"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 安装主程序
echo "安装二进制文件..."
sudo install -Dm755 "$SCRIPT_DIR/lx-music-shell" /usr/bin/lx-music-shell
echo -e "  ${GREEN}✓${NC} /usr/bin/lx-music-shell"

# 安装更新脚本
sudo install -Dm755 "$SCRIPT_DIR/sources-update.sh" /usr/bin/lx-music-sources
echo -e "  ${GREEN}✓${NC} /usr/bin/lx-music-sources"

# 安装卸载脚本
sudo install -Dm755 "$SCRIPT_DIR/uninstall.sh" /usr/bin/lx-music-shell-uninstall
echo -e "  ${GREEN}✓${NC} /usr/bin/lx-music-shell-uninstall"

# 安装 man 页面
if [[ -f "$SCRIPT_DIR/aur/lx-music-shell.1" ]]; then
    sudo install -Dm644 "$SCRIPT_DIR/aur/lx-music-shell.1" /usr/share/man/man1/lx-music-shell.1
    sudo install -Dm644 "$SCRIPT_DIR/aur/lx-music-shell.1" /usr/share/man/man1/lx-music-sources.1
    sudo install -Dm644 "$SCRIPT_DIR/aur/lx-music-shell.1" /usr/share/man/man1/lx-music-shell-uninstall.1
    sudo mandb 2>/dev/null || true
    echo -e "  ${GREEN}✓${NC} man 页面"
fi

# 安装 bash 补全
if [[ -f "$SCRIPT_DIR/aur/lx-music-shell.bash" ]]; then
    sudo install -Dm644 "$SCRIPT_DIR/aur/lx-music-shell.bash" /usr/share/bash-completion/completions/lx-music-shell
    echo -e "  ${GREEN}✓${NC} bash 补全"
fi

# 安装桌面文件
if [[ -f "$SCRIPT_DIR/aur/lx-music-shell.desktop" ]]; then
    sudo install -Dm644 "$SCRIPT_DIR/aur/lx-music-shell.desktop" /usr/share/applications/lx-music-shell.desktop
    sudo update-desktop-database 2>/dev/null || true
    echo -e "  ${GREEN}✓${NC} 桌面文件"
fi

# 安装文档
if [[ -f "$SCRIPT_DIR/LICENSE" ]]; then
    sudo install -Dm644 "$SCRIPT_DIR/LICENSE" /usr/share/licenses/lx-music-shell/LICENSE
    echo -e "  ${GREEN}✓${NC} LICENSE"
fi

if [[ -f "$SCRIPT_DIR/README.md" ]]; then
    sudo install -Dm644 "$SCRIPT_DIR/README.md" /usr/share/doc/lx-music-shell/README.md
    echo -e "  ${GREEN}✓${NC} README.md"
fi

#==============================================================================
# 第五阶段: 创建用户配置
#==============================================================================
echo ""
echo -e "${YELLOW}[5/5] 创建用户配置...${NC}"
echo ""

CONFIG_DIR="${HOME}/.config/lx-music-shell"
mkdir -p "$CONFIG_DIR"

# 创建默认配置
if [[ ! -f "$CONFIG_DIR/config" ]]; then
    cat > "$CONFIG_DIR/config" << 'EOFCONFIG'
# LX-Music-Shell Configuration

# 播放器后端 (mpv/mplayer/ffplay)
PLAYER_BACKEND="mpv"

# 默认音乐源
DEFAULT_SOURCE="kugou"

# 搜索结果数量限制
SEARCH_LIMIT="20"

# 播放模式 (list/loop/single/random)
PLAY_MODE="list"

# 音量 (0-100)
VOLUME="80"

# 自动更新源列表
AUTO_UPDATE_SOURCES="true"

# UI设置
UI_COLOR="true"

# 网络监控
NETWORK_CHECK_INTERVAL="3"
MAX_RECONNECT_ATTEMPTS="5"
RECONNECT_DELAY="2"
AUTO_RECONNECT="true"
WATCH_BLUETOOTH="true"
EOFCONFIG
    echo -e "  ${GREEN}✓${NC} 配置文件: $CONFIG_DIR/config"
fi

# 创建源配置
if [[ ! -f "$CONFIG_DIR/sources.list" ]]; then
    cat > "$CONFIG_DIR/sources.list" << 'EOFSOURCES'
# LX-Music-Shell Music Sources Configuration
SOURCE_KUGOU="https://www.kugou.com/yy/index.php"
SOURCE_KUWO="http://www.kuwo.cn/api/www/search/searchMusicBykeyWord"
SOURCE_QQ="https://c.y.qq.com/soso/fcgi-bin/client_search_cp"
SOURCE_NETEASE="https://music.163.com/api/search/get/web"
SOURCE_MIGU="https://music.migu.cn/v1/api/search/search"
SOURCE_XIMALAYA="https://www.ximalaya.com/revision/search"
EOFSOURCES
    echo -e "  ${GREEN}✓${NC} 源配置: $CONFIG_DIR/sources.list"
fi

# 创建缓存目录
mkdir -p "${HOME}/.cache/lx-music-shell/search"
mkdir -p "${HOME}/.local/share/lx-music-shell"

#==============================================================================
# 安装完成
#==============================================================================
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  安装完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

echo "运行方式:"
echo "  ${BLUE}lx-music-shell${NC}              # 交互模式"
echo "  ${BLUE}lx-music-shell --help${NC}       # 查看帮助"
echo "  ${BLUE}lx-music-shell --test-sources${NC} # 测试源连通性"
echo ""

echo "配置文件位置: $CONFIG_DIR/"
echo ""

echo "已安装的功能:"
echo "  ${GREEN}✓${NC} 多源音乐搜索 (6个平台)"
echo "  ${GREEN}✓${NC} 源连通性测试"
echo "  ${GREEN}✓${NC} 自动重连 (蓝牙/网络断线)"
echo "  ${GREEN}✓${NC} 状态栏实时显示"
echo "  ${GREEN}✓${NC} 多播放器后端 (mpv/ffplay/mplayer)"
echo "  ${GREEN}✓${NC} 播放列表管理"
echo ""

echo "新功能说明:"
echo "  - 蓝牙/WiFi 断线后自动重连并续播"
echo "  - 实时状态栏显示播放进度和网络状态"
echo "  - 可通过 /status 查看完整状态"
echo ""

# 测试安装
echo -e "${YELLOW}测试安装...${NC}"
if command -v lx-music-shell &>/dev/null; then
    echo -e "${GREEN}✓ 安装成功！${NC}"
    echo ""
    echo "可以运行 'lx-music-shell' 开始使用"
else
    echo -e "${RED}✗ 安装可能有问题${NC}"
    echo "请检查 PATH 设置或重新登录终端"
fi