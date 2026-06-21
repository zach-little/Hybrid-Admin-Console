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

### Fixed
- Fixed `Core.Authentication.MSAL` contract adapters to create sessions through the shared `AuthenticationRequest` contract instead of passing deprecated tenant/cloud parameters directly.

### Notes
- Phase 6.1 does not perform live Microsoft authentication yet.
- Device Code Flow remains unsupported.
