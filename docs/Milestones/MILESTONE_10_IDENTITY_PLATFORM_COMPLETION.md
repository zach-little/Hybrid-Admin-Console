# Milestone 10 - Identity Platform Completion

## Status

Mostly complete / stabilization required.

## Purpose

Milestone 10 completes the User Lookup identity platform. Earlier roadmap text described broad enterprise features, but the current implementation already places most identity-related enterprise data inside the User workflow.

This is the correct direction.

## Architectural Rule

- User facts belong in User Lookup / HybridCompositeUser.
- Administrative actions belong in workflows.
- External system communication belongs in providers.

Do not split licenses, mailbox facts, groups, manager data, authentication posture, risk, or PIM into standalone modules merely because they come from different providers.

## Already Implemented or Partially Implemented

- Active Directory attributes.
- Manager data.
- Direct-report data.
- Groups.
- Microsoft Graph user data.
- Exchange Online mailbox details.
- Exchange On-Premises recipient / remote mailbox details.
- Authentication posture.
- License data path exists but likely has a propagation/display bug.
- PIM path has been attempted but is not confirmed functional.
- Risk exists only in shallow form.
- Device Management has started as a separate workflow.

## Remaining Work

### License profile parity

Fix user Graph profile propagation so license fields reach the UI:

- Licenses.
- AssignedLicenses.
- LicenseAssignmentStates.
- License diagnostics.
- Service plan detail where available.

### PIM

- Validate cloud and permission requirements.
- Use delegated Microsoft Graph access so results remain subject to the signed-in technician's Entra ID permissions and activation state.
- Display eligible and active assignments where available.
- Return clear diagnostics when unavailable.

### Risk and authentication posture

- Expand risk detail beyond yes/no.
- Improve risky sign-in detail.
- Improve user risk / sign-in risk display.
- Improve MFA/authentication methods display.
- Improve password and sign-in date display.
- Improve Conditional Access status messaging where available.

### Exchange identity data

- Validate Exchange Online mailbox data.
- Validate Exchange On-Premises remote mailbox data.
- Validate distribution groups.
- Validate mailbox delegation.
- Validate archive, forwarding, litigation hold, and mailbox statistics.

### Legacy parity

- Complete New User Wizard parity with `legacy\New_User_Wizard.ps1`.
- Preserve field options, defaults, validation, and review behavior from the legacy script.

## Not in Scope

- Standalone License module for user license display.
- Standalone Exchange module for user mailbox facts.
- Standalone Risk module for simple identity risk facts.

These may become workflows later only when they perform administration, reporting, investigation, or bulk operations.
