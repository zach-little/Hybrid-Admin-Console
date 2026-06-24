# Version

Current Version: v0.8.9

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

Known issues / next stabilization work:

- On-premises Exchange provider support is introduced, but runtime profile bootstrap wiring still needs live validation against the local Exchange server profile settings.
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

Milestone 9 should not start until v0.8.9 live-readiness stabilization is validated in the live environment.
