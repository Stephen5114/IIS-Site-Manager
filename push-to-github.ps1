# 推送到 GitHub
# 使用前：在 https://github.com/new 创建空仓库，然后将下面 YOUR_USERNAME 改为你的 GitHub 用户名

param(
    [Parameter(Mandatory=$true)]
    [string]$RepoUrl
)

$gitPath = "C:\Program Files\Git\bin\git.exe"
$projectPath = "c:\Users\Administrator\Desktop\hosting_web\IIS-Site-Manager"

Set-Location $projectPath

# 检查是否已存在 origin
$remote = & $gitPath remote show origin 2>&1
if ($LASTEXITCODE -eq 0) {
    & $gitPath remote set-url origin $RepoUrl
} else {
    & $gitPath remote add origin $RepoUrl
}

# 重命名分支为 main（如需要）
& $gitPath branch -M main

# 推送
& $gitPath push -u origin main

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n推送成功！" -ForegroundColor Green
    Write-Host "仓库地址: $RepoUrl" -ForegroundColor Cyan
} else {
    Write-Host "`n推送失败。若需登录，请使用 GitHub Personal Access Token 作为密码。" -ForegroundColor Yellow
}
