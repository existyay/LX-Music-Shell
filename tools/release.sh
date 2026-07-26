#!/usr/bin/env bash
#==============================================================================
# LX-Music-Shell 版本发布脚本
# 用于自动化版本号更新、标签创建、提交和发布流程
#
# 用法:
#   ./tools/release.sh patch       # 1.1.1 -> 1.1.2
#   ./tools/release.sh minor       # 1.1.1 -> 1.2.0
#   ./tools/release.sh major       # 1.1.1 -> 2.0.0
#   ./tools/release.sh 1.2.3       # 指定具体版本号
#
# 每次提交小版本，每十次小版本后提交一次大版本
# 小版本 (patch): bug 修复
# 中版本 (minor): 新功能
# 大版本 (major): 重大变更
#==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
VERSION_FILE="$PROJECT_DIR/lx-music-shell"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 打印彩色输出
info() { printf '%b\n' "${CYAN}[INFO]${NC} $*"; }
success() { printf '%b\n' "${GREEN}[✓]${NC} $*"; }
warn() { printf '%b\n' "${YELLOW}[!]${NC} $*"; }
error() { printf '%b\n' "${RED}[✗]${NC} $*"; }

# 从脚本获取当前版本
get_current_version() {
    grep -E '^VERSION=' "$VERSION_FILE" | head -1 | sed 's/^VERSION="//; s/"$//'
}

# 更新脚本中的 VERSION 行
update_version() {
    local new_version="$1"
    sed -i "s/^VERSION=\"[0-9.]*\"$/VERSION=\"$new_version\"/" "$VERSION_FILE"
    success "更新 VERSION=$new_version"
}

# 更新 PKGBUILD
update_pkgbuild() {
    local new_version="$1"
    local pkgbuild="$PROJECT_DIR/aur/PKGBUILD"

    sed -i "s/^pkgver=.*/pkgver=$new_version/" "$pkgbuild"

    # 重置 pkgrel=1 因为新版本
    sed -i "s/^pkgrel=.*/pkgrel=1/" "$pkgbuild"

    # 更新 source URL 引用
    sed -i "s|source=(\"lx-music-shell-source-v[0-9.]*\.tar\.gz|source=(\"lx-music-shell-source-v$new_version.tar.gz|" "$pkgbuild"

    success "更新 PKGBUILD pkgver=$new_version"
}

# 更新 .SRCINFO
update_srcinfo() {
    info "重新生成 .SRCINFO..."
    cd "$PROJECT_DIR"
    rm -f aur/.SRCINFO
    if command -v makepkg &>/dev/null; then
        if (cd aur && makepkg --printsrcinfo > .SRCINFO 2>/dev/null); then
            success ".SRCINFO 已生成 (makepkg)"
        else
            warn "makepkg 不可用,使用备用脚本生成"
            bash aur/build-aur-package.sh --no-confirm 2>&1 | tail -3 || true
        fi
    else
        bash aur/build-aur-package.sh --no-confirm 2>&1 | tail -3 || true
    fi
}

# 计算新版本号
bump_version() {
    local current="$1"
    local bump_type="$2"

    IFS='.' read -r major minor patch <<< "$current"

    case "$bump_type" in
        patch)
            patch=$((patch + 1))
            ;;
        minor)
            minor=$((minor + 1))
            patch=0
            ;;
        major)
            major=$((major + 1))
            minor=0
            patch=0
            ;;
        *)
            # 当作完整版本号处理
            echo "$bump_type"
            return
            ;;
    esac

    echo "$major.$minor.$patch"
}

# 检查是否有未提交的变更
check_clean() {
    if [[ -n "$(cd "$PROJECT_DIR" && git status --porcelain)" ]]; then
        warn "存在未提交的变更:"
        cd "$PROJECT_DIR" && git status --short | head -10
        echo ""
        read -rp "是否继续? [y/N] " answer
        [[ "$answer" =~ ^[Yy]$ ]]
    fi
}

# 创建 git tag
create_tag() {
    local version="$1"
    cd "$PROJECT_DIR"

    if git rev-parse "v$version" >/dev/null 2>&1; then
        warn "Tag v$version 已存在"
        return 1
    fi

    git tag -a "v$version" -m "Release v$version"
    success "已创建 tag v$version"
}

# 提交变更
commit_release() {
    local version="$1"
    cd "$PROJECT_DIR"

    git add lx-music-shell aur/PKGBUILD aur/.SRCINFO

    if [[ -n "$(git status --porcelain)" ]]; then
        git commit -m "release: v$version

Automatically versioned by tools/release.sh

Changes:
- Bug fixes and code quality improvements
- Updated PKGBUILD and .SRCINFO"
        success "已提交 v$version"
    else
        info "无文件需要提交"
    fi
}

# 推送到 GitHub
push_github() {
    local version="$1"
    cd "$PROJECT_DIR"

    if ! command -v ssh-add &>/dev/null; then
        warn "ssh-add 不可用,跳过 GitHub 推送"
        return 0
    fi

    info "推送 GitHub..."
    if git push origin master 2>&1; then
        success "已推送 master"
    else
        warn "master 推送失败 (可能需要 SSH key)"
        return 1
    fi

    if git push origin "v$version" 2>&1; then
        success "已推送 tag v$version"
    else
        warn "tag 推送失败"
        return 1
    fi
}

# 同步 AUR
push_aur() {
    local version="$1"
    cd "$PROJECT_DIR"

    if [[ ! -f ~/.ssh/aur_key ]]; then
        warn "找不到 AUR SSH key (~/.ssh/aur_key),跳过 AUR 推送"
        info "如需推送到 AUR:"
        echo "  bash aur/push-to-aur.sh"
        return 0
    fi

    info "推送 AUR..."
    if bash aur/push-to-aur.sh 2>&1; then
        success "AUR 推送完成"
    else
        warn "AUR 推送失败,可手动运行: bash aur/push-to-aur.sh"
    fi
}

# 主流程
main() {
    local bump_arg="${1:-patch}"

    printf '%b\n' "${BLUE}========================================${NC}"
    printf '%b\n' "${BLUE}  LX-Music-Shell 版本发布工具${NC}"
    printf '%b\n' "${BLUE}========================================${NC}"
    echo ""

    local current_version
    current_version=$(get_current_version)
    info "当前版本: $current_version"

    local new_version
    new_version=$(bump_version "$current_version" "$bump_arg")
    info "新版本:   $new_version"
    echo ""

    # 确认
    read -rp "确认发布 v$new_version? [Y/n] " answer
    if [[ "$answer" =~ ^[Nn]$ ]]; then
        warn "已取消"
        exit 0
    fi

    # 检查工作目录
    check_clean || { error "工作目录不干净,已取消"; exit 1; }

    echo ""
    printf '%b\n' "${BLUE}[1/6]${NC} 更新版本号"
    update_version "$new_version"

    printf '%b\n' "${BLUE}[2/6]${NC} 更新 PKGBUILD"
    update_pkgbuild "$new_version"

    printf '%b\n' "${BLUE}[3/6]${NC} 重新生成 .SRCINFO"
    update_srcinfo

    printf '%b\n' "${BLUE}[4/6]${NC} 创建 Git tag"
    create_tag "$new_version"

    printf '%b\n' "${BLUE}[5/6]${NC} 提交变更"
    commit_release "$new_version"

    printf '%b\n' "${BLUE}[6/6]${NC} 推送到远程"
    echo ""
    push_github "$new_version"
    echo ""
    push_aur "$new_version"

    echo ""
    printf '%b\n' "${GREEN}========================================${NC}"
    printf '%b\n' "${GREEN}  v$new_version 发布完成！${NC}"
    printf '%b\n' "${GREEN}========================================${NC}"
    echo ""
    info "GitHub: https://github.com/existyay/LX-Music-Shell/releases/tag/v$new_version"
    info "AUR:    https://aur.archlinux.org/packages/lx-music-shell"
}

main "$@"