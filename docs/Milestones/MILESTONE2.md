# Milestone 2 - Domain Models and User Service

Milestone 2 introduces the first application-level service API and the canonical domain model factories used by the framework.

## Added

- `src/Domain/Hybrid.Models.psm1`
- `src/Application/Application.UserService.psm1`
- Expanded `src/Infrastructure/Infrastructure.Mock.psm1`
- Updated `src/Application/Application.ServiceLocator.psm1`
- Updated `src/Core/Core.ModuleLoader.psm1`
- `tests/Test-Milestone2.ps1`

## Public APIs

### Domain models

- `New-HybridUser`
- `New-HybridGroup`
- `New-HybridMailbox`
- `New-HybridDevice`
- `New-HybridLicense`
- `New-HybridWorkflow`
- `New-HybridResult`

### User service

- `Initialize-HybridUserService`
- `Search-HybridUser`
- `Get-HybridUser`
- `Get-HybridUserGroups`
- `Get-HybridUserMailbox`
- `Get-HybridUserDevices`
- `Get-HybridUserLicenses`

## Design Notes

The User service does not call Active Directory, Graph, Exchange, or Intune directly. It calls the registered `Directory` service. In Milestone 2 that service is backed by `Infrastructure.Mock`, but later the same service API can be backed by Active Directory, Graph, Exchange, Intune, or a composite provider.

The UI and workflows should use `Search-HybridUser` and `Get-HybridUser`, not provider-specific cmdlets.

## Validation

Run:

```powershell
.\tests\Test-Milestone1.ps1
.\tests\Test-Milestone2.ps1
```
