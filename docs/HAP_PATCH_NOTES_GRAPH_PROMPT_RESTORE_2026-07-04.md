# HAP Patch Notes - Graph Prompt Restore

Date: 2026-07-04

## Purpose
Restore the launch-time Microsoft Graph delegated credential prompt after the launch-page readiness UI polish.

## Changes
- Preserves the launch-page UI polish and menu placement changes.
- Updates Microsoft Graph runtime bootstrap so a live Graph provider with `Authentication = Interactive` is treated as requiring delegated sign-in during launch, even if the profile's nested delegated block is stale or missing.
- Keeps app-only available only when delegated sign-in is not required.
- Clarifies launch-page text so it does not imply authentication was removed or deferred.

## Files
- `src/Core/Core.Runtime.psm1`
- `src/UI/Start-HybridAdminConsole.ps1`
