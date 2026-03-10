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

## Operational Notes

- Stop the backend app pool before rebuilding if you hit file lock issues.
- Keep real secrets only in `appsettings.Production.json` or another deployment-only config source.
- Do not pass secrets containing `$` through `appcmd`; use JSON config files instead.
