#!/usr/bin/env bash
#==============================================================================
# AUR 推送脚本 - 一键推送到 AUR
# 使用专用 SSH key (无 passphrase)
#==============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
AUR_PKG="lx-music-shell"
SSH_KEY="$HOME/.ssh/aur_key"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  AUR 推送脚本${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 1. 检查 SSH key
if [[ ! -f "$SSH_KEY" ]]; then
    echo -e "${RED}✗ SSH key 不存在: $SSH_KEY${NC}"
    echo "运行: ssh-keygen -t ed25519 -N '' -f $SSH_KEY"
    exit 1
fi
echo -e "${GREEN}✓ SSH key 已配置: $SSH_KEY${NC}"

# 2. 测试 SSH 连接
echo ""
echo "测试 AUR 连接..."
SSH_OUTPUT=$(ssh -i "$SSH_KEY" -T -o StrictHostKeyChecking=no aur@aur.archlinux.org 2>&1)
if echo "$SSH_OUTPUT" | grep -q "Permission denied"; then
    echo -e "${RED}✗ AUR SSH 连接失败${NC}"
    echo ""
    echo "你的 SSH 公钥:"
    cat "${SSH_KEY}.pub"
    echo ""
    echo "请将此公钥上传到: https://aur.archlinux.org/account/"
    exit 1
fi
echo -e "${GREEN}✓ AUR SSH 连接成功${NC}"

# 3. 克隆 AUR 仓库
WORK_DIR="/tmp/aur-push-$$"
rm -rf "$WORK_DIR"
# 确保后续的 git 操作使用相同的私钥
export GIT_SSH_COMMAND="ssh -i '$SSH_KEY' -o StrictHostKeyChecking=no"

echo ""
echo "克隆 AUR 仓库..."
if ! git clone "ssh://aur@aur.archlinux.org/${AUR_PKG}.git" "$WORK_DIR" 2>&1; then
    echo -e "${RED}✗ 克隆失败 - 包名可能已被占用${NC}"
    exit 1
fi

cd "$WORK_DIR"

# 配置 git 用户
git config user.name "existyay"
git config user.email "liujam826@gmail.com"

# 4. 复制文件
echo ""
echo "复制文件到 AUR 仓库..."
cp "$SCRIPT_DIR/PKGBUILD" .
cp "$SCRIPT_DIR/.SRCINFO" .
cp "$SCRIPT_DIR/lx-music-shell.install" .
cp "$SCRIPT_DIR/lx-music-shell.1" .
cp "$SCRIPT_DIR/lx-music-sources.1" .
cp "$SCRIPT_DIR/lx-music-shell-uninstall.1" .
cp "$SCRIPT_DIR/lx-music-shell.bash" .
cp "$SCRIPT_DIR/lx-music-shell.desktop" .

echo ""
echo "将要提交的文件:"
ls -la
echo ""

# 5. 提交
git add PKGBUILD .SRCINFO lx-music-shell.install lx-music-shell.1 \
        lx-music-sources.1 lx-music-shell-uninstall.1 \
        lx-music-shell.bash lx-music-shell.desktop

git commit -m "Update to lx-music-shell v1.1.1

A pure shell terminal music player with multi-source support
including auto-reconnect on network/bluetooth disconnection.

Improvements over v1.1.0:
- Clean up all shellcheck warnings (0 errors, 0 warnings)
- Add dedicated man pages for lx-music-sources and uninstaller
- Add proper Maintainer field in PKGBUILD
- Fix source filename uniqueness for namcap
- Various code cleanups"

# 6. 推送
echo ""
echo "推送到 AUR..."
if git push 2>&1; then
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  ✓ 推送成功！${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "你的 AUR 包地址:"
    echo "  https://aur.archlinux.org/packages/${AUR_PKG}"
    echo ""
    echo "用户安装命令:"
    echo "  yay -S ${AUR_PKG}"
    echo ""
    echo -e "${YELLOW}注意: AUR 包可能需要几分钟才能在搜索中显示${NC}"
else
    echo -e "${RED}✗ 推送失败${NC}"
    exit 1
fi

# 清理
cd /
rm -rf "$WORK_DIR"