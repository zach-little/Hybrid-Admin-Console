# C# Runtime Profile Read-Only Slice

## Scope

This slice proves the first migration path from WPF/MVVM into the temporary legacy PowerShell bridge without importing the legacy UI script.

Implemented operations:

- `Get-HapRuntimeProfiles`
- `Start-HapRuntimeSession`
- `Stop-HapRuntimeSession`

## Parity Covered

- Runtime profiles load through the headless bridge and return stable DTOs.
- The out-of-process worker performs a protocol handshake before executing operations.
- Runtime initialization can start the Simulation profile through `Core.Runtime.psm1`.
- Provider health is normalized into name, mode, enabled, required, status, message, connected, available, and last-error fields.
- Runtime shutdown resets the legacy runtime state through `Reset-HybridRuntime`.
- The WPF selector ViewModel exposes loading, selection, validation, progress, error, provider-health, and shutdown state.

## Out Of Scope

- User search and user-detail workflows.
- Live authentication prompts.
- Native .NET provider parity.
- Permanent third-party plugin execution.
- Any write operation.

## Notes

The temporary bridge and worker remain migration-only. They must not be reused as the permanent PowerShell extension SDK.
