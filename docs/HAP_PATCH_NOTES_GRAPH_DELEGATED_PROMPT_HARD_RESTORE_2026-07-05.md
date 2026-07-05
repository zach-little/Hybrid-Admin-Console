# HAP Patch Notes - Graph Delegated Prompt Hard Restore - 2026-07-05

## Purpose
Restore the launch-time delegated Microsoft Graph credential prompt after launch-page readiness/UI refactoring caused Graph to remain deferred.

## Changes
- Adds an explicit `Connect` / `EnsureAuthenticated` operation to the lazy Microsoft Graph runtime service.
- Launch workflow now explicitly calls the Microsoft Graph delegated connector after runtime initialization when the selected profile or provider requires delegated/interactive Graph auth.
- Keeps the previous UI polish and list/menu contrast changes intact.

## Notes
`GetHealth` is not used as the launch prompt trigger because the lazy Graph provider can legitimately return `Deferred` without acquiring a delegated token.
