# Project Status

## Current Version

**Version:** 0.4.0
**Status:** Milestone 4 Complete

---

## Milestone Status

| Milestone                               | Status   |
| --------------------------------------- | -------- |
| Milestone 1 - Core Framework            | Complete |
| Milestone 2 - Domain Foundation         | Complete |
| Milestone 3 - Hybrid User Engine        | Complete |
| Milestone 4 - Active Directory Provider | Complete |
| Milestone 5 - Microsoft Graph Provider  | Next     |

---

## Completed Milestones

### Milestone 1 - Core Framework

Completed:

* Bootstrap
* Module Loader
* Configuration Manager
* Logging Framework
* Service Registry
* Plugin Loader
* Mock Provider
* Shell Host
* Framework Test Harness

### Milestone 2 - Domain Foundation

Completed:

* Domain Models
* User Service
* Mock Directory Provider
* Search-HybridUser
* Get-HybridUser
* Initial Unit Tests

### Milestone 3 - Hybrid User Engine

Completed:

* Canonical HybridUser object
* User hydration
* Mailbox hydration
* Group hydration
* Device hydration
* License hydration
* Manager hydration
* Direct Reports hydration
* Cache integration
* Unit tests

### Milestone 4 - Active Directory Provider

Completed:

* Active Directory provider
* Search
* User retrieval
* Groups
* Manager
* Direct Reports
* Password Reset
* Enable / Disable
* Unlock
* OU operations
* Group add / remove
* Manager update
* Provider registration
* Shared provider base
* Provider lifecycle
* Provider health
* Capability discovery
* Command wrapper
* Cache integration
* Structured errors
* NoNet support
* Provider contract tests

---

## Current Architecture

The platform now uses a layered, provider-driven architecture:

```text
UI
 ↓
Application Services
 ↓
Domain Models
 ↓
Provider Contracts
 ↓
Infrastructure Providers
```

Shared provider infrastructure now lives in the core layer and may be extended by infrastructure providers without violating provider independence.

---

## Next Objective

Begin Milestone 5 - Microsoft Graph Provider.

Primary focus:

* Graph provider skeleton
* GCC High support
* App-only authentication support
* Delegated authentication support
* PIM-compatible delegated role retrieval
* User properties
* Authentication methods
* Azure roles
* Conditional Access information
* Devices
* Sign-in information
* Risk information
* Provider health
* Capability discovery
* Unit tests
