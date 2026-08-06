# HAP PowerShell Provider SDK

This SDK is for administrator-approved third-party providers only. It is separate from the temporary migration bridge and must not import migration-only modules.

Providers integrate through:

- `manifest.json`
- `Invoke-HapProviderOperation`
- Structured result objects from `HAP.ProviderSdk.psm1`

The initial supported runtime is PowerShell 7. Manifests must declare provider identity, API version, module entry point, capabilities, operations, and required permissions.

HAP owns all UI and executes providers only through the isolated plugin host.
