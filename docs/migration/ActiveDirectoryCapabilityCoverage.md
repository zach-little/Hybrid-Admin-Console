# Active Directory Capability Coverage

## Task 34 Disposition

| Capability | Current HAP Use | Native Path | Disposition |
| --- | --- | --- | --- |
| Connection/session | Runtime provider health | LDAP/DirectoryServices protocol binding | NativeSupported |
| User search | User lookup and selected user hydration | LDAP paged search | NativeSupported |
| User attributes | Directory Facts and edit dialog | LDAP attribute read/write with allowlist | NativeSupported |
| Group membership read | User groups and distribution membership context | LDAP member/memberOf reads | NativeSupported |
| Manager/direct reports | Manager changes and move reports workflow | LDAP manager/directReports attributes | NativeSupported |
| OU lookup | New User Wizard preflight | LDAP OU/container search | NativeSupported |
| Password/enable/disable | Account administration | LDAP/AD supported account operations | NativeSupportedWithGatedLabWrites |
| Exchange recipient attributes | GAL visibility, mailbox forwarding, recipient state | Exchange-owned administration | BlockedOrExchangeOwned |
| Device search | On-prem computer lookup | LDAP computer search | NativeSupported |

## Native Scope for Tasks 35-38

- Task 35 implements connection/read contracts and separates connection failures from lookup misses.
- Task 36 exposes write capability results behind explicit lab opt-in and rejects Exchange-owned mutations.
- Task 37 routes AD portions of hybrid workflows through native provider contracts.
- Task 38 retires legacy AD only after lab parity validation.

## Live Lab Gate

- Lab domain only.
- Dedicated test OU.
- Non-production test accounts and groups.
- Rollback plan for manager, membership, enable/disable, move, and ordinary attribute writes.
