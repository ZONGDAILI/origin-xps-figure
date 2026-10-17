# 一键把本地仓库推到 GitHub
# 前置：1) 已在 GitHub 网页上创建**空仓库**（不要勾 README / .gitignore / license）
#       2) 本机能访问 github.com（系统代理/VPN 已开启；api.github.com 通不代表 github.com 通）
# 用法：.\push-to-github.ps1                      # 默认 ZONGDAILI/origin-xps-figure
#       .\push-to-github.ps1 -User someone -Repo myrepo
param(
    [string]$User = 'ZONGDAILI',
    [string]$Repo = 'origin-xps-figure',
    [string]$Branch = 'main'
)

$ErrorActionPreference = 'Stop'
$git = "C:\Program Files\Git\cmd\git.exe"
if (-not (Test-Path $git)) { $git = (Get-Command git -ErrorAction Stop).Source }

function Test-GitHub {
    try {
        $r = Invoke-WebRequest 'https://github.com' -UseBasicParsing -TimeoutSec 8 -MaximumRedirection 2
        return $r.StatusCode -eq 200
    } catch { return $false }
}

Write-Host "1) 检查 github.com 连通性 ..."
if (-not (Test-GitHub)) {
    Write-Host "   ✗ github.com 不可达。" -ForegroundColor Red
    Write-Host "     请先开启系统代理/VPN（Clash Verge 等），或改用浏览器拖拽上传："
    Write-Host "     仓库页 → Add file → Upload files → 把本目录下的文件/文件夹拖进去"
    exit 1
}
Write-Host "   ✓ 可访问"

Write-Host "2) 配置 remote ..."
$remote = "https://github.com/$User/$Repo.git"
$has = (& $git remote) -contains 'origin'
if ($has) { & $git remote set-url origin $remote } else { & $git remote add origin $remote }
Write-Host "   origin -> $remote"

Write-Host "3) 推送（首次会弹出浏览器登录 GitHub，点授权即可）..."
& $git push -u origin $Branch
if ($LASTEXITCODE -ne 0) {
    Write-Host "   ✗ 推送失败。常见原因：" -ForegroundColor Red
    Write-Host "     - 网页创建仓库时勾了 README/.gitignore/LICENSE（远端非空）→ 改执行："
    Write-Host "       git pull --rebase origin $Branch ; git push -u origin $Branch"
    Write-Host "     - 未完成浏览器登录 → 重跑本脚本"
    exit 1
}
Write-Host "   ✓ 推送完成：$remote" -ForegroundColor Green
Write-Host ""
Write-Host "接下来（网页上 2 分钟）："
Write-Host "  A. 加 Topics：仓库页右侧 About → 齿轮 → 填 xps, origin, originpro, agents-skill, deepseek-harness, scientific-figures"
Write-Host "  B. 发 Release：Releases → Draft a new release → tag v1.0 → 上传 dist/origin-xps-figure-skill.zip"
