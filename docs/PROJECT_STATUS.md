# Project Status

## Current Version

v0.9.0

---

## Completed Milestones

- ✅ Milestone 1 — Foundation
- ✅ Milestone 2 — Domain Model
- ✅ Milestone 3 — Provider Architecture
- ✅ Milestone 4 — Active Directory Provider
- ✅ Milestone 5 — Microsoft 365 Cloud Foundation
- ✅ Milestone 6 — Authentication Infrastructure
- ✅ Milestone 7 — Service Layer & Vertical Integration
- ✅ Milestone 8 — Runtime Platform
- ✅ Milestone 8.1 — Runtime Platform Hardening
- ✅ Milestone 8.2 — Branding & Theme System

---

## Current Stabilization Track

The project is currently in a live-environment stabilization pass after Milestone 8. v0.8.9 focuses on live Runtime UX and vertical stabilization before starting Milestone 9.

### Completed in the stabilization pass

- Runtime launcher now opens the Runtime Profile/WPF path instead of the legacy shell directly.
- Runtime startup and provider health diagnostics were added.
- Active Directory runtime readiness now imports and validates the ActiveDirectory module in the live provider session.
- Active Directory health now reports connected in the live runtime session.
- Persistent diagnostics were added for runtime, Active Directory, and hydration behavior:
  - `logs/runtime-diagnostics.log`
  - `logs/ad-runtime-diagnostics.log`
  - `logs/hydration-diagnostics.log`
- Active Directory search works in the live environment.
- Base user hydration works in the live environment.
- Active Directory details load for the selected user.
- Group display formatting was corrected so group lists display friendly group names rather than raw object output.
- DN/OU propagation was tightened across AD provider, HybridUserService, and UI resolvers.
- The main console now has a Back/Start button to reopen Runtime Home.
- The bottom status bar now has staged search progress for Search, Base User, AD, Graph, Exchange Online, Authentication Posture, Aggregation, and Complete.
- Exchange display now distinguishes AD mail attributes from Exchange Online mailbox provider data.
- Duplicate user search results now open a chooser instead of silently selecting the first match.
- An `Infrastructure.ExchangeOnPremises` provider slice was added so hybrid environments can query local Exchange recipient, remote-mailbox, forwarding, and distribution-group data separately from Exchange Online.
- Runtime Home provider display now renders enabled providers dynamically from the selected profile/runtime registry, including Exchange On-Premises.
- Exchange mailbox hydration can now load an on-prem remote mailbox when Exchange Online mailbox data is unavailable, and aggregation annotates the ExchangeMailbox vertical with the source provider.
- Runtime theme support and profile-aware branding are available.

### Current live validation findings

Active Directory search, group display, and DN/OU display are working. v0.8.9 now also includes duplicate-user selection before hydration: AD conversion now preserves DN/OU as direct properties and Attributes values, the service layer reads hashtable attributes, and the UI resolver reads both direct and Attributes-backed names.

The likely investigation areas are:

1. `src\Infrastructure\Infrastructure.ActiveDirectory.psm1`
   - `ConvertTo-HybridADUser`
   - Confirm `DistinguishedName` is preserved from raw AD results.
   - Confirm the value is also available in the `Attributes` bag if the UI expects it there.

2. `src\Application\Application.HybridUserService.psm1`
   - `New-HybridCompositeUser`
   - `Add-HybridUserDetails`
   - Confirm `DistinguishedName`, `ActiveDirectoryDistinguishedName`, and `OrganizationalUnit` survive service-layer composition.

3. `src\UI\Start-HybridAdminConsole.ps1`
   - `Update-DetailPanels`
   - `Resolve-HybridUserDistinguishedName`
   - `Resolve-HybridUserOrganizationalUnit`
   - Confirm the UI is reading the same property names produced by the service layer.

### Other known live validation gaps

- Exchange on-premises support is represented as a separate provider slice and has runtime/profile/editor wiring. Live validation should confirm the local Exchange server returns remote mailbox, forwarding, and distribution-group data for the selected identity.
- Microsoft Graph vertical is not yet loading in the live test environment.
- Authentication posture vertical is not yet loading in the live test environment.
- Graph, Exchange, and Authentication services may still be unregistered or deferred depending on runtime profile/provider configuration.

---

## Current Recommendation

Milestone 9 / v0.9.0 is complete.

The v0.9 runtime foundation is in place. Continue carrying forward live validation notes while planning the next enterprise feature slices.

---

## Next Target

v0.9.0 — Background Runtime Services

Completed:

- Runtime event bus.
- Runtime bootstrap event publication.
- Provider refresh scheduling foundation.
- Runtime service orchestrator.
- Provider status synchronization events.
- Cache invalidation events.
- Runtime task lifecycle and cooperative cancellation tracking.

## v0.9C Status - Workflow Framework

v0.9C introduces HAP workflows after profile launch. User Lookup remains the existing console path. New User Wizard is available as a new workflow shell with validation and preview-only planning. Live write execution is intentionally deferred to the next implementation phase.
