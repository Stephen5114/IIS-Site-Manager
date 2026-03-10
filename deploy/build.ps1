# IIS-Site-Manager Build Script
# Builds backend, frontend, and agent into separate deploy folders.

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot

$env:DOTNET_CLI_HOME = Join-Path $ProjectRoot ".dotnet"
$env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE = "1"
$env:APPDATA = Join-Path $ProjectRoot ".appdata"
$env:NUGET_PACKAGES = Join-Path $ProjectRoot ".nuget\packages"
$nugetConfig = Join-Path $ProjectRoot "NuGet.Config"

$backendSiteName = "IIS-Site-Manager-Backend"
$backendPoolName = "IIS-Site-Manager-Backend-Pool"
$frontendSiteName = "IIS-Site-Manager-Frontend"
$frontendPoolName = "IIS-Site-Manager-Frontend-Pool"

function Stop-IisIfPresent {
    param(
        [string]$SiteName,
        [string]$PoolName
    )

    try {
        Import-Module WebAdministration -ErrorAction SilentlyContinue

        $site = Get-Website -Name $SiteName -ErrorAction SilentlyContinue
        if ($site) {
            Write-Host "Stopping site '$SiteName'..." -ForegroundColor Yellow
            Stop-Website -Name $SiteName
        }

        if (Test-Path "IIS:\AppPools\$PoolName") {
            Write-Host "Stopping app pool '$PoolName'..." -ForegroundColor Yellow
            Stop-WebAppPool -Name $PoolName -ErrorAction SilentlyContinue
        }
    }
    catch {
        Write-Warning "Unable to stop IIS resources for $SiteName / ${PoolName}: $($_.Exception.Message)"
    }
}

function Restart-IisIfPresent {
    param(
        [string]$SiteName,
        [string]$PoolName
    )

    try {
        Import-Module WebAdministration -ErrorAction SilentlyContinue

        if (Test-Path "IIS:\AppPools\$PoolName") {
            Start-WebAppPool -Name $PoolName -ErrorAction SilentlyContinue
        }

        $site = Get-Website -Name $SiteName -ErrorAction SilentlyContinue
        if ($site -and $site.State -ne "Started") {
            Start-Website -Name $SiteName
        }
    }
    catch {
        Write-Warning "Unable to restart IIS resources for $SiteName / ${PoolName}: $($_.Exception.Message)"
    }
}

function Replace-DirectoryPreservingProductionConfig {
    param(
        [string]$SourcePath,
        [string]$DestinationPath
    )

    $backupProductionConfig = $null
    $productionConfigPath = Join-Path $DestinationPath "appsettings.Production.json"
    if (Test-Path $productionConfigPath) {
        $backupProductionConfig = Get-Content -Raw $productionConfigPath
    }

    if (-not (Test-Path $DestinationPath)) {
        New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
    }

    Get-ChildItem -Path $DestinationPath -Force | ForEach-Object {
        if ($_.Name -ne "appsettings.Production.json") {
            Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Get-ChildItem -Path $SourcePath -Force | ForEach-Object {
        Move-Item -Path $_.FullName -Destination $DestinationPath -Force
    }

    Remove-Item $SourcePath -Recurse -Force -ErrorAction SilentlyContinue

    if ($backupProductionConfig) {
        Set-Content -Path (Join-Path $DestinationPath "appsettings.Production.json") -Value $backupProductionConfig -Encoding UTF8
    }
}

Write-Host "Building IIS-Site-Manager deployment artifacts..." -ForegroundColor Cyan

Stop-IisIfPresent -SiteName $backendSiteName -PoolName $backendPoolName
Stop-IisIfPresent -SiteName $frontendSiteName -PoolName $frontendPoolName
Start-Sleep -Seconds 2

$apiTemp = Join-Path $ProjectRoot "deploy\api_temp"
$apiDest = Join-Path $ProjectRoot "deploy\api"
$webTemp = Join-Path $ProjectRoot "deploy\web_temp"
$webDest = Join-Path $ProjectRoot "deploy\web"
$agentDest = Join-Path $ProjectRoot "deploy\agent"

if (Test-Path $apiTemp) { Remove-Item $apiTemp -Recurse -Force }
if (Test-Path $webTemp) { Remove-Item $webTemp -Recurse -Force }

Write-Host "`n[1/4] Publishing backend to deploy/api..." -ForegroundColor Yellow
Push-Location (Join-Path $ProjectRoot "backend")
dotnet publish -c Release -o $apiTemp --no-self-contained `
    --configfile $nugetConfig
if ($LASTEXITCODE -ne 0) { Pop-Location; exit 1 }
Pop-Location
Replace-DirectoryPreservingProductionConfig -SourcePath $apiTemp -DestinationPath $apiDest

$logsDir = Join-Path $apiDest "logs"
if (-not (Test-Path $logsDir)) {
    New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
}

Write-Host "`n[2/4] Building frontend and exporting static site to deploy/web..." -ForegroundColor Yellow
Push-Location (Join-Path $ProjectRoot "frontend")
npm run build
if ($LASTEXITCODE -ne 0) { Pop-Location; exit 1 }
Pop-Location
Copy-Item -Path (Join-Path $ProjectRoot "frontend\out") -Destination $webTemp -Recurse -Force
Replace-DirectoryPreservingProductionConfig -SourcePath $webTemp -DestinationPath $webDest

Write-Host "`n[3/4] Publishing agent to deploy/agent..." -ForegroundColor Yellow
Push-Location (Join-Path $ProjectRoot "agent")
dotnet publish -c Release -o $agentDest --no-self-contained `
    --configfile $nugetConfig
if ($LASTEXITCODE -ne 0) { Pop-Location; exit 1 }
Pop-Location

Write-Host "`n[4/4] Restarting IIS resources if present..." -ForegroundColor Yellow
Restart-IisIfPresent -SiteName $backendSiteName -PoolName $backendPoolName
Restart-IisIfPresent -SiteName $frontendSiteName -PoolName $frontendPoolName

Write-Host "`nBuild complete." -ForegroundColor Green
Write-Host "  Backend: $apiDest" -ForegroundColor White
Write-Host "  Frontend: $webDest" -ForegroundColor White
Write-Host "  Agent: $agentDest" -ForegroundColor White
