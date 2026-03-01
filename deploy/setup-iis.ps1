# IIS-Site-Manager IIS Setup Script
# Single site: ASP.NET Core serves API (/api/*) + static frontend (/*)
# Run as Administrator

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"
$DeployRoot = $PSScriptRoot
$SiteName = "IIS-Site-Manager"
$Port = 8081

Write-Host "Setting up IIS for IIS-Site-Manager..." -ForegroundColor Cyan

# Ensure Web Server role
$webServer = Get-WindowsFeature -Name Web-Server -ErrorAction SilentlyContinue
if (-not $webServer.Installed) {
    Write-Host "Installing IIS (Web-Server)..." -ForegroundColor Yellow
    Install-WindowsFeature -Name Web-Server -IncludeManagementTools
}

# Ensure ASP.NET Core Module
$aspNetModule = Get-WindowsFeature -Name Web-Asp-Net45 -ErrorAction SilentlyContinue
# For .NET Core hosting, need DotNetCore* or similar - IIS usually has it if .NET SDK installed

Import-Module WebAdministration -ErrorAction SilentlyContinue

# Remove existing site if present
$existing = Get-Website -Name $SiteName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "Removing existing site $SiteName..." -ForegroundColor Yellow
    Remove-Website -Name $SiteName
}

# Create app pool for API (.NET Core - No Managed Code)
$poolName = "IIS-Site-Manager-API"
if (-not (Test-Path "IIS:\AppPools\$poolName")) {
    New-WebAppPool -Name $poolName
}
Set-ItemProperty "IIS:\AppPools\$poolName" -Name "managedRuntimeVersion" -Value ""
# NetworkService has Performance Counter read permission (ApplicationPoolIdentity often returns CPU=0)
Set-ItemProperty "IIS:\AppPools\$poolName" -Name "processModel.identityType" -Value "NetworkService"

# Grant Performance Counter read permission (backup for ApplicationPoolIdentity)
$perfUser = "IIS AppPool\$poolName"
try {
    Add-LocalGroupMember -Group "Performance Monitor Users" -Member $perfUser -ErrorAction SilentlyContinue
    Write-Host "Added $perfUser to Performance Monitor Users (for CPU metrics)" -ForegroundColor Gray
} catch { }

# Single site: ASP.NET Core app serves both API and static frontend
$apiPath = Join-Path $DeployRoot "api"
$wwwroot = Join-Path $apiPath "wwwroot"

if (-not (Test-Path $apiPath)) { Write-Error "deploy/api not found. Run build.ps1 first." }
if (-not (Test-Path $wwwroot)) { Write-Error "deploy/api/wwwroot not found. Run build.ps1 first." }

# Create site - single app (no sub-application)
New-Website -Name $SiteName -PhysicalPath $apiPath -Port $Port -ApplicationPool $poolName
# Replace binding with *:port for remote access
Get-WebBinding -Name $SiteName -Protocol "http" | Remove-WebBinding
New-WebBinding -Name $SiteName -Protocol "http" -Port $Port -IPAddress "*"

# Allow port in Windows Firewall for remote access
$firewallRule = "IIS-Site-Manager-$Port"
New-NetFirewallRule -DisplayName $firewallRule -Direction Inbound -Protocol TCP -LocalPort $Port -Action Allow -ErrorAction SilentlyContinue | Out-Null

$hostname = [System.Net.Dns]::GetHostName()
$remoteUrl = "http://${hostname}:$Port"
# Try to get primary IP for remote access
$ip = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceAlias -notlike "*Loopback*" -and $_.IPAddress -notlike "169.*" } | Select-Object -First 1).IPAddress
Write-Host "`nIIS setup complete. Binding: *:$Port (all interfaces)" -ForegroundColor Green
Write-Host "  Local:   http://localhost:$Port" -ForegroundColor White
Write-Host "  Remote:  $remoteUrl" -ForegroundColor White
if ($ip) { Write-Host "  Or:      http://${ip}:$Port" -ForegroundColor White }
Write-Host "  API:     $remoteUrl/api" -ForegroundColor White

# Restart app pool so new Performance Monitor Users permission takes effect
Start-Sleep -Seconds 2
try { Stop-WebAppPool -Name $poolName -ErrorAction Stop; Start-Sleep -Seconds 2; Start-WebAppPool -Name $poolName }
catch { try { Start-WebAppPool -Name $poolName } catch { } }
Write-Host "`nApp pool recycled (for CPU permission to take effect)" -ForegroundColor Gray
