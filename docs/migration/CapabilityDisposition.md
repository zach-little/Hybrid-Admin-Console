# Capability Disposition

## Directory Simulator

| Capability | Disposition | Migration Task | Notes |
| --- | --- | --- | --- |
| ProviderHealth | Retain, port native | Task 23 | First native simulator slice. |
| UserLookup | Retain, port native | Task 23 | Initial operation: read-only search/get user summary. |
| ManagerLookup | Retain, port native later | Task 25 | Depends on native user data model. |
| GroupMembershipRead | Retain, port native later | Task 25 | Read-only groups from simulator user fixtures. |
| DirectReportsRead | Retain, port native later | Task 25 | Read-only hierarchy from simulator seed data. |
| DeviceLookup | Retain, port native later | Task 25 | Includes generated and seeded device records. |
| GraphProfileRead | Retain, port native later | Task 25 | Requires stable timestamp normalization. |
| AuthenticationPostureRead | Retain, port native later | Task 25 | Requires stable timestamp normalization. |
| MailboxRead | Retain, port native later | Task 25 | Read-only mailbox summary and statistics. |
| MailboxDelegationRead | Retain, port native later | Task 25 | Read-only simulated delegation list. |
| DistributionGroupsRead | Retain, port native later | Task 25 | Read-only simulated distribution groups. |
| Simulator mutations | Retain, port native later | Task 26 | Not part of the first read-only slice. |

## Task 22 Decision

The first native parity slice is intentionally small: ProviderHealth plus UserLookup only. It is sufficient to prove native provider contracts, deterministic simulator data, cancellation/timeout behavior, and no-PowerShell enforcement without changing production routing.
