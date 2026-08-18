New contributors and future development sessions should begin with ENGINEERING_GUIDE.md

# Hybrid Identity Lifecycle & Operations Platform (HILOP)

Hybrid Identity Lifecycle & Operations Platform (HILOP) is a modular PowerShell-based enterprise administration framework for hybrid Microsoft environments.

Atlas is the first deployment profile. The core framework is intended to remain profile-driven and provider-agnostic.

HILOP is a local desktop administration tool that runs on a technician's workstation under that technician's user context. It does not provide application-level role-based access control (RBAC) or centralized approval workflows. Microsoft Graph operations use delegated access, and effective authorization remains with Microsoft Entra ID, Active Directory, Conditional Access, and the permissions assigned to the signed-in technician. HILOP does not elevate or replace those controls.

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
