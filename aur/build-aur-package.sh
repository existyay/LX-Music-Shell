#!/usr/bin/env bash
#==============================================================================
# LX-Music-Shell AUR 完整提交脚本
# 集成：PKGBUILD 填充 + .SRCINFO 生成 + 源码包创建 + AUR 推送
#
# 使用方法:
#   1. 设置环境变量 (推荐):
#      export AUR_GITHUB_USER="existyay"
#      export AUR_MAINTAINER_NAME="你的真实姓名"
#      export AUR_MAINTAINER_EMAIL="你的邮箱@example.com"
#      export AUR_SSH_KEY="/home/user/.ssh/id_ed25519"  # 可选
#      bash aur/build-aur-package.sh --push
#
#   2. 或交互式输入:
#      bash aur/build-aur-package.sh --push
#==============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PKGBUILD="$SCRIPT_DIR/PKGBUILD"
SRCINFO="$SCRIPT_DIR/.SRCINFO"

#==============================================================================
# 配置 (环境变量覆盖)
#==============================================================================
GITHUB_USER="${AUR_GITHUB_USER:-existyay}"
GITHUB_REPO="${AUR_GITHUB_REPO:-LX-Music-Shell}"
AUR_PACKAGE="${AUR_PACKAGE:-lx-music-shell}"
MAINTAINER_NAME="${AUR_MAINTAINER_NAME:-}"
MAINTAINER_EMAIL="${AUR_MAINTAINER_EMAIL:-}"
PKG_VERSION="${PKG_VERSION:-1.1.0}"
AUR_SSH_KEY="${AUR_SSH_KEY:-}"
PUSH_TO_AUR="${PUSH_TO_AUR:-true}"

#==============================================================================
# 步骤 1: 输入/验证必需信息
#==============================================================================
prompt_user_input() {
    echo -e "${YELLOW}请提供以下信息 (直接回车使用默认值)${NC}"
    echo ""
    
    if [[ -z "$MAINTAINER_NAME" ]]; then
        echo -n "Maintainer 姓名 [默认: Demo User]: "
        read -r MAINTAINER_NAME
        MAINTAINER_NAME="${MAINTAINER_NAME:-Demo User}"
    fi
    
    if [[ -z "$MAINTAINER_EMAIL" ]]; then
        echo -n "Maintainer 邮箱 [默认: demo@example.com]: "
        read -r MAINTAINER_EMAIL
        MAINTAINER_EMAIL="${MAINTAINER_EMAIL:-demo@example.com}"
    fi
    
    echo ""
}

#==============================================================================
# 步骤 2: 填充 PKGBUILD
#==============================================================================
fill_pkgbuild() {
    echo -e "${BLUE}[1/5] 填充 PKGBUILD 占位符...${NC}"

    cp "$PKGBUILD" "${PKGBUILD}.bak"

    # 删除所有 Maintainer/Contributor 注释行
    sed -i '/^# Maintainer:/d; /^# Contributor:/d' "$PKGBUILD"

    # 在文件开头添加 Maintainer
    sed -i "1i\\
# Maintainer: $MAINTAINER_NAME <$MAINTAINER_EMAIL>" "$PKGBUILD"

    # url
    sed -i "s|^url=.*|url=\"https://github.com/$GITHUB_USER/$GITHUB_REPO\"|" "$PKGBUILD"

    # source URL (使用 releases tag)
    sed -i "s|^source=.*|source=(\"lx-music-shell-source-v\$pkgver.tar.gz::https://github.com/$GITHUB_USER/$GITHUB_REPO/archive/refs/tags/v\$pkgver.tar.gz\")|" "$PKGBUILD"

    echo -e "${GREEN}  ✓ PKGBUILD 已更新${NC}"
    echo ""
    head -10 "$PKGBUILD"
}

#==============================================================================
# 步骤 3: 生成 .SRCINFO
#==============================================================================
generate_srcinfo() {
    echo ""
    echo -e "${BLUE}[2/5] 重新生成 .SRCINFO...${NC}"
    
    rm -f "$SRCINFO"
    
    cd "$PROJECT_DIR"
    
    # 尝试 makepkg
    if command -v makepkg &>/dev/null; then
        if makepkg --geninteg > "$SRCINFO" 2>/dev/null; then
            echo -e "${GREEN}  ✓ .SRCINFO 已生成 (makepkg)${NC}"
            cd "$SCRIPT_DIR"
            return 0
        fi
    fi
    
    cd "$SCRIPT_DIR"
    
    # 静态生成 (通过 awk 跟踪括号匹配)
    local pkgname=$(grep '^pkgname=' "$PKGBUILD" | head -1 | sed 's/.*=//; s/"//g')
    local pkgver=$(grep '^pkgver=' "$PKGBUILD" | head -1 | sed 's/.*=//; s/"//g')
    local pkgrel=$(grep '^pkgrel=' "$PKGBUILD" | head -1 | sed 's/.*=//; s/"//g')
    local pkgdesc=$(grep '^pkgdesc=' "$PKGBUILD" | head -1 | sed 's/.*=//; s/^"//; s/"$//')
    local url=$(grep '^url=' "$PKGBUILD" | head -1 | sed 's/.*=//; s/"//g')
    
    cat > "$SRCINFO" << EOF
pkgbase = $pkgname
	pkgdesc = $pkgdesc
	pkgver = $pkgver
	pkgrel = $pkgrel
	url = $url
EOF
    
    parse_array() {
        local field="$1"
        local start_line=$(grep -n "^${field}=(" "$PKGBUILD" 2>/dev/null | head -1 | cut -d: -f1)
        [[ -z "$start_line" ]] && return
        local end_line=$(awk -v start="$start_line" '
            NR < start { next }
            {
                line = $0
                for (i = 1; i <= length(line); i++) {
                    c = substr(line, i, 1)
                    if (c == "(") depth++
                    if (c == ")") {
                        depth--
                        if (depth == 0) { print NR; exit }
                    }
                }
            }
        ' "$PKGBUILD")
        [[ -z "$end_line" ]] && end_line=$(wc -l < "$PKGBUILD")
        sed -n "${start_line},${end_line}p" "$PKGBUILD" | grep -oP '"[^"]*"' | sed 's/^"//; s/"$//'
    }
    
    for field in arch license depends optdepends checkdepends backup; do
        while IFS= read -r item; do
            [[ -n "$item" ]] && echo "	$field = $item" >> "$SRCINFO"
        done < <(parse_array $field)
    done
    
    echo "	options = !strip" >> "$SRCINFO"
    echo "	source = https://github.com/$GITHUB_USER/$GITHUB_REPO/archive/refs/tags/v$pkgver.tar.gz" >> "$SRCINFO"
    echo "	sha256sums = SKIP" >> "$SRCINFO"
    echo "" >> "$SRCINFO"
    echo "pkgname = $pkgname" >> "$SRCINFO"
    
    echo -e "${GREEN}  ✓ .SRCINFO 已生成 (static)${NC}"
}

#==============================================================================
# 步骤 4: 验证
#==============================================================================
validate() {
    echo ""
    echo -e "${BLUE}[3/5] 验证 PKGBUILD 和 .SRCINFO...${NC}"
    
    local errors=0
    
    # PKGBUILD 检查
    if grep -q "yourname\|YOUR_\|example\.com" "$PKGBUILD"; then
        echo -e "${RED}  ✗ PKGBUILD 仍包含占位符${NC}"
        ((errors++))
    else
        echo -e "${GREEN}  ✓ PKGBUILD 无占位符${NC}"
    fi
    
    # .SRCINFO 检查
    if [[ ! -f "$SRCINFO" ]]; then
        echo -e "${RED}  ✗ .SRCINFO 不存在${NC}"
        ((errors++))
    else
        local srcinfo_url=$(grep "url = " "$SRCINFO" | head -1 | sed 's|^	*url = ||')
        local expected_url="https://github.com/$GITHUB_USER/$GITHUB_REPO"
        if [[ "$srcinfo_url" == "$expected_url" ]]; then
            echo -e "${GREEN}  ✓ .SRCINFO URL 正确${NC}"
        else
            echo -e "${RED}  ✗ .SRCINFO URL 错误: '$srcinfo_url' (期望: '$expected_url')${NC}"
            ((errors++))
        fi
    fi
    
    if [[ $errors -gt 0 ]]; then
        echo -e "${RED}  验证失败，请检查错误${NC}"
        return 1
    fi
    
    return 0
}

#==============================================================================
# 步骤 5: 推送到 AUR
#==============================================================================
push_to_aur() {
    echo ""
    echo -e "${BLUE}[4/5] 准备推送到 AUR...${NC}"
    
    # 测试 SSH 连接
    echo "测试 SSH 连接到 AUR..."
    local ssh_cmd="ssh"
    [[ -n "$AUR_SSH_KEY" ]] && ssh_cmd="ssh -i $AUR_SSH_KEY"
    
    if ! $ssh_cmd -T -o StrictHostKeyChecking=no -o BatchMode=yes aur@aur.archlinux.org 2>&1 | grep -q "Welcome\|successfully"; then
        echo -e "${RED}  ✗ 无法连接到 AUR${NC}"
        echo ""
        echo "请检查:"
        echo "  1. SSH 公钥是否上传到 https://aur.archlinux.org/account/"
        echo "  2. SSH 密钥路径是否正确: $AUR_SSH_KEY"
        echo ""
        echo "公钥内容:"
        cat ~/.ssh/id_ed25519.pub 2>/dev/null || echo "未找到 ~/.ssh/id_ed25519.pub"
        return 1
    fi
    
    echo -e "${GREEN}  ✓ SSH 连接成功${NC}"
    
    # 克隆 AUR 仓库
    local aur_work="/tmp/aur-$AUR_PACKAGE-$$"
    rm -rf "$aur_work"
    
    echo "克隆 AUR 仓库..."
    if ! $ssh_cmd "aur@aur.archlinux.org" "git clone ssh://aur@aur.archlinux.org/$AUR_PACKAGE.git $aur_work" 2>&1; then
        echo -e "${RED}  ✗ 克隆失败${NC}"
        echo "可能包名 $AUR_PACKAGE 已被占用"
        echo "尝试用其他名字: AUR_PACKAGE=lx-mus-shell bash $0 --push"
        return 1
    fi
    
    # 检查是否是首次提交
    if [ -d "$aur_work" ] && [ -z "$(ls -A "$aur_work" 2>/dev/null)" ]; then
        echo "首次提交，准备空仓库..."
        cd "$aur_work"
        git init -q
        git config user.name "$MAINTAINER_NAME"
        git config user.email "$MAINTAINER_EMAIL"
    else
        cd "$aur_work"
        git config user.name "$MAINTAINER_NAME"
        git config user.email "$MAINTAINER_EMAIL"
    fi
    
    # 复制文件
    echo "复制文件到 AUR 仓库..."
    cp "$PKGBUILD" .
    cp "$SRCINFO" .
    cp "$SCRIPT_DIR/lx-music-shell.install" .
    cp "$SCRIPT_DIR/lx-music-shell.1" .
    cp "$SCRIPT_DIR/lx-music-shell.bash" .
    cp "$SCRIPT_DIR/lx-music-shell.desktop" .
    
    echo ""
    echo "将要提交的文件:"
    ls -la
    echo ""
    
    # 确认
    echo -n "确认提交到 AUR? (y/N) "
    read -r confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "已取消"
        cd /
        rm -rf "$aur_work"
        return 1
    fi
    
    # 提交
    git add PKGBUILD .SRCINFO lx-music-shell.install lx-music-shell.1 \
            lx-music-shell.bash lx-music-shell.desktop 2>/dev/null || \
    git add .
    
    git commit -q -m "Initial upload: $AUR_PACKAGE v$PKG_VERSION

A pure shell terminal music player with multi-source support
including auto-reconnect on network/bluetooth disconnection."
    
    echo ""
    echo "推送到 AUR..."
    if git push 2>&1; then
        echo ""
        echo -e "${GREEN}  ✓ 推送成功！${NC}"
        echo ""
        echo "  你的包地址: https://aur.archlinux.org/packages/$AUR_PACKAGE"
        echo "  用户安装: yay -S $AUR_PACKAGE"
    else
        echo -e "${RED}  ✗ 推送失败${NC}"
        return 1
    fi
    
    cd /
    rm -rf "$aur_work"
}

#==============================================================================
# 步骤 6: 推送 tag 到 GitHub
#==============================================================================
push_to_github() {
    echo ""
    echo -e "${BLUE}[5/5] 推送到 GitHub...${NC}"
    
    cd "$PROJECT_DIR"
    
    # 检查 remote
    if ! git remote -v | grep -q "origin"; then
        echo -e "${RED}  ✗ 未配置 origin remote${NC}"
        echo "运行: git remote add origin https://github.com/$GITHUB_USER/$GITHUB_REPO.git"
        return 1
    fi
    
    # 推送代码
    echo "推送代码到 GitHub..."
    if git push -u origin master 2>&1; then
        echo -e "${GREEN}  ✓ 代码推送成功${NC}"
    else
        echo -e "${YELLOW}  ⚠ 代码推送可能失败 (已存在或权限问题)${NC}"
    fi
    
    # 推送 tag
    echo "推送 tag v$PKG_VERSION..."
    git tag -f "v$PKG_VERSION" 2>/dev/null || git tag "v$PKG_VERSION"
    if git push origin "v$PKG_VERSION" 2>&1; then
        echo -e "${GREEN}  ✓ Tag 推送成功${NC}"
    else
        echo -e "${RED}  ✗ Tag 推送失败${NC}"
        return 1
    fi
}

#==============================================================================
# 主流程
#==============================================================================
main() {
    local action="${1:-all}"
    
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  LX-Music-Shell AUR 完整提交工具${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo "配置:"
    echo "  GitHub 用户:  $GITHUB_USER"
    echo "  GitHub 仓库:  $GITHUB_REPO"
    echo "  AUR 包名:    $AUR_PACKAGE"
    echo "  Maintainer:   ${MAINTAINER_NAME:-<待输入>}"
    echo "  版本:        $PKG_VERSION"
    echo ""
    
    # 询问输入
    if [[ "$action" == "--push" ]] && [[ -z "$MAINTAINER_NAME" || -z "$MAINTAINER_EMAIL" ]]; then
        prompt_user_input
    fi
    
    echo -e "${CYAN}当前信息:${NC}"
    echo "  Maintainer: $MAINTAINER_NAME <$MAINTAINER_EMAIL>"
    echo "  仓库: https://github.com/$GITHUB_USER/$GITHUB_REPO"
    echo "  AUR 包: $AUR_PACKAGE"
    echo ""
    
    if [[ "$action" != "--no-confirm" ]]; then
        echo -n "继续执行? (y/N) "
        read -r answer
        [[ ! "$answer" =~ ^[Yy]$ ]] && { echo "已取消"; exit 0; }
    fi
    
    # 执行步骤
    fill_pkgbuild
    generate_srcinfo
    validate || { rm -f "${PKGBUILD}.bak"; exit 1; }
    
    # 备份 PKGBUILD
    rm -f "${PKGBUILD}.bak"
    
    if [[ "$action" == "--push" ]]; then
        push_to_github
        echo ""
        push_to_aur
    fi
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  完成！${NC}"
    echo -e "${GREEN}========================================${NC}"
    
    if [[ "$action" == "--push" ]]; then
        echo ""
        echo "📦 AUR 包: https://aur.archlinux.org/packages/$AUR_PACKAGE"
        echo "📥 用户安装: yay -S $AUR_PACKAGE"
    fi
}

#==============================================================================
# 入口
#==============================================================================
case "${1:-all}" in
    --help|-h)
        echo "用法: $0 [选项]"
        echo ""
        echo "选项:"
        echo "  (无)       仅生成 PKGBUILD 和 .SRCINFO"
        echo "  --push     生成 + 推送到 GitHub 和 AUR"
        echo "  --no-confirm  跳过确认步骤"
        echo ""
        echo "环境变量:"
        echo "  AUR_GITHUB_USER       GitHub 用户名 (默认: existyay)"
        echo "  AUR_GITHUB_REPO       GitHub 仓库名 (默认: LX-Music-Shell)"
        echo "  AUR_PACKAGE           AUR 包名 (默认: lx-music-shell)"
        echo "  AUR_MAINTAINER_NAME   Maintainer 姓名"
        echo "  AUR_MAINTAINER_EMAIL  Maintainer 邮箱"
        echo "  AUR_SSH_KEY           SSH 密钥路径"
        echo "  PKG_VERSION           包版本 (默认: 1.1.0)"
        ;;
    *)
        main "$@"
        ;;
esac