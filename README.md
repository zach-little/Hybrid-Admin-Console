# Hybrid Administration Platform

Hybrid Administration Platform is a modular PowerShell-based enterprise administration framework for hybrid Microsoft environments.

Atlas is the first deployment profile. The core framework is intended to remain profile-driven and provider-agnostic.

## Run Milestone 1 Tests

```powershell
Get-ChildItem -Path . -Recurse -File | Unblock-File
.	ests\Test-Milestone1.ps1
```

## Launch

```powershell
.\Start-AtlasHybridAdminConsole.ps1 -Profile Atlas -NoNet -HapDebug
```

Note: `-HapDebug` is used instead of `-Debug` to avoid conflict with PowerShell's common `-Debug` parameter.
