# Engineering Guide

## Version 0.6 Microsoft 365 Platform Notes

Version 0.6 builds Microsoft 365 capabilities on top of the Version 0.5 cloud foundation.

### Phase 6.1: Authentication Manager

Phase 6.1 introduces the authentication manager and adapter contract.

The manager owns:

- Authentication adapter registration
- Session cache lookup
- Session cache replacement
- Refresh-window detection
- Session acquisition routing
- Device Code Flow rejection

Providers must ask the platform for sessions through `Get-HybridAuthenticationSession`.

Providers must not call MSAL, WAM, browser login, client credentials, or managed identity directly.

### Offline Testing

Phase 6.1 remains offline-testable.

Mock adapters return valid `Hybrid.AuthenticationSession` objects without requiring Microsoft Graph, MSAL, internet access, or live credentials.

### Live Auth Boundary

`Core.Authentication.MSAL` currently establishes the adapter contract shape. Live token acquisition can be wired behind this contract without changing provider behavior.

# Architecture after Milestone 7

The project has transitioned from provider-centric to service-centric.

Search operations now flow through the following layers:

UI

↓

Aggregation Service

↓

Vertical Services

↓

Providers

↓

Infrastructure

Each vertical owns a single responsibility:

Active Directory

Exchange

Microsoft Graph

Authentication

The Aggregation Service coordinates vertical retrieval while remaining provider-agnostic.

This architecture is considered stable and will remain the foundation for future milestones.
---

# Version 0.8 Runtime Platform Notes

## Milestone 8 Phase 2: Runtime Bootstrap Engine

The Runtime Bootstrap Engine is implemented in `src/Core/Core.Runtime.psm1` and is the startup orchestration boundary for runtime-profile-driven launches.

### Public API

- `Initialize-HybridRuntime`
- `Get-HybridRuntime`
- `Reset-HybridRuntime`

### Runtime ownership

Runtime bootstrap is Core infrastructure. UI scripts must not load profiles, decide provider modes, or initialize provider stacks directly once they are migrated to the runtime path in later phases.

### Authentication boundary

Phase 2 does not perform live authentication or provider connectivity checks. Live providers are registered as deferred runtime records. This preserves startup safety and keeps authentication verification reserved for the diagnostics/authentication phases.

### Simulation behavior

Simulation profiles initialize the Directory Simulator and wire the existing service-backed verticals through application services. This allows the runtime engine to exercise the vertical service layer without live Microsoft dependencies.

### Additive development rule

The runtime engine extends the existing Milestone 8 Phase 1 Runtime Profile foundation. It does not alter profile contracts, UI behavior, or previous milestone exports.
