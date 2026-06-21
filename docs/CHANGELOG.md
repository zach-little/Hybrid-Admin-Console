# Changelog

## 0.6.0-dev

### Added
- Added `Core.Authentication.Manager` for authentication adapter registration and session routing.
- Added authentication session cache helpers.
- Added refresh-window detection for authentication sessions.
- Added `Get-HybridAuthenticationSession` as the provider-facing session entry point.
- Added mock authentication adapters for offline tests.
- Added `Core.Authentication.MSAL` contract adapter scaffolding.
- Added Milestone 6 Phase 1 authentication manager tests.
- Added live-capable MSAL token request construction through `New-HybridMsalTokenRequest`.
- Added MSAL runtime availability reporting through `Test-HybridMsalRuntimeAvailable`.
- Added injectable MSAL token acquisition boundary for live authentication without coupling tests to MFA, WAM, or external modules.
- Added MSAL token result normalization into the shared `Hybrid.TokenDescriptor` and `Hybrid.AuthenticationSession` contracts.
- Added Milestone 6 Phase 2 live-capable MSAL adapter tests.

### Notes
- Phase 6.1 does not perform live Microsoft authentication yet.
- Phase 6.2 introduces the live-capable MSAL adapter boundary while keeping automated tests offline and deterministic.
- Device Code Flow remains unsupported.
