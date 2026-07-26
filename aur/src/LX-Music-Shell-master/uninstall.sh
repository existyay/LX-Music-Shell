#!/usr/bin/env bash
#==============================================================================
# LX-Music-Shell 卸载脚本
# 用于从系统中移除 LX-Music-Shell
#
# 注意: 如果你是通过 pacman/yay 安装的，请使用:
#   sudo pacman -R lx-music-shell
#   或 sudo yay -R lx-music-shell
# 此脚本适用于手动安装的版本
#==============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  LX-Music-Shell 卸载脚本${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 检测是否为系统级安装或用户级安装
SYSTEM_FILES=(
    "/usr/bin/lx-music-shell"
    "/usr/local/bin/lx-music-shell"
    "/usr/bin/lx-music-sources"
    "/usr/local/bin/lx-music-sources"
    "/usr/local/share/man/man1/lx-music-shell.1"
    "/usr/share/man/man1/lx-music-shell.1"
    "/usr/share/man/man1/lx-music-sources.1"
    "/usr/share/bash-completion/completions/lx-music-shell"
    "/usr/share/applications/lx-music-shell.desktop"
    "/etc/skel/.config/lx-music-shell"
)

USER_FILES=(
    "$HOME/.config/lx-music-shell"
    "$HOME/.cache/lx-music-shell"
    "$HOME/.local/share/lx-music-shell"
    "$HOME/.local/bin/lx-music-shell"
    "$HOME/.local/bin/lx-music-sources"
    "$HOME/Music/LX-Music-Shell"
)

# 检查是否有系统级文件
SYSTEM_FOUND=false
for file in "${SYSTEM_FILES[@]}"; do
    if [[ -e "$file" ]]; then
        SYSTEM_FOUND=true
        break
    fi
done

# 检查是否有用户级文件
USER_FOUND=false
for file in "${USER_FILES[@]}"; do
    if [[ -e "$file" ]]; then
        USER_FOUND=true
        break
    fi
done

if [[ "$SYSTEM_FOUND" == false ]] && [[ "$USER_FOUND" == false ]]; then
    echo -e "${YELLOW}未找到 LX-Music-Shell 的安装文件${NC}"
    echo ""
    echo "如果你通过 AUR/pacman 安装了，请使用:"
    echo "  sudo pacman -R lx-music-shell"
    echo "  或 sudo yay -R lx-music-shell"
    exit 0
fi

# 询问用户是否使用 pacman 卸载
if [[ "$SYSTEM_FOUND" == true ]] && command -v pacman &>/dev/null; then
    if pacman -Q lx-music-shell &>/dev/null; then
        echo -e "${GREEN}检测到 LX-Music-Shell 是通过 pacman 安装的${NC}"
        echo ""
        echo "是否使用 pacman 卸载? [Y/n]"
        read -r answer
        if [[ ! "$answer" =~ ^[Nn]$ ]]; then
            echo ""
            echo -e "${BLUE}使用 pacman 卸载...${NC}"
            sudo pacman -R lx-music-shell
            exit_code=$?
            if [[ $exit_code -eq 0 ]]; then
                echo ""
                echo -e "${GREEN}✓ 通过 pacman 卸载成功${NC}"
                echo ""
                echo -n "是否同时删除用户配置文件? [y/N] "
                read -r remove_user
                if [[ "$remove_user" =~ ^[Yy]$ ]]; then
                    echo -n "确认删除 ~/.config/lx-music-shell 等用户文件? [y/N] "
                    read -r confirm
                    if [[ "$confirm" =~ ^[Yy]$ ]]; then
                        for file in "${USER_FILES[@]}"; do
                            if [[ -e "$file" ]]; then
                                rm -rf "$file"
                                echo -e "  ${GREEN}✓${NC} 已删除: $file"
                            fi
                        done
                    fi
                fi
            fi
            exit $exit_code
        fi
    fi
fi

# 手动卸载流程
echo ""
echo -e "${YELLOW}开始手动卸载...${NC}"
echo ""

# 询问权限
if [[ "$SYSTEM_FOUND" == true ]]; then
    echo -e "${YELLOW}检测到系统级安装文件，需要 sudo 权限${NC}"
    echo -n "继续? [y/N] "
    read -r answer
    if [[ ! "$answer" =~ ^[Yy]$ ]]; then
        echo "已取消"
        exit 1
    fi
    SUDO_CMD="sudo"
else
    SUDO_CMD=""
fi

# 删除系统级文件
if [[ "$SYSTEM_FOUND" == true ]]; then
    echo ""
    echo -e "${BLUE}[1/2] 删除系统文件...${NC}"
    for file in "${SYSTEM_FILES[@]}"; do
        if [[ -e "$file" ]]; then
            $SUDO_CMD rm -rf "$file"
            echo -e "  ${GREEN}✓${NC} 已删除: $file"
        fi
    done
    
    # 刷新数据库
    $SUDO_CMD mandb 2>/dev/null || true
    $SUDO_CMD update-desktop-database 2>/dev/null || true
    echo ""
fi

# 处理用户文件
echo -e "${BLUE}[2/2] 处理用户文件...${NC}"
USER_EXISTS=false
for file in "${USER_FILES[@]}"; do
    if [[ -e "$file" ]]; then
        USER_EXISTS=true
        break
    fi
done

if [[ "$USER_EXISTS" == true ]]; then
    echo ""
    echo "找到用户文件:"
    for file in "${USER_FILES[@]}"; do
        if [[ -e "$file" ]]; then
            echo "  - $file"
        fi
    done
    echo ""
    echo -n "是否删除用户配置文件和缓存? [y/N] "
    read -r answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        for file in "${USER_FILES[@]}"; do
            if [[ -e "$file" ]]; then
                rm -rf "$file"
                echo -e "  ${GREEN}✓${NC} 已删除: $file"
            fi
        done
    else
        echo "用户文件已保留"
    fi
else
    echo "无用户文件需要处理"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  卸载完成${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "感谢使用 LX-Music-Shell"
echo ""