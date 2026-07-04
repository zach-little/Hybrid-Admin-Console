# Version

Current Version: v0.10.x

Status: Identity Platform Completion / Milestone 10 stabilization.

---

## Current Development Target

### v0.10.x - Identity Platform Completion

Milestone 10 has been redefined from broad independent enterprise modules into identity platform completion.

The codebase already implements much of the originally planned Milestone 10 capability set inside the User Lookup workflow. That is the intended architecture.

Current target:

- Stabilize the User Lookup identity hub.
- Fix Graph profile parity for license and PIM data.
- Improve authentication posture and risk details.
- Validate Exchange Online and Exchange On-Premises mailbox data.
- Complete New User Wizard parity with the legacy script.
- Preserve identity facts inside the User workflow.
- Keep Device Management as the first separate administrative workflow.

---

## Current Release Notes

### v0.10.x - Identity Platform Completion

Summary:

- User Lookup is the central identity hub.
- Active Directory attributes are already pulled.
- Manager and direct-report data are pulled from Active Directory where available.
- Groups are pulled and displayed.
- Graph user data is wired into the user flow.
- Exchange Online mailbox data is wired into the user flow.
- Exchange On-Premises recipient / remote mailbox data is wired into the user flow.
- Authentication posture has Azure/Graph-backed implementation but needs better coverage and diagnostics.
- Licenses are intended to be part of the user Graph profile but likely have a propagation/display bug.
- PIM has been attempted but is not confirmed functional.
- Risk is currently shallow and should be expanded.
- Device Management has started as a separate workflow and remains valid as an independent operational area.

Known issues / next stabilization work:

- Fix the license display/hydration path so richer Graph profile license fields reach the UI.
- Confirm whether the active UI path prefers `Get-HybridUserGraphProfile` over `Get-HybridGraphProfile`, and if so, bring the former to property parity or route through the richer service.
- Preserve `Licenses`, `AssignedLicenses`, `LicenseAssignmentStates`, license diagnostics, PIM roles, and PIM diagnostics in the user profile returned to the UI.
- Validate PIM behavior in the target cloud and delegated/app-only permission model.
- Expand risk details beyond yes/no.
- Improve authentication posture diagnostics.
- Live-validate Exchange Online and Exchange On-Premises mailbox details.

---

## Roadmap Alignment

- v0.10 - Identity Platform Completion.
- v0.11 - Administrative Workflows.
- v0.12 - Enterprise Operations.
- v0.13 - Enterprise Platform.
- v1.0 - Hybrid Enterprise Platform.

---

## Release Policy

Identity facts should not become standalone modules.

A standalone workflow is appropriate only when it performs administrative operations or manages a collection/object type independently of a single user identity view.
