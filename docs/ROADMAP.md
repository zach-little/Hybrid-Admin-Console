# Roadmap

## Current Version

v0.9.0

---

## Completed

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

## Current Track

### v0.9.0 — Background Runtime Services

Milestone 9 is complete after the v0.8.9 live-readiness stabilization pass.

Completed:

- Runtime event bus module added.
- Runtime bootstrap now registers a `RuntimeEventBus` service.
- Runtime initialization emits structured events for future background services and status synchronization.
- Runtime service orchestrator module added.
- Runtime bootstrap now registers a `RuntimeServices` service.
- Provider refresh schedules are registered during runtime bootstrap.
- Provider refreshes publish started, completed, failed, and status synchronization events.
- Cache invalidation publishes structured runtime events.
- Runtime tasks are tracked with started, completed, failed, cancellation-requested, and cancelled events.
- BadgeID compatibility was tightened so the legacy AD `BadgeID` attribute is requested and mapped.

Completed in v0.8.9:

- Active Directory Distinguished Name display path tightened.
- Active Directory Organizational Unit display path tightened.
- AD detail display now reads direct properties and Attributes-backed values returned by the service layer.
- Friendly group display formatting preserved.
- Hybrid AD mail attributes are separated from real Exchange Online provider mailbox data in the UI.
- Exchange is not shown as loaded unless the Exchange Online provider returns mailbox details.
- Back/Start button added to return from the main console to Runtime Home/Profile selection.
- Bottom-center search progress bar added to the left of the active profile indicator.
- Persistent runtime, AD, and hydration diagnostics continue.
- Duplicate AD search matches now show a chooser before user hydration.
- On-premises Exchange provider slice added for hybrid recipient/remote mailbox lookup.
- Runtime Home provider card now renders provider detail lines dynamically instead of using a hardcoded AD/Graph/EXO list.
- Exchange mailbox hydration now accepts Exchange On-Premises remote mailbox data as valid mailbox detail data when Exchange Online is unavailable.

Carried-forward validation notes:

- Live-validate on-premises Exchange remote mailbox, forwarding, and distribution-group retrieval against the local Exchange server.
- Improve Graph, Exchange, and Authentication vertical status messages when services are not registered, deferred, unavailable, or failed.
- Remove leftover backup/repair artifacts before tagging.

Suggested validation tests:

- `Test-Milestone8_8GroupOuDisplay.ps1`
- `Test-Milestone8_9DnOuDisplay.ps1`
- `Test-Milestone8_9RuntimeNavigation.ps1`
- `Test-Milestone8_9SearchProgress.ps1`
- `Test-Milestone8_9DuplicateUserChooser.ps1`
- `Test-Milestone8_9ExchangeOnPremisesProvider.ps1`
- `Test-Milestone8_9ExchangeOnPremisesRuntimeHydration.ps1`
- Existing Milestone 8 hardening/branding/diagnostics tests

---

## Milestone 9 — Background Runtime Services

Status: Complete.

Focus:

- Runtime event bus
- Provider refresh scheduling foundation
- Automatic cache invalidation events
- Provider status synchronization events
- Runtime notifications event foundation
- Long-running task framework
- Cancellation and progress reporting event foundation

Milestone 9 built the runtime-services foundation. Full worker-threaded non-blocking card refresh remains a future UI implementation task because live provider modules and authentication sessions need a dedicated runspace design.

---

## Milestone 10 — Enterprise Features

- Device Management
- Licensing
- Teams
- SharePoint
- Security
- Compliance
- Exchange Enhancements
- Azure Resource Management

---

## Milestone 11 — Extensibility

- Plugin SDK
- Third-party providers
- Extension discovery
- Provider marketplace
- Runtime extension loading

---

## Milestone 12 — Production Release

- Installer
- Auto-update
- Telemetry options
- Enterprise deployment
- Code signing
- Documentation completion
- Release packaging discipline

## v0.9C - Workflow Framework and New User Wizard Shell

- Add a post-profile workflow selector.
- Preserve User Lookup as the current Hybrid Admin Console workflow.
- Add New User Wizard as a service-backed workflow shell.
- Migrate legacy wizard mappings into an application service.
- Provide validation and preview-only planned actions.
- Defer destructive user creation/write execution until the preview plan is verified.
