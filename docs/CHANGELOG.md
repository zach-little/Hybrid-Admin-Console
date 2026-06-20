# Changelog

## 0.5.0-dev

### Added

- Added `Core.Authentication` framework shell.
- Added authentication policy contracts.
- Added authentication method registration and discovery.
- Added authentication request contract with sovereign authority resolution.
- Added authentication session contract and validation.
- Added charter enforcement that rejects Device Code Flow.
- Extended Milestone 5 tests through Phase 3.
- Added `Core.TenantContext` for tenant identity metadata.
- Added `Core.OrganizationContext` for organization-wide runtime state.
- Added tenant default domain resolution.
- Added organization provider registration helpers.
- Added organization capability registration helpers.

### Notes

- Phase 3 intentionally does not authenticate, call MSAL, or call Microsoft Graph.
- Phase 2 intentionally does not authenticate or call Microsoft Graph.
- `Project_Status.md`, `ROADMAP.md`, and `VERSION.md` are updated during the final phase of the version.
