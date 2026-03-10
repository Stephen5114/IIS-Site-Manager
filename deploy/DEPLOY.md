# Deployment Notes

## Current Model

Production now uses separate IIS sites:

- backend: `IIS-Site-Manager-Backend` on port `5032`
- frontend: `IIS-Site-Manager-Frontend` on port `8082`

The agent is published separately to `deploy/agent`.

## Build Artifacts

Run from the repo root:

```powershell
cd deploy
.\build.ps1
```

This produces:

- `deploy/api`: published backend
- `deploy/web`: exported static frontend
- `deploy/agent`: published agent

`build.ps1` preserves `deploy/api/appsettings.Production.json` if it already exists.

## IIS Setup

Run as Administrator:

```powershell
cd deploy
.\setup-iis.ps1
```

Optional cleanup of the old single-site setup:

```powershell
.\setup-iis.ps1 -RemoveLegacySingleSite
```

The script:

- creates separate backend and frontend app pools
- binds backend to `*:5032`
- binds frontend to `*:8082`
- sets backend `ASPNETCORE_ENVIRONMENT=Production`
- opens firewall rules for both ports

## Agent Service

For local or remote Windows Service setup, use one of:

- `deploy/setup-agent-service.ps1`
- `deploy/install-agent-service.ps1`

Both scripts write `appsettings.Production.json` for the agent and configure the service to start with `--environment Production`.
Default service account is now `LocalSystem`, because `LocalService` does not have enough IIS configuration access for `Microsoft.Web.Administration` based provisioning on the remote node.

## Production Acceptance Check

The canonical post-deploy verification is:

```powershell
$env:IIS_SMOKE_ADMIN_USERNAME = "<admin-username>"
$env:IIS_SMOKE_ADMIN_PASSWORD = "<admin-password>"
$env:IIS_SMOKE_WINRM_USERNAME = "<winrm-username>"
$env:IIS_SMOKE_WINRM_PASSWORD = "<winrm-password>"
.\deploy\run-production-acceptance.ps1
```

Required environment variables:

- `IIS_SMOKE_ADMIN_USERNAME`
- `IIS_SMOKE_ADMIN_PASSWORD`
- `IIS_SMOKE_WINRM_USERNAME`
- `IIS_SMOKE_WINRM_PASSWORD`

Optional environment variables:

- `IIS_SMOKE_WINRM_PORT` default `5985`
- `IIS_SMOKE_WINRM_AUTH` default `Basic`
- `IIS_SMOKE_SQL_CONNECTION` optional cleanup override if the script cannot read the local production API connection string

What the script verifies:

- backend health responds
- admin login succeeds through `/api/admin/login`
- customer registration succeeds
- admin approval succeeds through the protected admin API
- site queueing succeeds through the protected admin API
- provisioning reaches `succeeded`
- the remote IIS site exists, is started, and has its expected `index.html`

Cleanup behavior:

- default: keep successful test artifacts and print a machine-readable summary for traceability
- `-CleanupOnSuccess`: also remove the created customer, site, jobs, and remote IIS artifacts
- failed runs always attempt best-effort cleanup of the artifacts created in that run

Use this script after backend deploys, agent deploys, service-account changes, or node maintenance. It is the primary proof that the admin approval and provisioning path still works end to end.

## Operational Notes

- Stop the backend app pool before rebuilding if you hit file lock issues.
- Keep real secrets only in `appsettings.Production.json` or another deployment-only config source.
- Do not pass secrets containing `$` through `appcmd`; use JSON config files instead.
