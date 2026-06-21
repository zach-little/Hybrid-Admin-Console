# Changelog

## v0.8.0-dev — Milestone 8 Phase 2 Hotfix 1

- Fixed `Core.Runtime` diagnostics collection assignment during runtime bootstrap.
- Hardened runtime member replacement to avoid note-property type mismatches.
- Improved Phase 2 test guardrails around runtime context creation.

## v0.8.0-dev — Milestone 8 Phase 2 Hotfix 2

- Fixed runtime-imported application service commands not being visible to validation sessions.
- Runtime module imports dependency modules with `-Global` so existing public service commands remain available after bootstrap.
