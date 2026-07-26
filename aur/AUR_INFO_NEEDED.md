# AUR 提交需要手动提供的信息

## 必需的硬性信息（必须提供）

| 字段 | 格式 | 示例 | 说明 |
|------|------|------|------|
| **GitHub 用户名** | 小写字母+数字 | `yourname` | 仓库所在用户名 |
| **Maintainer 姓名** | 真实姓名 | `Your Real Name` | AUR 上显示的姓名 |
| **Maintainer 邮箱** | 有效邮箱 | `your.email@example.com` | AUR 上显示的邮箱 |

## 提供方式

### 方法 1: 环境变量 (推荐)
```bash
export AUR_GITHUB_USER="你的GitHub用户名"
export AUR_MAINTAINER_NAME="你的真实姓名"
export AUR_MAINTAINER_EMAIL="你的邮箱@example.com"
export PKG_VERSION="1.1.0"  # 可选, 默认 1.1.0

bash aur/build-aur-package.sh
```

### 方法 2: 交互式输入
直接运行脚本，脚本会询问：
```bash
bash aur/build-aur-package.sh
# 然后按提示输入
```

## 你需要手动做的事 (无法自动化)

### 1. GitHub 仓库创建
1. 访问 https://github.com/new
2. 仓库名填: `lx-music-shell`
3. 可见性: **Public**
4. **不要**勾选 "Initialize with README"
5. 点击 Create repository

### 2. 推送代码到 GitHub
```bash
cd /home/issac/Proj/LX-Music-Shell

# 添加 GitHub 远程仓库
git remote add origin https://github.com/你的用户名/lx-music-shell.git

# 推送主分支
git push -u origin master

# 创建版本 tag
git tag -a v1.1.0 -m "Release v1.1.0"
git push origin v1.1.0
```

### 3. 创建 GitHub Release (可选但推荐)
1. 访问 https://github.com/你的用户名/lx-music-shell/releases/new
2. 选择 tag `v1.1.0`
3. 标题: `LX-Music-Shell v1.1.0`
4. 描述发布说明
5. 点击 Publish

### 4. 注册 AUR 账号
1. 访问 https://aur.archlinux.org/register
2. 填写用户名、邮箱、密码
3. 验证邮箱

### 5. 配置 AUR SSH 密钥
1. 生成 SSH 密钥:
   ```bash
   ssh-keygen -t ed25519 -C "你的邮箱@example.com"
   ```
2. 复制公钥:
   ```bash
   cat ~/.ssh/id_ed25519.pub
   ```
3. 访问 https://aur.archlinux.org/account/
4. 粘贴公钥到 "SSH Public Key" 字段

### 6. 提交到 AUR
```bash
# 克隆 AUR 空仓库
git clone ssh://aur@aur.archlinux.org/lx-music-shell.git /tmp/aur-pkg

# 复制已准备好的文件 (脚本会自动填充)
cp aur/PKGBUILD aur/.SRCINFO aur/lx-music-shell.install \
   aur/lx-music-shell.1 aur/lx-music-shell.bash \
   aur/lx-music-shell.desktop /tmp/aur-pkg/

# 提交
cd /tmp/aur-pkg
git add .
git config user.name "你的名字"
git config user.email "你的邮箱@example.com"
git commit -m "Initial upload: lx-music-shell v1.1.0"
git push
```

## 脚本会自动填充的信息

### ✨ 自动填充
- ✅ Maintainer 姓名和邮箱 (PKGBUILD 第一行)
- ✅ GitHub 仓库 URL (url 字段)
- ✅ Source 下载 URL (指向 GitHub releases)
- ✅ pkgname, pkgver, pkgrel

### ✨ 自动生成
- ✅ `.SRCINFO` (从 PKGBUILD 自动生成)
- ✅ 源码包 (lx-music-shell-1.1.0.tar.gz)

### ✨ 自动验证
- ✅ 所有包名是否存在
- ✅ 字段完整性
- ✅ 无占位符残留

## 验证清单

提交前请确认:
- [ ] 在 GitHub 上能看到 https://github.com/你的用户名/lx-music-shell
- [ ] 可以访问 https://github.com/你的用户名/lx-music-shell/archive/refs/tags/v1.1.0.tar.gz
- [ ] AUR 账户已注册
- [ ] SSH 密钥已配置
- [ ] 本地 `makepkg -si` 测试通过 (如果可以)
- [ ] `namcap PKGBUILD` 无错误 (如果可以)

## 提交后

提交后访问 https://aur.archlinux.org/packages/lx-music-shell 查看你的包。

等待几分钟后任何人都可以通过 `yay -S lx-music-shell` 安装你的包了!

## 常见问题

### Q: 包名已被占用怎么办?
A: 在 AUR 搜索 `lx-music-shell`，如果被占用，可以改名如:
- `lx-mus-shell`
- `lxms-bin`
- `music-shell`
- `lx-music-shell-git`

### Q: 提交后审核不通过怎么办?
A: AUR 是仓库, 无审核机制, 直接推送即可。但用户会评论问题, 需及时修复。

### Q: 如何更新版本?
1. 修改代码
2. `cd /home/issac/Proj/LX-Music-Shell/aur && bash build-aur-package.sh`
3. 推送到 GitHub: `git push origin master v1.1.1`
4. 推送到 AUR:
   ```bash
   cd /tmp/aur-pkg
   git pull
   # 复制新文件
   cp ../aur/PKGBUILD ../aur/.SRCINFO .
   git add . && git commit -m "Update to v1.1.1" && git push
   ```