# IIS-Site-Manager Build Script
# Builds backend + frontend into deploy/api (single app)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot

Write-Host "Building IIS-Site-Manager..." -ForegroundColor Cyan

# Stop IIS site and recycle app pool (to release file locks)
try {
    Import-Module WebAdministration -ErrorAction SilentlyContinue
    $site = Get-Website -Name "IIS-Site-Manager" -ErrorAction SilentlyContinue
    if ($site) {
        Write-Host "Stopping IIS-Site-Manager site and recycling app pool..." -ForegroundColor Yellow
        Stop-Website -Name "IIS-Site-Manager"
        $pool = Get-ChildItem "IIS:\AppPools" -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq "IIS-Site-Manager-API" }
        if ($pool) { $pool | Stop-WebAppPool }
        Start-Sleep -Seconds 5
    }
} catch { }

# Build backend - publish to api_temp then swap (avoids file lock from running IIS)
Write-Host "`n[1/3] Publishing backend..." -ForegroundColor Yellow
$apiTemp = "$ProjectRoot\deploy\api_temp"
$apiDest = "$ProjectRoot\deploy\api"
Push-Location $ProjectRoot\backend
dotnet publish -c Release -o $apiTemp --no-self-contained
if ($LASTEXITCODE -ne 0) { Pop-Location; exit 1 }
Pop-Location
# Swap: remove old api, move api_temp to api
if (Test-Path $apiDest) {
    Remove-Item $apiDest -Recurse -Force -ErrorAction Stop
}
Move-Item -Path $apiTemp -Destination $apiDest -Force

# Ensure logs folder exists (ANCM needs it for stdout)
$logsDir = Join-Path $apiDest "logs"
if (-not (Test-Path $logsDir)) { New-Item -ItemType Directory -Path $logsDir -Force | Out-Null }

# Ensure web.config has stdout logging (logs folder created above)

# Build frontend
Write-Host "`n[2/3] Building frontend..." -ForegroundColor Yellow
Push-Location $ProjectRoot\frontend
npm run build
if ($LASTEXITCODE -ne 0) { Pop-Location; exit 1 }
Pop-Location

# Copy frontend into api/wwwroot (single app: API + static frontend)
Write-Host "`n[3/3] Copying frontend to deploy/api/wwwroot..." -ForegroundColor Yellow
$outDir = "$ProjectRoot\frontend\out"
if (-not (Test-Path $outDir)) { Write-Error "Frontend out folder not found. Run 'npm run build' in frontend." }
$wwwroot = "$apiDest\wwwroot"
if (Test-Path $wwwroot) { Remove-Item $wwwroot -Recurse -Force }
Copy-Item -Path $outDir -Destination $wwwroot -Recurse -Force

# Restart site if it was stopped
try {
    $site = Get-Website -Name "IIS-Site-Manager" -ErrorAction SilentlyContinue
    if ($site -and $site.State -ne "Started") {
        Start-Website -Name "IIS-Site-Manager"
        Write-Host "Site restarted." -ForegroundColor Green
    }
} catch { }

Write-Host "`nBuild complete. Run .\setup-iis.ps1 to deploy to IIS (if not already done)." -ForegroundColor Green
