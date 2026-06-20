# Changelog

## 0.5.0-dev

### Added

- Added `Core.HttpResponse` for standardized HTTP response and error contracts.
- Added `Core.HttpRetry` for retry policy contracts and retry execution.
- Added `Core.HttpPipeline` for shared HTTP request construction and mock transport execution.
- Added bearer token injection from `Hybrid.AuthenticationSession`.
- Added correlation ID and User-Agent header injection.
- Added HTTP pipeline diagnostics and pagination state contracts.
- Extended Milestone 5 tests through Phase 5.

### Notes

- Phase 5 intentionally uses mock transports only.
- Phase 5 does not call Microsoft Graph, acquire tokens, or require network access.
- `Project_Status.md`, `ROADMAP.md`, and `VERSION.md` are updated during the final phase of the version.
