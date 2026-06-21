# Milestone 6 Phase 3 - Microsoft Graph Provider Service

## Status

Implemented as a provider-facing Microsoft Graph service wrapper.

## Architectural intent

Phase 3 adds the Microsoft Graph provider surface that consumes the platform authentication manager and returns canonical HAP domain models. This phase intentionally does not perform live Graph HTTP calls. Live Graph request execution remains behind the existing Version 0.5 Graph client and HTTP pipeline foundation.

## Added capability

- `Core.Provider.MicrosoftGraph`
- `Hybrid.MicrosoftGraphProviderContext`
- `Hybrid.MicrosoftGraphProviderService`
- Provider operations for `SearchUser` and `GetUser`
- Provider health and capability discovery
- Authentication session acquisition through `Get-HybridAuthenticationSession`
- Mock Graph user data for deterministic offline testing

## Validation

Run from the repository root:

```powershell
Get-ChildItem -Path . -Recurse -File | Unblock-File

Remove-Module Infrastructure.ActiveDirectory,Core.ProviderBase,ActiveDirectory,Hybrid.Models,Core.Authentication.MSAL,Core.Authentication.Manager,Core.Authentication,Core.CloudEnvironment,Core.TenantContext,Core.Provider.MicrosoftGraph,Graph.Models -Force -ErrorAction SilentlyContinue
.\tests\Test-Milestone6.ps1

Remove-Module Infrastructure.ActiveDirectory,Core.ProviderBase,ActiveDirectory,Hybrid.Models,Core.Authentication.MSAL,Core.Authentication.Manager,Core.Authentication,Core.CloudEnvironment,Core.TenantContext,Core.Provider.MicrosoftGraph,Graph.Models -Force -ErrorAction SilentlyContinue
.\tests\Test-Milestone6Phase2.ps1

Remove-Module Infrastructure.ActiveDirectory,Core.ProviderBase,ActiveDirectory,Hybrid.Models,Core.Authentication.MSAL,Core.Authentication.Manager,Core.Authentication,Core.CloudEnvironment,Core.TenantContext,Core.Provider.MicrosoftGraph,Graph.Models -Force -ErrorAction SilentlyContinue
.\tests\Test-Milestone6Phase3.ps1
```
