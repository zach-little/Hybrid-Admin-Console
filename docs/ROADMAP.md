# Roadmap

## Current Version

v0.8.9

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

## Current Pre-Milestone 9 Track

### v0.8.9 — Live Runtime UX & Vertical Stabilization

This stabilization release is the current validation target before Milestone 9.

Implemented in this pass:

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

Still planned before Milestone 9:

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

Begin only after the v0.8.9 live-readiness pass is complete.

Focus:

- Background refresh engine
- Runtime event bus
- Provider refresh scheduling
- Automatic cache invalidation
- Live provider reconnection
- Runtime notifications
- Status synchronization
- Long-running task framework
- Non-blocking card refresh
- Cancellation and progress reporting

Milestone 9 should build on the search progress and hydration-stage instrumentation introduced during the live-readiness stabilization work.

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

