#Requires -RunAsAdministrator

param(
    [string]$BackendSiteName = "IIS-Site-Manager-Backend",
    [string]$BackendPoolName = "IIS-Site-Manager-Backend-Pool",
    [int]$BackendPort = 5032,
    [string]$FrontendSiteName = "IIS-Site-Manager-Frontend",
    [string]$FrontendPoolName = "IIS-Site-Manager-Frontend-Pool",
    [int]$FrontendPort = 8082,
    [string]$AspNetCoreEnvironment = "Production",
    [switch]$RemoveLegacySingleSite
)

$ErrorActionPreference = "Stop"
$DeployRoot = $PSScriptRoot
$BackendPath = Join-Path $DeployRoot "api"
$FrontendPath = Join-Path $DeployRoot "web"

Write-Host "Setting up IIS for split backend/frontend deployment..." -ForegroundColor Cyan

Import-Module ServerManager -ErrorAction SilentlyContinue
$webServer = Get-WindowsFeature -Name Web-Server -ErrorAction SilentlyContinue
if ($webServer -and -not $webServer.Installed) {
    Write-Host "Installing IIS (Web-Server)..." -ForegroundColor Yellow
    Install-WindowsFeature -Name Web-Server -IncludeManagementTools
}

Import-Module WebAdministration -ErrorAction Stop

if (-not (Test-Path $BackendPath)) {
    throw "Backend deploy path not found: $BackendPath. Run .\build.ps1 first."
}

if (-not (Test-Path $FrontendPath)) {
    throw "Frontend deploy path not found: $FrontendPath. Run .\build.ps1 first."
}

if ($RemoveLegacySingleSite) {
    $legacySite = Get-Website -Name "IIS-Site-Manager" -ErrorAction SilentlyContinue
    if ($legacySite) {
        Write-Host "Removing legacy single-site deployment 'IIS-Site-Manager'..." -ForegroundColor Yellow
        Remove-Website -Name "IIS-Site-Manager"
    }
}

foreach ($poolName in @($BackendPoolName, $FrontendPoolName)) {
    if (-not (Test-Path "IIS:\AppPools\$poolName")) {
        New-WebAppPool -Name $poolName | Out-Null
    }
}

Set-ItemProperty "IIS:\AppPools\$BackendPoolName" -Name "managedRuntimeVersion" -Value ""
Set-ItemProperty "IIS:\AppPools\$BackendPoolName" -Name "processModel.identityType" -Value "NetworkService"

Set-ItemProperty "IIS:\AppPools\$FrontendPoolName" -Name "managedRuntimeVersion" -Value ""
Set-ItemProperty "IIS:\AppPools\$FrontendPoolName" -Name "processModel.identityType" -Value "ApplicationPoolIdentity"

try {
    Add-LocalGroupMember -Group "Performance Monitor Users" -Member "IIS AppPool\$BackendPoolName" -ErrorAction SilentlyContinue
}
catch {
}

foreach ($siteName in @($BackendSiteName, $FrontendSiteName)) {
    $site = Get-Website -Name $siteName -ErrorAction SilentlyContinue
    if ($site) {
        Write-Host "Removing existing site '$siteName'..." -ForegroundColor Yellow
        Remove-Website -Name $siteName
    }
}

Write-Host "Creating backend site '$BackendSiteName' on port $BackendPort..." -ForegroundColor Yellow
New-Website -Name $BackendSiteName -PhysicalPath $BackendPath -Port $BackendPort -ApplicationPool $BackendPoolName | Out-Null
Get-WebBinding -Name $BackendSiteName -Protocol "http" | Remove-WebBinding
New-WebBinding -Name $BackendSiteName -Protocol "http" -Port $BackendPort -IPAddress "*" | Out-Null

Write-Host "Creating frontend site '$FrontendSiteName' on port $FrontendPort..." -ForegroundColor Yellow
New-Website -Name $FrontendSiteName -PhysicalPath $FrontendPath -Port $FrontendPort -ApplicationPool $FrontendPoolName | Out-Null
Get-WebBinding -Name $FrontendSiteName -Protocol "http" | Remove-WebBinding
New-WebBinding -Name $FrontendSiteName -Protocol "http" -Port $FrontendPort -IPAddress "*" | Out-Null

$appCmd = Join-Path $env:SystemRoot "System32\inetsrv\appcmd.exe"
if (Test-Path $appCmd) {
    & $appCmd set config $BackendSiteName -section:system.webServer/aspNetCore "/-[environmentVariables.[name='ASPNETCORE_ENVIRONMENT']]" /commit:apphost 2>$null | Out-Null
    & $appCmd set config $BackendSiteName -section:system.webServer/aspNetCore "/+[environmentVariables.[name='ASPNETCORE_ENVIRONMENT',value='$AspNetCoreEnvironment']]" /commit:apphost | Out-Null
}

foreach ($rule in @(
    @{ Name = "IIS-Site-Manager-Backend-$BackendPort"; Port = $BackendPort },
    @{ Name = "IIS-Site-Manager-Frontend-$FrontendPort"; Port = $FrontendPort }
)) {
    New-NetFirewallRule -DisplayName $rule.Name -Direction Inbound -Protocol TCP -LocalPort $rule.Port -Action Allow -ErrorAction SilentlyContinue | Out-Null
}

Start-WebAppPool -Name $BackendPoolName -ErrorAction SilentlyContinue
Start-WebAppPool -Name $FrontendPoolName -ErrorAction SilentlyContinue
Start-Website -Name $BackendSiteName -ErrorAction SilentlyContinue
Start-Website -Name $FrontendSiteName -ErrorAction SilentlyContinue

$hostname = [System.Net.Dns]::GetHostName()
$ip = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.InterfaceAlias -notlike "*Loopback*" -and $_.IPAddress -notlike "169.*" } |
    Select-Object -First 1).IPAddress

Write-Host "`nIIS setup complete." -ForegroundColor Green
Write-Host "  Backend:  http://localhost:$BackendPort" -ForegroundColor White
Write-Host "  Frontend: http://localhost:$FrontendPort" -ForegroundColor White
Write-Host "  Backend env: ASPNETCORE_ENVIRONMENT=$AspNetCoreEnvironment" -ForegroundColor White
if ($ip) {
    Write-Host "  Remote backend:  http://${ip}:$BackendPort" -ForegroundColor White
    Write-Host "  Remote frontend: http://${ip}:$FrontendPort" -ForegroundColor White
}
Write-Host "  Host backend:  http://${hostname}:$BackendPort" -ForegroundColor White
Write-Host "  Host frontend: http://${hostname}:$FrontendPort" -ForegroundColor White
