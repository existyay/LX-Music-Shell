#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PKGBUILD="$SCRIPT_DIR/PKGBUILD"
SRCINFO="$SCRIPT_DIR/.SRCINFO"

GITHUB_USER="${AUR_GITHUB_USER:-existyay}"
GITHUB_REPO="${AUR_GITHUB_REPO:-LX-Music-Shell}"
AUR_PACKAGE="${AUR_PACKAGE:-lx-music-shell}"
PKG_VERSION="${PKG_VERSION:-3.0.2}"
AUR_SSH_KEY="${AUR_SSH_KEY:-}"
MAINTAINER_NAME="${AUR_MAINTAINER_NAME:-existyay}"
MAINTAINER_EMAIL="${AUR_MAINTAINER_EMAIL:-liujam826@gmail.com}"

print_header() {
    printf '%b\n' "${BLUE}========================================${NC}"
    printf '%b\n' "${BLUE}  LX-Music-Shell AUR 提交工具${NC}"
    printf '%b\n' "${BLUE}========================================${NC}"
    printf '%b\n' ""
}

usage() {
    cat <<'USAGE'
用法: $0 [选项]

选项:
  (无)          仅生成 PKGBUILD 和 .SRCINFO
  --push        生成并推送到 GitHub 与 AUR
  --no-confirm  跳过确认提示
  --help, -h    显示此帮助信息

环境变量:
  AUR_GITHUB_USER       GitHub 用户名 (默认: existyay)
  AUR_GITHUB_REPO       GitHub 仓库名 (默认: LX-Music-Shell)
  AUR_PACKAGE           AUR 包名 (默认: lx-music-shell)
  AUR_MAINTAINER_NAME   Maintainer 姓名
  AUR_MAINTAINER_EMAIL  Maintainer 邮箱
  AUR_SSH_KEY           SSH 私钥路径
  PKG_VERSION           包版本 (默认: 1.1.1)
USAGE
}

prompt_user_input() {
    printf '%b\n' "${YELLOW}请提供以下信息 (直接回车使用默认值)${NC}"

    if [[ -z "${MAINTAINER_NAME:-}" ]]; then
        printf 'Maintainer 姓名 [默认: Demo User]: '
        read -r MAINTAINER_NAME
        MAINTAINER_NAME="${MAINTAINER_NAME:-existyay}"
    fi

    if [[ -z "${MAINTAINER_EMAIL:-}" ]]; then
        printf 'Maintainer 邮箱 [默认: demo@example.com]: '
        read -r MAINTAINER_EMAIL
        MAINTAINER_EMAIL="${MAINTAINER_EMAIL:-demo@example.com}"
    fi

    printf '%b\n' ""
}

fill_pkgbuild() {
    printf '%b\n' "${BLUE}[1/4] 更新 PKGBUILD${NC}"

    cp "$PKGBUILD" "${PKGBUILD}.bak"
    sed -i '/^# Maintainer:/d; /^# Contributor:/d' "$PKGBUILD"
    sed -i "1i\\# Maintainer: $MAINTAINER_NAME <$MAINTAINER_EMAIL>" "$PKGBUILD"
    sed -i "s|^url=.*|url=\"https://github.com/$GITHUB_USER/$GITHUB_REPO\"|" "$PKGBUILD"
    sed -i "s|^pkgver=.*|pkgver=$PKG_VERSION|" "$PKGBUILD"
    sed -i "s|^source=.*|source=(\"lx-music-shell-source-v$PKG_VERSION.tar.gz::https://github.com/$GITHUB_USER/$GITHUB_REPO/archive/refs/tags/v$PKG_VERSION.tar.gz\")|" "$PKGBUILD"

    printf '%b\n' "${GREEN}  ✓ PKGBUILD 更新完成${NC}"
    printf '%b\n' ""
    head -n 12 "$PKGBUILD"
}

generate_srcinfo() {
    printf '%b\n' ""
    printf '%b\n' "${BLUE}[2/4] 生成 .SRCINFO${NC}"

    rm -f "$SRCINFO"
    cd "$SCRIPT_DIR"

    if command -v makepkg >/dev/null 2>&1; then
        if makepkg --printsrcinfo > "$SRCINFO" 2>/dev/null; then
            printf '%b\n' "${GREEN}  ✓ .SRCINFO 已生成 (makepkg)${NC}"
            return 0
        fi
    fi

    printf '%b\n' "${YELLOW}  ⚠ makepkg 不可用，正在尝试静态生成 .SRCINFO${NC}"

    local pkgname
    pkgname=$(grep '^pkgname=' "$PKGBUILD" | head -n 1 | sed 's/.*=//; s/"//g')
    local pkgver
    pkgver=$(grep '^pkgver=' "$PKGBUILD" | head -n 1 | sed 's/.*=//; s/"//g')
    local pkgrel
    pkgrel=$(grep '^pkgrel=' "$PKGBUILD" | head -n 1 | sed 's/.*=//; s/"//g')
    local pkgdesc
    pkgdesc=$(grep '^pkgdesc=' "$PKGBUILD" | head -n 1 | sed 's/.*=//; s/^"//; s/"$//')
    local url
    url=$(grep '^url=' "$PKGBUILD" | head -n 1 | sed 's/.*=//; s/"//g')

    cat > "$SRCINFO" <<EOF
pkgbase = $pkgname
pkgname = $pkgname
pkgver = $pkgver
pkgrel = $pkgrel
pkgdesc = $pkgdesc
arch = any
url = $url
license = MIT
source = https://github.com/$GITHUB_USER/$GITHUB_REPO/archive/refs/tags/v$pkgver.tar.gz
sha256sums = SKIP
EOF

    printf '%b\n' "${GREEN}  ✓ .SRCINFO 已生成 (静态)${NC}"
}

validate() {
    printf '%b\n' ""
    printf '%b\n' "${BLUE}[3/4] 验证 PKGBUILD 和 .SRCINFO${NC}"

    local errors=0

    if grep -Eq 'yourname|YOUR_|example\.com' "$PKGBUILD"; then
        printf '%b\n' "${RED}  ✗ PKGBUILD 中仍存在占位符${NC}"
        errors=$((errors + 1))
    else
        printf '%b\n' "${GREEN}  ✓ PKGBUILD 没有占位符${NC}"
    fi

    if [[ ! -f "$SRCINFO" ]]; then
        printf '%b\n' "${RED}  ✗ .SRCINFO 不存在${NC}"
        errors=$((errors + 1))
    else
        local srcinfo_url expected_url
        # .SRCINFO 中键以制表符缩进 ('\tkey = value')，不是行首
        srcinfo_url=$(grep -E $'^\t*url = ' "$SRCINFO" | head -n 1 | sed $'s/^\t*url = //')
        expected_url="https://github.com/$GITHUB_USER/$GITHUB_REPO"
        if [[ "$srcinfo_url" == "$expected_url" ]]; then
            printf '%b\n' "${GREEN}  ✓ .SRCINFO URL 正确${NC}"
        else
            printf '%b\n' "${RED}  ✗ .SRCINFO URL 错误: '$srcinfo_url' (期望: '$expected_url')${NC}"
            errors=$((errors + 1))
        fi
    fi

    if [[ "$errors" -gt 0 ]]; then
        printf '%b\n' "${RED}  验证失败，请检查上方错误${NC}"
        return 1
    fi

    return 0
}

push_to_aur() {
    printf '%b\n' ""
    printf '%b\n' "${BLUE}[4/4] 推送到 AUR${NC}"

    local ssh_cmd="ssh"
    if [[ -n "${AUR_SSH_KEY:-}" ]]; then
        ssh_cmd="ssh -i $AUR_SSH_KEY"
        export GIT_SSH_COMMAND="ssh -i '$AUR_SSH_KEY' -o StrictHostKeyChecking=no"
    fi

    printf '%s\n' "测试 SSH 连接到 AUR..."
    if ! $ssh_cmd -T -o StrictHostKeyChecking=no -o BatchMode=yes aur@aur.archlinux.org 2>&1 | grep -qE 'Welcome|successfully'; then
        printf '%b\n' "${RED}  ✗ AUR SSH 连接失败${NC}"
        return 1
    fi

    printf '%b\n' "${GREEN}  ✓ AUR 连接成功${NC}"

    local aur_work
    aur_work="/tmp/aur-${AUR_PACKAGE}-$$"
    rm -rf "$aur_work"
    mkdir -p "$aur_work"

    printf '%s\n' "克隆 AUR 仓库..."
    if ! git clone "ssh://aur@aur.archlinux.org/$AUR_PACKAGE.git" "$aur_work" 2>&1; then
        printf '%b\n' "${RED}  ✗ 克隆 AUR 仓库失败${NC}"
        printf '%b\n' "请确认包名 '$AUR_PACKAGE' 已在 AUR 上创建。"
        return 1
    fi

    cd "$aur_work"
    git config user.name "${MAINTAINER_NAME:-AUR Maintainer}"
    git config user.email "${MAINTAINER_EMAIL:-aur@example.com}"

    cp "$PKGBUILD" .
    cp "$SRCINFO" .
    cp "$SCRIPT_DIR/lx-music-shell.install" .
    cp "$SCRIPT_DIR/lx-music-shell.1" .
    cp "$SCRIPT_DIR/lx-music-sources.1" .
    cp "$SCRIPT_DIR/lx-music-shell-uninstall.1" .
    cp "$SCRIPT_DIR/lx-music-shell.bash" .
    cp "$SCRIPT_DIR/lx-music-shell.desktop" .

    git add PKGBUILD .SRCINFO lx-music-shell.install lx-music-shell.1 \
            lx-music-sources.1 lx-music-shell-uninstall.1 \
            lx-music-shell.bash lx-music-shell.desktop

    if [[ -n "$(git status --porcelain)" ]]; then
        git commit -qm "Update AUR package: $AUR_PACKAGE v$PKG_VERSION"
    else
        printf '%b\n' "${YELLOW}  ⚠ AUR 仓库无文件变更，跳过提交${NC}"
    fi

    git push origin master

    printf '%b\n' "${GREEN}  ✓ AUR 推送完成${NC}"
    rm -rf "$aur_work"
}

push_to_github() {
    printf '%b\n' ""
    printf '%b\n' "${BLUE}[GitHub] 推送到 GitHub${NC}"

    cd "$PROJECT_DIR"
    if ! git remote -v | grep -q '^origin'; then
        printf '%b\n' "${RED}  ✗ 未配置 origin 远程仓库${NC}"
        printf '%s\n' "运行: git remote add origin https://github.com/$GITHUB_USER/$GITHUB_REPO.git"
        return 1
    fi

    git push -u origin master
    git tag -f "v$PKG_VERSION"
    git push -f origin "v$PKG_VERSION"
    printf '%b\n' "${GREEN}  ✓ GitHub 推送完成${NC}"
}

main() {
    local action="${1:-all}"
    print_header

    printf '%b\n' "配置:"
    printf '%b\n' "  GitHub 用户:  $GITHUB_USER"
    printf '%b\n' "  GitHub 仓库:  $GITHUB_REPO"
    printf '%b\n' "  AUR 包名:    $AUR_PACKAGE"
    printf '%b\n' "  版本:        $PKG_VERSION"
    printf '%b\n' ""

    if [[ "$action" == '--push' ]] && { [[ -z "${MAINTAINER_NAME:-}" ]] || [[ -z "${MAINTAINER_EMAIL:-}" ]]; }; then
        prompt_user_input
    fi

    if [[ "$action" != '--no-confirm' ]] && [[ "$action" != '--help' ]]; then
        printf '继续执行? (y/N) '
        read -r answer
        if [[ ! "$answer" =~ ^[Yy]$ ]]; then
            printf '%b\n' "已取消。"
            exit 0
        fi
    fi

    fill_pkgbuild
    generate_srcinfo
    validate

    if [[ "$action" == '--push' ]]; then
        push_to_github
        push_to_aur
    fi

    printf '%b\n' ""
    printf '%b\n' "${GREEN}完成${NC}"
}

case "${1:-all}" in
    --help|-h)
        usage
        ;;
    *)
        main "$@"
        ;;
esac
