# Changelog

## 0.5.0-dev

### Added

- Added `Hybrid.TokenDescriptor` contract for provider-neutral token metadata.
- Added token descriptor validation.
- Added `Hybrid.AuthenticationResult` contract for future authentication success and failure results.
- Added session state resolution through `Get-HybridAuthenticationSessionState`.
- Added authentication cache key and cache entry contracts.
- Extended authentication sessions to accept token descriptors.
- Extended Milestone 5 tests through Phase 4.

### Notes

- Phase 4 intentionally does not authenticate, call MSAL, call WAM, call Microsoft Graph, or persist tokens.
- `Project_Status.md`, `ROADMAP.md`, and `VERSION.md` are updated during the final phase of the version.
