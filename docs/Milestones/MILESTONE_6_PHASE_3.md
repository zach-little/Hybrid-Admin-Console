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

## Test Harness Correction

The Phase 3 service exposes provider operations as scriptblocks. PowerShell scriptblock `.Invoke()` returns a collection wrapper even when the underlying command returns one object. The GetUser assertions now unwrap the first result before validating the canonical `Hybrid.User` model. This preserves provider behavior while testing the object contract accurately.


## Test Fix: Provider Health Contract

`Get-HybridMicrosoftGraphProviderHealth` now unwraps provider-base health output to a single object and explicitly stamps the `Hybrid.MicrosoftGraphProviderHealth` type name before returning it. This keeps provider health aligned with the Phase 3 platform contract without weakening the test.
