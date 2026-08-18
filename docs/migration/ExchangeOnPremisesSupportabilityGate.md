# Exchange On-Premises Supportability Gate

## Task 44 Disposition

| Operation | Current HILOP Use | Native Non-PowerShell Path | Disposition |
| --- | --- | --- | --- |
| Provider health/session | Runtime status | Connection/authentication checks only | NativeSupportedWithBehaviorChange |
| Remote mailbox read | User mailbox panel | No approved Exchange admin API configured | UnsupportedWithoutApprovedApi |
| Distribution group read/write | User group administration | No approved Exchange admin API configured | CustomerExtensionCandidate |
| Mailbox delegation | User mailbox delegation dialog | No approved Exchange admin API configured | CustomerExtensionCandidate |
| Mailbox forwarding | User mailbox forwarding dialog | No approved Exchange admin API configured | DeferredUnavailable |
| Exchange recipient mutation | GAL/recipient management | Do not replace with direct AD attribute edits | Unsupported |

## Task 45 Approved Native Scope

- Native provider may report health, connection, authentication, and limited availability.
- Recipient administration remains unavailable until a supported non-PowerShell management API is selected.
- Customer PowerShell extensions may provide organization-specific Exchange on-premises administration through the permanent extension host.

## Task 46 Cutover Decision

- Built-in Exchange on-premises legacy PowerShell routing should be removed.
- Unsupported retained UI actions must be disabled with the catalog reason.
- No Exchange Management Shell, remote PowerShell, `System.Management.Automation`, or unsupported directory mutation is allowed in the built-in provider.
