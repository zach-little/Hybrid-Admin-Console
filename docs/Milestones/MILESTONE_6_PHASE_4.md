# Milestone 6 Phase 4 - Exchange Online Provider Foundation

## Objective

Add the Exchange Online provider foundation for the Microsoft 365 platform layer without introducing live Exchange dependencies into automated milestone tests.

## Architecture

Phase 4 follows the same platform pattern established by the Microsoft Graph provider:

```text
Provider command -> Provider service -> Authentication Manager -> Authentication Adapter -> Platform session
```

The Exchange Online provider does not authenticate directly. It creates an authentication request and asks the authentication manager for a platform session.

## Added Files

- `src/Core/Core.Provider.ExchangeOnline.psm1`
- `tests/Test-Milestone6Phase4.ps1`
- `docs/milestones/MILESTONE_6_PHASE_4.md`

## Public Commands

- `New-HybridExchangeOnlineProviderContext`
- `Initialize-HybridExchangeOnlineProvider`
- `Search-HybridExchangeOnlineMailbox`
- `Get-HybridExchangeOnlineMailbox`
- `Get-HybridExchangeOnlineProviderHealth`

## Model Contracts

- `Hybrid.ExchangeOnline.ProviderContext`
- `Hybrid.ExchangeOnline.ProviderService`
- `Hybrid.ExchangeOnline.Mailbox`
- `Hybrid.ExchangeOnline.ProviderHealth`

## Test Coverage

The Phase 4 test validates:

- exported provider functions
- provider context contract
- provider service contract
- authentication manager integration
- capability reporting
- mailbox search
- mailbox lookup
- mailbox model conversion
- provider health contract

## Known Limitations

This phase intentionally uses seeded mailbox data. Live Exchange Online cmdlet execution is deferred until the provider boundary, authentication session contract, and mailbox model contract are stable.

## Next Step

After Phase 4 passes, Milestone 6 can be rolled up with project-wide documentation updates for changelog, version, and project status.


## Phase 4 Tenant Context Fix

- Exchange Online authentication request creation now normalizes split tenant/cloud context input into the platform tenant context contract expected by the authentication manager.
- This keeps Exchange Online aligned with the Microsoft Graph provider contract without requiring live Exchange authentication during tests.


## CloudEnvironment endpoint contract fix

The Exchange Online provider now normalizes simplified cloud objects into the shared `Hybrid.CloudEnvironment` contract before creating authentication requests. This preserves the Authentication Manager requirement that tenant contexts carry a `CloudEnvironment.Endpoints` map while keeping Phase 4 tests isolated from live Microsoft cloud dependencies.
