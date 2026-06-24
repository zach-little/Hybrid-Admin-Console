# Project Status

## Current Version

v0.8.9

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
- Runtime theme support and profile-aware branding are available.

### Current live validation findings

Active Directory search and group display are working. v0.8.9 includes a DN/OU propagation fix that must be validated live: AD conversion now preserves DN/OU as direct properties and Attributes values, the service layer reads hashtable attributes, and the UI resolver reads both direct and Attributes-backed names.

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

- Exchange status is currently misleading in a hybrid environment. The UI can report Exchange loaded while the data may be AD mail attributes rather than Exchange Online provider data.
- Microsoft Graph vertical is not yet loading in the live test environment.
- Authentication posture vertical is not yet loading in the live test environment.
- Graph, Exchange, and Authentication services may still be unregistered or deferred depending on runtime profile/provider configuration.
- The UI needs a Back/Start button to return to Runtime Home so operators can switch profiles without closing the application.
- The bottom status area needs a centered search progress bar, placed to the left of the active profile indicator, showing current search/hydration progress.

---

## Current Recommendation

Do not begin Milestone 9 yet.

Before Milestone 9, validate the v0.8.9 live-readiness stabilization pass:

- Validate DN/OU display in live AD.
- Continue clarifying hybrid Exchange vs Exchange Online status, including future on-prem Exchange connectivity.
- Register or explicitly mark Graph, Exchange, and Authentication verticals as deferred/unavailable with clear reason text.
- Validate Back/Start navigation to Runtime Home/Profile selection.
- Validate the bottom search progress bar stages.
- Clean backup artifacts created during hotfix attempts before tagging a new release.

---

## Next Target

v0.8.9 — Live Runtime UX & Vertical Stabilization

