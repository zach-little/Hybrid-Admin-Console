# Changelog

## 0.5.0

### Added

- Added `Core.CloudEnvironment` for sovereign cloud endpoint registration and resolution.
- Added built-in Microsoft Commercial, GCC High, and DoD cloud environments.
- Added `Core.TenantContext` for tenant identity metadata.
- Added tenant default domain resolution.
- Added tenant cloud environment resolution.
- Added `Core.OrganizationContext` for organization-wide runtime state.
- Added organization singleton context registration.
- Added organization provider registration helpers.
- Added organization capability registration helpers.
- Added `Core.Authentication` framework shell.
- Added authentication policy contracts.
- Added authentication method registration.
- Added explicit rejection of Device Code Flow.
- Added authentication request contracts.
- Added authentication session contracts.
- Added token descriptor contracts.
- Added authentication result contracts.
- Added authentication cache key and cache entry contracts.
- Added authentication session state helpers.
- Added shared HTTP response objects.
- Added standardized HTTP error objects.
- Added HTTP retry policy contracts.
- Added retry delay calculation.
- Added shared HTTP request objects.
- Added shared HTTP pipeline execution.
- Added HTTP pipeline diagnostics.
- Added HTTP pagination state.
- Added bearer token injection through the HTTP pipeline.
- Added correlation ID and User-Agent injection through the HTTP pipeline.
- Added Microsoft Graph client foundation.
- Added Microsoft Graph provider foundation.
- Added Microsoft Graph provider health reporting.
- Added Microsoft Graph provider capability reporting.
- Added Graph user wrappers.
- Added Graph group wrappers.
- Added Graph organization wrapper.
- Added Graph user, group, and organization conversion contracts.
- Added Graph endpoint builder.
- Added Graph resource URI builder.
- Added Graph OData query builder.
- Added Graph error translator.
- Added Graph request builders.
- Added Graph diagnostics objects.
- Added Graph batch request and response contracts.
- Extended Milestone 5 tests through Phase 5.6.1.
- Added project development workflow standards to documentation.
- Added changed-files-only phase ZIP packaging standard.
- Added standard validation command requirements.

### Changed

- Updated Version 0.5 documentation to reflect completed cloud foundation work.
- Updated roadmap to mark Version 0.5 complete and Version 0.6 as the next planned release.
- Updated project status to reflect the completed Microsoft cloud foundation.
- Updated engineering documentation to describe the cloud foundation, HTTP pipeline, Graph foundation, and provider lifecycle.
- Standardized phase validation commands to include `Unblock-File`, module unloading, and milestone test execution.

### Notes

- Version 0.5 intentionally does not perform live Microsoft authentication.
- Version 0.5 intentionally does not require Microsoft Graph, MSAL, or internet access for tests.
- Microsoft Graph functionality is foundation-level only; expanded live Graph features begin in Version 0.6.
- Device Code Flow remains intentionally unsupported.
- `Project_Status.md`, `ROADMAP.md`, and `VERSION.md` are updated only during finalization phases.
