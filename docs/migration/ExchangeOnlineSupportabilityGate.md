# Exchange Online Supportability Gate

## Task 39 Disposition

| Operation | Current HAP Use | Native Public Surface | Disposition |
| --- | --- | --- | --- |
| Provider health/session | Runtime status | Supported auth/session checks only | NativeSupported |
| Basic mailbox identity read | User mailbox card identity fields | Public Graph/mailbox-related read surfaces where available | NativeSupportedWithBehaviorChange |
| Mailbox statistics | Mailbox size/item count/last logon | No approved first-party native public API selected | UnsupportedWithoutPowerShell |
| Mailbox delegation | FullAccess/SendAs delegate management | No approved first-party native public API selected | UnsupportedWithoutPowerShell |
| Distribution group membership | Add/remove/list Exchange DGs | No approved first-party native public API selected for Exchange-owned DG administration | UnsupportedWithoutPowerShell |
| GAL hide/show | Recipient visibility | Exchange recipient administration | UnsupportedWithoutPowerShell |
| Mailbox forwarding | Exchange mailbox forwarding | Requires product decision; do not reverse engineer EXO PowerShell REST internals | RemoveOrDefer |

## Task 40 Approved Native Scope

- Native Exchange Online provider may authenticate, validate permissions, report limited health, and return basic mailbox identity fields from approved public API sources.
- Unsupported Exchange administration operations must return explicit `Unsupported` errors.
- No reverse engineering of private Exchange Online PowerShell endpoints.
- No hidden first-party PowerShell fallback.

## Product Decisions Required

- Whether to remove/defer Exchange mailbox delegation editing from first-party native HAP.
- Whether Exchange admin work should become customer extension territory.
- Whether mailbox statistics are required enough to retain a PowerShell extension path.
- Whether GAL visibility and forwarding should remain in legacy until a documented public API is chosen.
