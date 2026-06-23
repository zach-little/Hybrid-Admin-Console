# Milestone 8.3 — Active Directory Runtime Readiness Hotfix

Version: v0.8.3

## Purpose

This hotfix closes a live-runtime gap where Active Directory could report healthy during startup diagnostics, but AD-backed console operations could still fail after launch because the launched runtime session had not imported or validated the `ActiveDirectory` PowerShell module.

## Changes

- Added `Initialize-HybridActiveDirectoryRuntime` to `Infrastructure.ActiveDirectory`.
- The readiness helper explicitly imports the `ActiveDirectory` module in the current PowerShell session.
- The readiness helper validates required AD cmdlets before live operations run.
- The AD command wrapper now performs runtime readiness before invoking `Get-ADUser`, group membership, OU, and write operations.
- Provider health now re-checks runtime readiness when the provider is initialized and marked available.
- Added structured `ActiveDirectoryRuntimeUnavailable` errors for clearer diagnostics.
- Added runtime readiness state fields for provider health and troubleshooting.
- Added targeted Milestone 8.3 validation tests.

## Validation

```powershell
Get-ChildItem -Path . -Recurse -File | Unblock-File
Remove-Module Infrastructure.ActiveDirectory,Core.ProviderBase,ActiveDirectory,Hybrid.Models -Force -ErrorAction SilentlyContinue
.\tests\Test-Milestone4.ps1
.\tests\Test-Milestone8_3ActiveDirectoryRuntimeReadiness.ps1
```
