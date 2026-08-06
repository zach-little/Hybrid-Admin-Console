# Live Validation Runbook

## Task 22 Baseline

The first native provider parity slice targets the Directory Simulator only. No live tenant, domain, Exchange, Graph, or Active Directory validation is required for Task 22 or Task 23.

## Simulator Validation

Task 23 should validate native simulator behavior with deterministic fixtures only:

- Provider health success.
- Seeded user lookup by SAM account name.
- Seeded user lookup by UPN.
- Generated fallback user warning.
- Invalid query failure.
- Unavailable provider failure.
- Invalid configuration failure.
- Cancellation failure.
- Timeout failure.
- Multiple-match warning.
- Partial-user-data warning.

## Future Live Validation

Live validation starts with the Graph, Active Directory, and Exchange supportability gates. Those tasks must add environment prerequisites, required permissions, safe read-only test accounts, rollback expectations, and explicit write-operation approval steps before any live mutation is attempted.
