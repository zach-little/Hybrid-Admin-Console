# Changelog

## 0.5.0-dev

### Added

- Added `Core.TenantContext` for tenant identity metadata.
- Added `Core.OrganizationContext` for organization-wide runtime state.
- Added tenant default domain resolution.
- Added organization provider registration helpers.
- Added organization capability registration helpers.
- Added `Core.Authentication` framework shell.
- Added authentication policies, methods, and request contracts.
- Added authentication session, token descriptor, authentication result, cache key, and cache entry contracts.
- Added shared HTTP response, retry, request, pipeline, pagination, and diagnostic contracts.
- Added Microsoft Graph provider foundation.
- Added Microsoft Graph client built on the shared HTTP pipeline.
- Added Microsoft Graph user, group, and organization wrapper modules.
- Added Microsoft Graph model conversion contracts.
- Added Microsoft Graph endpoint builder infrastructure.
- Added Microsoft Graph OData query builder infrastructure.
- Added Microsoft Graph error translator contracts.
- Added Microsoft Graph request builders for users, groups, and organization resources.
- Added Microsoft Graph diagnostics and provider runtime state contracts.
- Added Microsoft Graph batch request and response contracts.
- Added Microsoft Graph mapper infrastructure.
- Extended Milestone 5 tests through Phase 5.6.1.

### Notes

- Phase 5.6.1 intentionally does not authenticate, call Microsoft Graph live, or implement MSAL.
- Batch support is contract-only in Version 0.5.
- `Project_Status.md`, `ROADMAP.md`, and `VERSION.md` are updated during the final phase of the version.
