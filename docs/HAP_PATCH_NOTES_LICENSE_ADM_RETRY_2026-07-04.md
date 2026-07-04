# HAP Patch Notes - License Friendly Names + ADM Exchange Skip Retry

Date: 2026-07-04

## Files changed

- `src/Core/Core.Provider.MicrosoftGraph.psm1`
- `src/Application/Application.HybridUserService.psm1`
- `src/UI/Start-HybridAdminConsole.ps1`

## Fixes

### License display

- Added a provider-side Microsoft SKU friendly-name resolver so Graph license objects carry both `DisplayName` and `FriendlyName`.
- Expanded the UI friendly-name resolver so raw SKU part numbers such as `SPE_E5`, `ENTERPRISEPACK`, `AAD_PREMIUM_P2`, `INTUNE_A`, and common GCC/GCC High SKU values render as readable product names.
- Updated the Graph license list formatter to prefer `FriendlyName`, then `DisplayName`, and only fall back to raw SKU values when no better name exists.
- Added a readable fallback for unknown Microsoft SKU constants by replacing underscores and normalizing casing instead of showing raw constants directly.

### Mailboxless ADM/admin accounts

- Tightened Exchange mailbox eligibility detection.
- `MailNickname` / `Alias` is no longer treated as proof that a user has an Exchange mailbox.
- Exchange Online base lookup now runs only when AD has an SMTP-bearing `mail`, `proxyAddresses`, or `targetAddress` value.
- Detailed Exchange mailbox hydration now also skips Exchange Online when no SMTP mail signal exists.
- Added diagnostics explaining that mailboxless ADM/admin accounts synced to Azure are expected to skip Exchange Online mailbox lookup.

## Expected behavior

- Normal mailbox users with SMTP attributes should still hydrate Exchange Online mailbox information.
- ADM/admin-only accounts synced to Azure but without mailbox attributes should no longer sit waiting for Exchange Online mailbox lookup timeout.
- Licenses should show readable names where known, and unknown SKU constants should at least be humanized.
