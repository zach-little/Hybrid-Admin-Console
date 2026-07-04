# Milestone 10 Codex Handoff

Use this note when starting the next Codex session.

## Direction

HAP is identity-first. User Lookup is the identity hub. Do not split identity facts into standalone modules.

## Immediate Task

Fix license and PIM data propagation in the existing User Lookup path.

Specifically, inspect whether the UI path prefers `Get-HybridUserGraphProfile` over `Get-HybridGraphProfile`. If so, either route through the richer graph profile service or update `Get-HybridUserGraphProfile` so it preserves all richer Graph profile fields.

Fields that must survive to the UI where available:

- Licenses.
- AssignedLicenses.
- LicenseAssignmentStates.
- License diagnostics.
- PIM roles.
- PIM diagnostics.
- Authentication method details.
- Risk details.

## Guardrails

- Do not create a standalone License module for user license display.
- Do not duplicate the user hydration pipeline.
- Do not create new verticals for facts already owned by the User workflow.
- Providers should only talk to external systems.
- Services should compose provider data.
- Workflows should perform operator actions or manage independent object workspaces.

## Validation

After implementation, validate that User Lookup displays license details for a user with assigned licenses and still renders clean diagnostics when Graph licensing data is unavailable.
