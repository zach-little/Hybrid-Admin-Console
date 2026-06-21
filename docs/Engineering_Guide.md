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
