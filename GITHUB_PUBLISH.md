# 发布到 GitHub 指南

## 1. 安装 Git

从 https://git-scm.com/download/win 下载并安装 Git for Windows。

安装完成后，**重启终端**使 `git` 命令生效。

## 2. 配置 Git（首次使用）

```powershell
git config --global user.name "你的用户名"
git config --global user.email "你的邮箱@example.com"
```

## 3. 在 GitHub 创建仓库

1. 登录 https://github.com
2. 点击右上角 **+** → **New repository**
3. 仓库名填写：`IIS-Site-Manager`（或自定义）
4. 选择 **Public**
5. **不要**勾选 "Add a README file"（本地已有）
6. 点击 **Create repository**

## 4. 推送代码

在 PowerShell 中执行（将 `YOUR_USERNAME` 替换为你的 GitHub 用户名）：

```powershell
cd c:\Users\Administrator\Desktop\hosting_web\IIS-Site-Manager

# 初始化仓库
git init

# 添加所有文件
git add .

# 首次提交
git commit -m "Initial commit: IIS Site Manager with Next.js frontend and .NET 10 backend"

# 添加远程仓库（替换为你的仓库地址）
git remote add origin https://github.com/YOUR_USERNAME/IIS-Site-Manager.git

# 推送到 main 分支
git branch -M main
git push -u origin main
```

## 5. 若使用 SSH

若已配置 SSH 密钥：

```powershell
git remote add origin git@github.com:YOUR_USERNAME/IIS-Site-Manager.git
git push -u origin main
```

## 6. 若需要登录

推送时若提示输入凭据：
- **用户名**：GitHub 用户名
- **密码**：使用 **Personal Access Token**（Settings → Developer settings → Personal access tokens）而非登录密码
