# Version

Current Version: v0.8.8

Status: Live-environment stabilization in progress.

---

## Current Release

### v0.8.8 — Active Directory Group Display Stabilization

Summary:

- Active Directory live runtime readiness is working.
- Active Directory provider health reports connected in the live runtime session.
- Base user search works in the live environment.
- Active Directory group display was corrected to show friendly group names rather than raw object output.
- Persistent runtime, Active Directory, and hydration diagnostics are available.

Known issues:

- Distinguished Name does not yet display in the UI.
- Organizational Unit does not yet display in the UI.
- Exchange status needs to distinguish AD mail attributes from Exchange Online provider data.
- Microsoft Graph vertical is not yet loading in the live validation environment.
- Authentication posture vertical is not yet loading in the live validation environment.

---

## Next Planned Release

### v0.8.9 — Live Runtime UX & Vertical Stabilization

Planned scope:

- Fix DN/OU display.
- Add Back/Start navigation to return to Runtime Home/Profile selection.
- Add bottom search progress bar to show current search/hydration stage.
- Clarify Exchange Online vs AD mail attribute status.
- Improve Graph, Exchange, and Authentication vertical registration/deferred state messaging.
- Preserve group display and AD live runtime readiness behavior.

---

## Release Policy

Milestone 9 should not start until v0.8.9 live-readiness stabilization is complete and validated.

