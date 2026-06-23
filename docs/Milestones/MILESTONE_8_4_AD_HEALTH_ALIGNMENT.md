# Milestone 8.4 â€” Active Directory Health Alignment Hotfix

## Purpose

The runtime launch page and the launched console must not report conflicting Active Directory status.

Before this hotfix, the launch page could show a static `Active Directory Ready` line because the runtime profile declared the provider, while the console Provider Health card could show `AD unavailable` because the live provider service was not connected in the current console session.

## Changes

- Removed static Active Directory Ready text from the launch page.
- Added named provider status rows on the Runtime Home surface.
- Added a shared UI readiness helper for Active Directory.
- Prefer `Get-HybridADProviderHealth` when available.
- Fall back to `Test-HybridActiveDirectoryProviderAvailable` only as module detection, not as connected provider readiness.
- Updated the console Provider Health card to use the same readiness helper.
- Added a distinct `Detected / not connected` state so module availability is not confused with operational provider readiness.

## Validation

Run:

```powershell
.\tests\Test-Milestone8_4ADHealthAlignment.ps1
```
