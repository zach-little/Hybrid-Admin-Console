# Version

Current Version: v0.9.0

Status: Live Runtime UX & Vertical Stabilization.

---

## Current Release

### v0.8.9 — Live Runtime UX & Vertical Stabilization

Summary:

- Active Directory DN/OU propagation was tightened from AD provider output through HybridUserService composition and UI display resolution.
- AD provider conversion now exposes `DistinguishedName`, `ActiveDirectoryDistinguishedName`, `OrganizationalUnit`, and `ActiveDirectoryOrganizationalUnit` as direct properties and in the `Attributes` bag.
- HybridUserService object-value resolution now supports hashtable-backed attribute bags.
- UI DN/OU display resolution now reads direct properties and `Attributes` bag values and writes diagnostics for resolved values.
- A Back/Start button was added to the main console so operators can return to Runtime Home and switch profiles without closing the app.
- A bottom search progress indicator was added with stages for Search, Base User, Active Directory Details, Microsoft Graph, Exchange Online, Authentication Posture, Aggregation, and Complete.
- Exchange display now clearly distinguishes AD mail attributes from Exchange Online mailbox data when the Exchange Online provider is unavailable or returns no mailbox.
- User search now preserves multiple matches and prompts the operator to choose the intended user before hydration.
- Added an on-premises Exchange provider slice for hybrid recipient/remote mailbox lookup through local Exchange PowerShell.
- Runtime Home provider detail display now renders enabled providers dynamically, including Exchange On-Premises.
- Exchange mailbox hydration now uses on-prem remote mailbox, forwarding, and distribution-group data when Exchange Online mailbox data is unavailable.
- Aggregation now marks ExchangeMailbox as loaded from ExchangeOnline or ExchangeOnPremises based on the mailbox detail source provider.

Known issues / next stabilization work:

- On-premises Exchange provider support has runtime/profile/editor wiring and mailbox-detail fallback. Live validation should confirm returned remote mailbox, forwarding, and distribution-group shape in the local Exchange environment.
- Microsoft Graph vertical may still be unavailable depending on runtime profile registration and authentication configuration.
- Authentication posture vertical may still be unavailable depending on runtime profile registration and Microsoft Graph authentication readiness.
- Service registry/deferred-provider status messaging still needs a deeper pass so each vertical clearly reports registered, deferred, unavailable, or failed.

---

## Previous Release

### v0.8.8 — Active Directory Group Display Stabilization

Summary:

- Active Directory live runtime readiness is working.
- Active Directory provider health reports connected in the live runtime session.
- Base user search works in the live environment.
- Active Directory group display was corrected to show friendly group names rather than raw object output.
- Persistent runtime, Active Directory, and hydration diagnostics are available.

---

## Release Policy

Milestone 9 / v0.9.0 is complete after the v0.8.9 live-readiness stabilization pass.

v0.9.0 delivered:

- Background runtime services.
- Runtime event bus.
- Provider refresh scheduling.
- Runtime service orchestrator.
- Provider status synchronization events.
- Cache invalidation events.
- Runtime task lifecycle and cooperative cancellation tracking.
