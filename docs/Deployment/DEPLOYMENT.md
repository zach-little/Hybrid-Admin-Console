# Hybrid Admin Platform Deployment

## Overview

Hybrid Admin Platform deployment is runtime-profile driven. A deployment can be validated and packaged without contacting Active Directory, Microsoft Graph, or Exchange Online.

The recommended first-run profile is `profiles/Runtime/Simulation.json`. This keeps startup deterministic and allows the shell, diagnostics, dashboard, and runtime profile wizard to be validated offline.

## Required Layout

A deployment should contain:

```text
src/
profiles/
profiles/Runtime/
docs/
tools/
tests/
logs/
build/
src/UI/Start-HybridAdminConsole.ps1
```

At least one readable runtime profile must exist under `profiles/Runtime`.

## Validate the Deployment

```powershell
Get-ChildItem -Path . -Recurse -File | Unblock-File

Remove-Module Core.Deployment,Core.Runtime,Core.RuntimeProfile,Core.ServiceRegistry,Application.HybridUserService,Application.GraphProfileService,Application.AuthenticationProfileService,Application.HybridUserAggregationService,Infrastructure.DirectorySimulator -Force -ErrorAction SilentlyContinue

.\tools\Test-HybridDeployment.ps1
```

## Create a Deployment Package

```powershell
.\tools\New-HybridAdminDeploymentPackage.ps1 -Force
```

The default package is written to `build`.

## First Run

Use the Simulation runtime profile for first-run validation:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\src\UI\Start-HybridAdminConsole.ps1 -Mock -InitialQuery Alex
```

Expected behavior:

1. Startup shell loads.
2. Runtime profile summary appears.
3. Diagnostics summary appears.
4. Launch opens the main dashboard.
5. Edit Runtime Profile opens the profile wizard.

## Security Notes

Device Code authentication is intentionally not used. GCC High Conditional Access policies commonly block that flow, and HAP must remain compatible with Interactive and App-only MSAL flows only.

Packaging and validation do not perform live authentication or provider connectivity checks.

## Runtime Profiles

Runtime profiles live under:

```text
profiles/Runtime
```

Supported runtime modes:

- `Simulation`
- `Live`
- `Hybrid`

Provider modes:

- `Simulation`
- `Live`
- `Disabled`

The runtime profile wizard can create and save custom profiles without editing JSON by hand.
