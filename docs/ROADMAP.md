# Roadmap

## Current Version

v0.8.8

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

This stabilization release should be completed before Milestone 9.

Primary goals:

- Fix Active Directory Distinguished Name display.
- Fix Active Directory Organizational Unit display.
- Ensure AD detail display reads from the actual service-layer object shape returned in live environments.
- Preserve friendly group display formatting.
- Separate hybrid AD mail attributes from real Exchange Online provider data.
- Prevent Exchange from showing as loaded unless the Exchange Online provider actually returned mailbox data.
- Improve Graph, Exchange, and Authentication vertical status messages when services are not registered, deferred, or unavailable.
- Add a Back/Start button to return from the main console to Runtime Home/Profile selection.
- Add a bottom-center search progress bar to the left of the active profile indicator.
- Continue writing persistent runtime, AD, and hydration diagnostics.
- Remove leftover backup/repair artifacts before tagging.

Suggested validation tests:

- `Test-Milestone8_8GroupOuDisplay.ps1`
- New `Test-Milestone8_9DnOuDisplay.ps1`
- New `Test-Milestone8_9RuntimeNavigation.ps1`
- New `Test-Milestone8_9SearchProgress.ps1`
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

