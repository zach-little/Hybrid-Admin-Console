# Changelog

## 0.5.0-dev

### Added

- Added `Core.TenantContext` for tenant identity metadata.
- Added `Core.OrganizationContext` for organization-wide runtime state.
- Added tenant default domain resolution.
- Added organization provider registration helpers.
- Added organization capability registration helpers.
- Added authentication framework shell with enterprise authentication policy support.
- Added authentication method registration while explicitly rejecting Device Code Flow.
- Added authentication request construction with sovereign authority resolution.
- Added authentication session and token descriptor contracts.
- Added authentication result, cache key, cache entry, and session validation helpers.
- Added shared HTTP response, retry, and pipeline infrastructure.
- Added mock-transport HTTP pipeline support for offline provider testing.
- Added Microsoft Graph provider foundation.
- Added cloud-aware Graph client built on the shared HTTP pipeline.
- Added initial Graph user, group, and organization wrappers.
- Added initial Graph-to-Hybrid model conversion contracts.
- Extended Milestone 5 tests through Phase 6.

### Notes

- Phase 6 intentionally does not authenticate, load MSAL, call Microsoft Graph, or require internet access.
- Microsoft Graph consumes the shared authentication session and HTTP pipeline contracts created earlier in Version 0.5.
- `Project_Status.md`, `ROADMAP.md`, and `VERSION.md` are updated during the final phase of the version.
