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

Known issues / next stabilization work:

- On-premises Exchange server connectivity is not yet implemented. Hybrid environments need a future profile-level `OnPremExchangeServer`/provider path so on-prem Exchange attributes and recipient operations can be queried directly.
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
