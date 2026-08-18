# HILOP Patch Notes - License Friendly Names and ADM Mailboxless Lookup

## Scope

This drop-in patch updates three source files only:

- `src/Core/Core.Provider.MicrosoftGraph.psm1`
- `src/Application/Application.HybridUserService.psm1`
- `src/UI/Start-HybridAdminConsole.ps1`

## Changes

### License display names

Microsoft Graph license objects now preserve the raw `SkuPartNumber`, but expose a friendlier `DisplayName` for common Microsoft 365, Office 365, Exchange, Intune, Entra, EMS, Visio, Project, Power BI, and GCC/GCC High SKUs.

The UI also performs a defensive friendly-name conversion when it receives raw license strings or older license objects, so the license list should show values like:

- `Office 365 E3`
- `Microsoft 365 E3`
- `Microsoft 365 G3 GCC/GCC High`
- `Exchange Online Plan 2`

instead of raw SKU identifiers like `ENTERPRISEPACK`, `SPE_E3`, or `M365_G3_GOV`.

### ADM / mailboxless account handling

`Add-HybridUserMailboxDetails` now skips Exchange Online mailbox lookup when the AD record has no mail signal:

- no `mail`
- no `proxyAddresses`
- no `targetAddress`
- no `mailNickname` / alias signal

This matches the existing Exchange On-Premises skip logic and prevents ADM/admin-only accounts from waiting on Exchange mailbox failures when they are synced to Azure but intentionally do not have mailboxes.

### Graph timeout hardening

Optional Graph enrichment calls now use a shorter timeout, and Graph user search now has a request timeout. This keeps optional enrichments such as license details, risk, PIM, and sign-in enrichment from stalling the whole lookup as long when Graph endpoints or permissions fail slowly.

## Validation targets

After applying the patch, test these cases:

1. A normal licensed mailbox user:
   - Graph loads.
   - Licenses display as friendly product names.
   - Exchange mailbox still loads.

2. An ADM/admin account synced to Azure without Exchange mail:
   - Graph should still load from Azure.
   - Exchange Online lookup should be skipped quickly.
   - Exchange summary should report no mailbox data instead of hanging.

3. A user with GCC/GCC High licensing:
   - `M365_G3_GOV` and `M365_G5_GOV` display as friendly GCC/GCC High names.

## Notes

This patch does not create a separate license module. License information remains part of the user identity/Graph profile workflow, consistent with the revised v0.10 roadmap direction.
