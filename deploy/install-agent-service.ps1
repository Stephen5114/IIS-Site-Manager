#Requires -RunAsAdministrator

param(
    [string]$ServiceName = "IIS-Site-Manager-Agent",
    [string]$DisplayName = "IIS Site Manager Agent",
    [string]$Description = "Collects node metrics and reports to IIS-Site-Manager control-plane.",
    [string]$AgentDir = "$PSScriptRoot\agent",
    [string]$BackendBaseUrl = "http://localhost:5032",
    [string]$NodeName = $env:COMPUTERNAME,
    [string]$PublicHost = $env:COMPUTERNAME,
    [bool]$Enabled = $true,
    [int]$MetricsIntervalSeconds = 15,
    [int]$JobPollIntervalSeconds = 10,
    [int]$RequestTimeoutSeconds = 10,
    [string]$ServiceAccount = "LocalSystem"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $AgentDir)) {
    throw "Agent publish directory not found: $AgentDir"
}

$serviceExe = Join-Path $AgentDir "IIS-Site-Manager.Agent.exe"
$serviceDll = Join-Path $AgentDir "IIS-Site-Manager.Agent.dll"

if (Test-Path $serviceExe) {
    $binPath = "`"$serviceExe`" --environment Production"
}
elseif (Test-Path $serviceDll) {
    $dotnetPath = (Get-Command dotnet -ErrorAction SilentlyContinue).Source
    if (-not $dotnetPath) {
        throw "dotnet runtime not found in PATH, and no .exe found in publish output."
    }
    $binPath = "`"$dotnetPath`" `"$serviceDll`" --environment Production"
}
else {
    throw "Neither IIS-Site-Manager.Agent.exe nor IIS-Site-Manager.Agent.dll found in $AgentDir."
}

Write-Host "Writing appsettings.Production.json..." -ForegroundColor Cyan
$productionConfigPath = Join-Path $AgentDir "appsettings.Production.json"
$productionConfig = @{
    Agent = @{
        BackendBaseUrl = $BackendBaseUrl
        NodeName = $NodeName
        PublicHost = $PublicHost
        Enabled = $Enabled
        MetricsIntervalSeconds = $MetricsIntervalSeconds
        JobPollIntervalSeconds = $JobPollIntervalSeconds
        RequestTimeoutSeconds = $RequestTimeoutSeconds
    }
}
$productionConfig | ConvertTo-Json -Depth 8 | Set-Content -Path $productionConfigPath -Encoding UTF8

Write-Host "Granting read permission to service account..." -ForegroundColor Cyan
icacls $AgentDir /grant "${ServiceAccount}:(OI)(CI)RX" /T | Out-Null

$existing = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "Service exists. Updating..." -ForegroundColor Yellow
    if ($existing.Status -ne "Stopped") {
        Stop-Service -Name $ServiceName -Force
        Start-Sleep -Seconds 2
    }
    sc.exe config $ServiceName binPath= "$binPath" start= auto obj= "$ServiceAccount" DisplayName= "$DisplayName" | Out-Null
}
else {
    Write-Host "Creating service..." -ForegroundColor Yellow
    sc.exe create $ServiceName binPath= "$binPath" start= auto obj= "$ServiceAccount" DisplayName= "$DisplayName" | Out-Null
}

sc.exe description $ServiceName $Description | Out-Null
sc.exe failure $ServiceName reset= 86400 actions= restart/5000/restart/15000/restart/30000 | Out-Null
sc.exe failureflag $ServiceName 1 | Out-Null

Write-Host "Starting service..." -ForegroundColor Cyan
Start-Service -Name $ServiceName
Start-Sleep -Seconds 1

$svc = Get-Service -Name $ServiceName
Write-Host "Service '$ServiceName' is $($svc.Status)." -ForegroundColor Green
Write-Host "AgentDir: $AgentDir" -ForegroundColor Gray
Write-Host "BackendBaseUrl: $BackendBaseUrl" -ForegroundColor Gray
Write-Host "NodeName: $NodeName | PublicHost: $PublicHost" -ForegroundColor Gray
