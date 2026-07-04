# Roadmap

## Current Version

v0.10.x - Identity Platform Completion

---

## Roadmap Principle

HAP is an identity-first hybrid administration console.

The User Lookup workflow is the central identity hub. Identity facts that describe a person should remain in the user hydration model and user panels. Operational actions that administer objects should become workflows. External systems should remain providers.

Architectural rule:

> Everything that describes a person belongs to the HybridCompositeUser / User workflow. Everything that performs an operation belongs to a workflow. Everything that communicates with an external system belongs to a provider.

This prevents identity attributes such as licenses, mailbox facts, groups, authentication posture, risk, manager, and PIM from being incorrectly split into standalone modules.

---

## Completed Foundation

- Milestone 1 - Foundation
- Milestone 2 - Domain Model
- Milestone 3 - Provider Architecture
- Milestone 4 - Active Directory Provider
- Milestone 5 - Microsoft 365 Cloud Foundation
- Milestone 6 - Authentication Infrastructure
- Milestone 7 - Service Layer & Vertical Integration
- Milestone 8 - Runtime Platform
- Milestone 8.1 - Runtime Platform Hardening
- Milestone 8.2 - Branding & Theme System
- Milestone 9 - Background Runtime Services

Milestone 9 delivered the runtime event bus, provider refresh scheduling foundation, runtime service orchestration, provider status synchronization events, cache invalidation events, task lifecycle tracking, cancellation tracking, and progress-event foundation.

---

## Current Track

## Milestone 10 - Identity Platform Completion

Status: Mostly complete / stabilization required.

Goal: finish the User Lookup experience and achieve parity with the legacy administration tool while preserving the identity-first architecture.

Milestone 10 was previously described as broad enterprise features. The codebase has since evolved: many of those capabilities are already implemented inside the User workflow rather than as separate modules. That is the correct architecture.

### User Lookup / Identity Hub

Current capability areas:

- Active Directory attributes are already being pulled.
- Manager and direct-report data are pulled through Active Directory.
- Group membership is already pulled.
- Microsoft Graph user data is wired into the user flow.
- Exchange Online mailbox information is wired into the user flow.
- Exchange On-Premises recipient / remote mailbox information is wired into the user flow.
- Authentication posture pulls Microsoft cloud identity information such as MFA/authentication method and sign-in posture details.
- Licenses are intended to be pulled as part of the user Graph profile, but the current implementation likely has a service/UI parity bug.
- PIM has been attempted but is not confirmed functional.
- Risk is currently shallow and should be expanded beyond simple yes/no risky sign-in indication.

### Milestone 10 remaining work

#### Graph profile parity and user hydration stabilization

- Fix license display/hydration parity.
- Ensure the user flow preserves `Licenses`, `AssignedLicenses`, `LicenseAssignmentStates`, license diagnostics, PIM roles, and PIM diagnostics from the richer Graph profile path.
- Avoid creating a standalone License module for identity facts.
- Keep license facts in the User workflow unless/until a true License Administration workflow is created in Milestone 11.

#### Authentication and risk

- Improve authentication method coverage.
- Improve MFA posture display.
- Add or repair password-last-changed display where available.
- Improve last interactive and non-interactive sign-in display.
- Expand risk details beyond yes/no.
- Improve sign-in risk / user risk / risky sign-in diagnostics.
- Improve Conditional Access evaluation/status messaging where available.

#### PIM

- Validate whether PIM data can be queried in the target cloud.
- Preserve delegated-access requirements where app-only access is insufficient.
- Display eligible and active role assignments where available.
- Display clear unavailable/deferred/error diagnostics when PIM cannot be queried.

#### Exchange identity details

- Live-validate Exchange Online mailbox provider behavior.
- Live-validate Exchange On-Premises recipient / remote mailbox behavior.
- Validate distribution groups.
- Validate mailbox delegation.
- Validate shared mailbox access where supported.
- Validate remote mailbox attributes.
- Validate archive status, litigation hold, forwarding, and mailbox statistics where supported.

#### Directory identity details

- Confirm Badge ID, office, phone numbers, state, extension attributes, manager hierarchy, and direct reports.
- Preserve both direct properties and Attributes-bag values through provider, service, aggregation, and UI layers.

#### User management parity

- Complete New User Wizard parity with `legacy\New_User_Wizard.ps1`.
- Implement/complete Modify User workflow.
- Implement/complete Disable User workflow.
- Implement/complete Offboarding workflow.
- Add account unlock/reset actions where appropriate.
- Add password reset actions where appropriate.
- Add user-scoped group, license, and Exchange actions only as explicit operator-confirmed administration actions.

#### Runtime stabilization

- Improve provider diagnostics.
- Improve vertical error reporting.
- Improve background refresh/status behavior.
- Improve provider health status rendering.
- Optimize user hydration performance.

### Milestone 10 first independent workflow

Device Management remains valid as a separate workflow because devices are a one-to-many operational area rather than a single identity fact.

Device Management scope:

- Search user devices.
- Show Intune device details.
- Show compliance state.
- Show stale check-in counts.
- Show primary user mapping.
- Prepare later operational actions such as sync, retire, wipe, BitLocker recovery, Autopilot, and remote actions.

---

## Milestone 11 - Administrative Workflows

Status: Started / planned.

Goal: move HAP beyond User Lookup into dedicated administration workspaces. These workflows perform operations and manage object types; they should not duplicate identity facts already shown in the User workflow.

### Device Management

- Search devices directly.
- Intune details.
- Compliance details.
- BitLocker recovery keys.
- Autopilot details.
- Remote actions.
- Primary user and device timeline.

### Group Management

- Security groups.
- Distribution groups.
- Microsoft 365 groups.
- Dynamic groups.
- Membership comparison.
- Bulk membership changes.

### Mailbox Administration

- Shared mailboxes.
- Room mailboxes.
- Equipment mailboxes.
- Mailbox permissions.
- Forwarding.
- Mail flow.
- Quarantine.
- Message trace.

### License Administration

This is an operational workflow, not the same as user license facts.

- License inventory.
- License utilization.
- Assign/remove licenses.
- Bulk licensing.
- Group-based licensing.
- SKU reporting.

### Application Management

- Enterprise applications.
- App registrations.
- Service principals.
- Certificates.
- Client secrets.
- Expiration reporting.

### Bulk Operations

- Bulk user updates.
- Bulk licensing.
- Bulk group changes.
- Bulk mailbox changes.
- CSV import/export.

---

## Milestone 12 - Enterprise Operations

Status: Planned.

Goal: add cross-environment operations, investigations, reporting, and enterprise visibility.

### Security Operations

- Conditional Access reporting.
- Risk dashboards.
- Secure Score.
- Identity Protection.
- Defender integration.
- Sign-in investigations.

### Azure Operations

- Subscriptions.
- Resource groups.
- Virtual machines.
- Storage.
- Key Vault.
- Networking.

### Exchange Operations

- Mail flow analysis.
- Connectors.
- Accepted domains.
- Transport rules.
- Message tracking.
- Hybrid configuration.

### Teams Administration

- Teams inventory.
- Team ownership.
- Channels.
- Policies.
- Voice.
- Meetings.

### Reporting

- Executive dashboard.
- Scheduled reports.
- Compliance reports.
- User lifecycle reports.
- Device reports.
- Licensing reports.

### External Integrations

- JAMIS.
- Paxton.
- SQL reporting.
- SharePoint automation.
- Sentinel integration.

---

## Milestone 13 - Enterprise Platform

Status: Planned.

Goal: turn HAP into a production-grade extensible enterprise platform.

### Plugin and extension framework

- Provider SDK.
- Workflow SDK.
- Extension loading.
- Custom dashboards.

### Configuration and migration

- Profile migration.
- Configuration validation.
- Secrets management.
- Version migration.

### Enterprise deployment

- Installer.
- Automatic updates.
- Code signing.
- Release channels.

### Audit and history

- Operation history.
- Administrative audit log.
- Search history.
- Export logs.

### Product polish

- UI refinement.
- Accessibility.
- Theme improvements.
- Performance tuning.
- Comprehensive documentation.

---

## Long-Term Vision: v1.0 - Hybrid Enterprise Platform

After Milestone 13, HAP should evolve from a unified admin console into a hybrid enterprise operations platform.

Examples:

- Create New Employee: AD -> Entra -> Exchange -> Licensing -> JAMIS -> Paxton.
- Offboard Employee: coordinated reverse workflow across connected systems.
- Approval-based administrative actions.
- Scheduled automation jobs.
- Provider health monitoring.
- Cross-provider search across AD, Entra, Exchange, Intune, JAMIS, Paxton, SQL, and other systems.

---

## Current Estimate

| Milestone | Status | Estimated Completion |
| --- | --- | ---: |
| v0.1-v0.8 Foundation | Complete | 100% |
| v0.9 Runtime/Architecture | Complete | 100% |
| v0.10 Identity Platform | Mostly complete / stabilizing | 85-90% |
| v0.11 Administrative Workflows | Started | 15% |
| v0.12 Enterprise Operations | Planned | 5% |
| v0.13 Enterprise Platform | Planning | 0% |
