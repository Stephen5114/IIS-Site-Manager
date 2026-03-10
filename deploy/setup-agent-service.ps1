#Requires -RunAsAdministrator

param(
    [string]$ServiceName = "IIS-Site-Manager-Agent",
    [string]$DisplayName = "IIS Site Manager Agent",
    [string]$Description = "Collects node metrics and reports to IIS-Site-Manager control-plane.",
    [string]$Configuration = "Release",
    [string]$PublishDir = "$PSScriptRoot\agent",
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
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$AgentProject = Join-Path $ProjectRoot "agent\IIS-Site-Manager.Agent.csproj"

if (-not (Test-Path $AgentProject)) {
    throw "Agent project not found: $AgentProject"
}

Write-Host "Publishing agent..." -ForegroundColor Cyan
dotnet publish $AgentProject -c $Configuration -o $PublishDir --no-self-contained
if ($LASTEXITCODE -ne 0) {
    throw "dotnet publish failed."
}

$productionConfigPath = Join-Path $PublishDir "appsettings.Production.json"
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

$serviceExe = Join-Path $PublishDir "IIS-Site-Manager.Agent.exe"
$serviceDll = Join-Path $PublishDir "IIS-Site-Manager.Agent.dll"

if (Test-Path $serviceExe) {
    $binPath = "`"$serviceExe`" --environment Production"
}
elseif (Test-Path $serviceDll) {
    $dotnetPath = (Get-Command dotnet).Source
    $binPath = "`"$dotnetPath`" `"$serviceDll`" --environment Production"
}
else {
    throw "Publish output is missing both exe and dll."
}

Write-Host "Granting read access to service account..." -ForegroundColor Cyan
if ($ServiceAccount -like 'NT AUTHORITY\*') {
    icacls $PublishDir /grant "$ServiceAccount:(OI)(CI)RX" /T | Out-Null
}

$existing = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "Service exists. Updating configuration..." -ForegroundColor Yellow
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
Write-Host "PublishDir: $PublishDir" -ForegroundColor Gray
Write-Host "BackendBaseUrl: $BackendBaseUrl" -ForegroundColor Gray
Write-Host "NodeName: $NodeName | PublicHost: $PublicHost" -ForegroundColor Gray
Write-Host "ServiceAccount: $ServiceAccount" -ForegroundColor Gray
