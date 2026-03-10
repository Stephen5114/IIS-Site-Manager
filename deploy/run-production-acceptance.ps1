#Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$BackendBaseUrl = "http://localhost:5032",
    [int]$TimeoutSeconds = 180,
    [switch]$CleanupOnSuccess,
    [string]$RemoteHost
)

$ErrorActionPreference = "Stop"

$script:RunId = "acc-" + [DateTime]::UtcNow.ToString("yyyyMMddHHmmss")
$script:Summary = [ordered]@{
    runId = $script:RunId
    customerId = $null
    siteId = $null
    jobId = $null
    nodeId = $null
    remoteHost = $RemoteHost
    finalStatus = "running"
    cleanupStatus = "not_started"
    error = $null
}

function Write-Step {
    param([string]$Message)
    Write-Host "[acceptance] $Message" -ForegroundColor Cyan
}

function Get-RequiredEnv {
    param([string]$Name)

    $value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Missing required environment variable '$Name'."
    }

    return $value
}

function Get-OptionalEnv {
    param(
        [string]$Name,
        [string]$Default = ""
    )

    $value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $Default
    }

    return $value
}

function Invoke-JsonRequest {
    param(
        [string]$Method,
        [string]$Url,
        [hashtable]$Headers = @{},
        $Body = $null
    )

    $invokeSplat = @{
        Method      = $Method
        Uri         = $Url
        Headers     = $Headers
        TimeoutSec  = 30
        ErrorAction = "Stop"
    }

    if ($null -ne $Body) {
        $invokeSplat.ContentType = "application/json"
        $invokeSplat.Body = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 10 }
    }

    try {
        return Invoke-RestMethod @invokeSplat
    }
    catch {
        $response = $_.Exception.Response
        if ($response) {
            $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
            $details = $reader.ReadToEnd()
            $reader.Dispose()
            throw "Request failed: $Method $Url returned $([int]$response.StatusCode). $details"
        }

        throw
    }
}

function New-WinRMCredential {
    $username = Get-RequiredEnv "IIS_SMOKE_WINRM_USERNAME"
    $password = Get-RequiredEnv "IIS_SMOKE_WINRM_PASSWORD"
    $secure = ConvertTo-SecureString $password -AsPlainText -Force
    return New-Object System.Management.Automation.PSCredential($username, $secure)
}

function Invoke-RemoteCheck {
    param(
        [string]$HostName,
        [string]$SiteName,
        [string]$PhysicalPath,
        [string]$AppPoolName
    )

    $port = [int](Get-OptionalEnv "IIS_SMOKE_WINRM_PORT" "5985")
    $auth = Get-OptionalEnv "IIS_SMOKE_WINRM_AUTH" "Basic"
    $cred = New-WinRMCredential

    Invoke-Command -ComputerName $HostName -Port $port -Credential $cred -Authentication $auth -ScriptBlock {
        param($RemoteSiteName, $RemotePhysicalPath, $RemoteAppPoolName)

        Import-Module WebAdministration

        $site = Get-Website -Name $RemoteSiteName -ErrorAction SilentlyContinue
        if (-not $site) {
            throw "Remote IIS site '$RemoteSiteName' was not found."
        }

        if ($site.State -ne "Started") {
            throw "Remote IIS site '$RemoteSiteName' is '$($site.State)', expected 'Started'."
        }

        $appPool = Get-Item "IIS:\AppPools\$RemoteAppPoolName" -ErrorAction SilentlyContinue
        if (-not $appPool) {
            throw "Remote application pool '$RemoteAppPoolName' was not found."
        }

        $indexPath = Join-Path $RemotePhysicalPath "index.html"
        if (-not (Test-Path $indexPath)) {
            throw "Remote site content '$indexPath' was not found."
        }

        [pscustomobject]@{
            siteName = $site.Name
            siteState = $site.State
            physicalPath = $site.PhysicalPath
            appPoolName = $RemoteAppPoolName
            indexPath = $indexPath
        }
    } -ArgumentList $SiteName, $PhysicalPath, $AppPoolName
}

function Invoke-RemoteCleanup {
    param(
        [string]$HostName,
        [string]$SiteName,
        [string]$PhysicalPath,
        [string]$AppPoolName
    )

    $port = [int](Get-OptionalEnv "IIS_SMOKE_WINRM_PORT" "5985")
    $auth = Get-OptionalEnv "IIS_SMOKE_WINRM_AUTH" "Basic"
    $cred = New-WinRMCredential

    Invoke-Command -ComputerName $HostName -Port $port -Credential $cred -Authentication $auth -ScriptBlock {
        param($RemoteSiteName, $RemotePhysicalPath, $RemoteAppPoolName)

        Import-Module WebAdministration

        $site = Get-Website -Name $RemoteSiteName -ErrorAction SilentlyContinue
        if ($site) {
            Remove-Website -Name $RemoteSiteName
        }

        if (Test-Path "IIS:\AppPools\$RemoteAppPoolName") {
            Remove-Item "IIS:\AppPools\$RemoteAppPoolName" -Recurse -Force
        }

        if (Test-Path $RemotePhysicalPath) {
            Remove-Item $RemotePhysicalPath -Recurse -Force
        }
    } -ArgumentList $SiteName, $PhysicalPath, $AppPoolName
}

function Resolve-SqlConnectionString {
    $fromEnv = Get-OptionalEnv "IIS_SMOKE_SQL_CONNECTION"
    if (-not [string]::IsNullOrWhiteSpace($fromEnv)) {
        return $fromEnv
    }

    $candidates = @(
        (Join-Path $PSScriptRoot "api\appsettings.Production.json"),
        (Join-Path (Split-Path -Parent $PSScriptRoot) "backend\bin\Release\net10.0\appsettings.Production.json")
    )

    foreach ($candidate in $candidates) {
        if (-not (Test-Path $candidate)) {
            continue
        }

        $json = Get-Content -Raw $candidate | ConvertFrom-Json
        $conn = $json.ConnectionStrings.Default
        if (-not [string]::IsNullOrWhiteSpace($conn)) {
            return [string]$conn
        }
    }

    throw "Unable to resolve a SQL connection string for cleanup. Set IIS_SMOKE_SQL_CONNECTION or place appsettings.Production.json beside the deployed API."
}

function Invoke-DbCleanup {
    param(
        [string]$RunId,
        [string]$Email,
        [string]$CustomerId,
        [string]$SiteId
    )

    $connectionString = Resolve-SqlConnectionString
    $connection = New-Object System.Data.SqlClient.SqlConnection $connectionString
    $connection.Open()

    try {
        $command = $connection.CreateCommand()
        $commandText = New-Object System.Collections.Generic.List[string]
        if (-not [string]::IsNullOrWhiteSpace($SiteId)) {
            $commandText.Add("DELETE FROM ProvisionJobs WHERE HostedSiteId = @siteId OR CustomerId = @customerId;")
            $commandText.Add("DELETE FROM HostedSites WHERE Id = @siteId OR CustomerId = @customerId;")
            [void]$command.Parameters.Add("@siteId", [System.Data.SqlDbType]::UniqueIdentifier)
            $command.Parameters["@siteId"].Value = [Guid]$SiteId
        }
        else {
            $commandText.Add("DELETE FROM ProvisionJobs WHERE CustomerId = @customerId;")
            $commandText.Add("DELETE FROM HostedSites WHERE CustomerId = @customerId;")
        }

        $commandText.Add("DELETE FROM WaitlistEntries WHERE Email = @email;")
        $commandText.Add("DELETE FROM CustomerAccounts WHERE Id = @customerId OR Email = @email;")
        $commandText.Add("DELETE FROM AuditLogs WHERE Details LIKE @runIdLike;")
        $command.CommandText = [string]::Join([Environment]::NewLine, $commandText)

        [void]$command.Parameters.Add("@customerId", [System.Data.SqlDbType]::UniqueIdentifier)
        $command.Parameters["@customerId"].Value = [Guid]$CustomerId

        [void]$command.Parameters.Add("@email", [System.Data.SqlDbType]::NVarChar, 255)
        $command.Parameters["@email"].Value = $Email

        [void]$command.Parameters.Add("@runIdLike", [System.Data.SqlDbType]::NVarChar, 200)
        $command.Parameters["@runIdLike"].Value = "%$RunId%"

        [void]$command.ExecuteNonQuery()
    }
    finally {
        $connection.Dispose()
    }
}

function Get-NodeBaseDomain {
    param([string]$HostName)

    if ($HostName -match '^agent\.(.+)$') {
        return $Matches[1]
    }

    return $HostName
}

$adminUsername = Get-RequiredEnv "IIS_SMOKE_ADMIN_USERNAME"
$adminPassword = Get-RequiredEnv "IIS_SMOKE_ADMIN_PASSWORD"

$customerEmail = "$($script:RunId)@example.com"
$siteName = $script:RunId
$jobState = $null
$siteState = $null
$node = $null
$nodeHost = $RemoteHost
$appPoolName = "$siteName-pool"
$physicalPath = "C:\inetpub\customer-sites\$siteName"
$cleanupRequested = $false

try {
    Write-Step "Checking backend health at $BackendBaseUrl"
    [void](Invoke-JsonRequest -Method GET -Url "$BackendBaseUrl/api/metrics")

    Write-Step "Logging in through admin API"
    $login = Invoke-JsonRequest -Method POST -Url "$BackendBaseUrl/api/admin/login" -Body @{
        username = $adminUsername
        password = $adminPassword
    }

    if (-not $login.success -or [string]::IsNullOrWhiteSpace($login.token)) {
        throw "Admin login failed: $($login.message)"
    }

    $adminHeaders = @{ Authorization = "Bearer $($login.token)" }

    Write-Step "Registering test customer $customerEmail"
    $register = Invoke-JsonRequest -Method POST -Url "$BackendBaseUrl/api/auth/register" -Body @{
        email = $customerEmail
        password = "Smoke!$($script:RunId)"
    }

    if (-not $register.success -or -not $register.customerId) {
        throw "Customer registration failed: $($register.message)"
    }

    $script:Summary.customerId = [string]$register.customerId

    Write-Step "Loading admin customers"
    $customers = Invoke-JsonRequest -Method GET -Url "$BackendBaseUrl/api/admin/customers" -Headers $adminHeaders
    $customer = @($customers) | Where-Object { $_.id -eq $register.customerId } | Select-Object -First 1
    if (-not $customer) {
        throw "Registered customer '$customerEmail' was not returned by the admin customers API."
    }

    Write-Step "Approving customer through protected admin API"
    $approval = Invoke-JsonRequest -Method POST -Url "$BackendBaseUrl/api/admin/customers/$($register.customerId)/approve" -Headers $adminHeaders
    if (-not $approval.success -or -not $approval.customer) {
        throw "Customer approval failed: $($approval.message)"
    }

    $script:Summary.customerId = [string]$approval.customer.id
    $script:Summary.nodeId = [string]$approval.customer.assignedServerNodeId

    Write-Step "Resolving approved node"
    $nodes = Invoke-JsonRequest -Method GET -Url "$BackendBaseUrl/api/admin/nodes" -Headers $adminHeaders
    $node = @($nodes) | Where-Object { $_.id -eq $approval.customer.assignedServerNodeId } | Select-Object -First 1
    if (-not $node) {
        throw "Approved node '$($approval.customer.assignedServerNodeId)' was not returned by the admin nodes API."
    }

    if ([string]::IsNullOrWhiteSpace($nodeHost)) {
        $nodeHost = [string]$node.publicHost
    }

    $script:Summary.remoteHost = $nodeHost

    $baseDomain = Get-NodeBaseDomain -HostName $nodeHost
    $domain = "$siteName.$baseDomain"

    Write-Step "Queueing site $domain"
    $siteCreate = Invoke-JsonRequest -Method POST -Url "$BackendBaseUrl/api/admin/sites" -Headers $adminHeaders -Body @{
        customerId = $approval.customer.id
        siteName = $siteName
        domain = $domain
        physicalPath = $physicalPath
        appPoolName = $appPoolName
        port = 80
    }

    if (-not $siteCreate.success -or -not $siteCreate.site) {
        throw "Site queueing failed: $($siteCreate.message)"
    }

    $script:Summary.siteId = [string]$siteCreate.site.id

    Write-Step "Polling admin jobs and sites until completion"
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Seconds 5

        $sites = Invoke-JsonRequest -Method GET -Url "$BackendBaseUrl/api/admin/sites" -Headers $adminHeaders
        $siteState = @($sites) | Where-Object { $_.id -eq $siteCreate.site.id } | Select-Object -First 1
        if (-not $siteState) {
            throw "Queued site '$($siteCreate.site.id)' disappeared from the admin sites API."
        }

        $jobs = Invoke-JsonRequest -Method GET -Url "$BackendBaseUrl/api/admin/jobs" -Headers $adminHeaders
        $jobState = @($jobs) | Where-Object { $_.hostedSiteId -eq $siteCreate.site.id } | Sort-Object createdUtc -Descending | Select-Object -First 1

        if ($jobState) {
            $script:Summary.jobId = [string]$jobState.id
        }

        if ($siteState.provisioningStatus -eq "succeeded" -and $jobState -and $jobState.status -eq "succeeded") {
            break
        }

        if ($siteState.provisioningStatus -eq "failed" -or ($jobState -and $jobState.status -eq "failed")) {
            $errorMessage = if ($jobState -and $jobState.error) { $jobState.error } else { $siteState.lastProvisionError }
            throw "Provisioning failed: $errorMessage"
        }
    }

    if (-not $siteState -or $siteState.provisioningStatus -ne "succeeded") {
        $lastSiteStatus = if ($siteState) { $siteState.provisioningStatus } else { "missing" }
        $lastJobStatus = if ($jobState) { $jobState.status } else { "missing" }
        throw "Provisioning timed out after $TimeoutSeconds seconds. Last site status: $lastSiteStatus. Last job status: $lastJobStatus."
    }

    Write-Step "Verifying remote IIS site on $nodeHost"
    $remoteCheck = Invoke-RemoteCheck -HostName $nodeHost -SiteName $siteName -PhysicalPath $physicalPath -AppPoolName $appPoolName
    Write-Host ($remoteCheck | ConvertTo-Json -Depth 5)

    $script:Summary.finalStatus = "succeeded"

    if ($CleanupOnSuccess) {
        $cleanupRequested = $true
    }
}
catch {
    $script:Summary.finalStatus = "failed"
    $script:Summary.error = $_.Exception.Message
    Write-Host "[acceptance] ERROR: $($script:Summary.error)" -ForegroundColor Red
    $cleanupRequested = $true
}
finally {
    if ($cleanupRequested) {
        Write-Step "Running cleanup"
        $cleanupErrors = New-Object System.Collections.Generic.List[string]

        if ($nodeHost -and $siteName) {
            try {
                Invoke-RemoteCleanup -HostName $nodeHost -SiteName $siteName -PhysicalPath $physicalPath -AppPoolName $appPoolName
            }
            catch {
                $cleanupErrors.Add("remote cleanup failed: $($_.Exception.Message)")
            }
        }

        if ($script:Summary.customerId) {
            try {
                Invoke-DbCleanup -RunId $script:RunId -Email $customerEmail -CustomerId $script:Summary.customerId -SiteId $script:Summary.siteId
            }
            catch {
                $cleanupErrors.Add("database cleanup failed: $($_.Exception.Message)")
            }
        }

        if ($cleanupErrors.Count -eq 0) {
            $script:Summary.cleanupStatus = "succeeded"
        }
        else {
            $script:Summary.cleanupStatus = "failed"
            foreach ($cleanupError in $cleanupErrors) {
                Write-Warning $cleanupError
            }
        }
    }
    elseif ($script:Summary.finalStatus -eq "succeeded") {
        $script:Summary.cleanupStatus = "kept"
    }
    else {
        $script:Summary.cleanupStatus = "skipped"
    }

    $summaryObject = [pscustomobject]$script:Summary
    Write-Host ($summaryObject | ConvertTo-Json -Depth 5)

    if ($script:Summary.finalStatus -ne "succeeded") {
        exit 1
    }
}
