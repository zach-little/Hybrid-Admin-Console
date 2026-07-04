# HAP Patch Notes - Graph Count + Mailboxless Exchange Retry

## Purpose
Fix live-data failures observed after the prior license/ADM patch:

- `Graph profile failed: The property 'Count' cannot be found on this object.`
- Authentication posture failing with the same `.Count` issue.
- Mailboxless/admin-only synchronized accounts eventually returning `ExchangeOnlineMailbox: Loaded` even though no real Exchange Online mailbox exists.

## Changes

### `src/Core/Core.Provider.MicrosoftGraph.psm1`
- Added defensive collection-count helper for Graph enrichment paths.
- Replaced direct `.Count` checks in optional Graph enrichment logic with safe count checks.
- Normalized string license values into license display objects instead of returning raw SKU strings.
- Expanded common friendly-name mappings for security, GCC/GCC High, Rights Management, and Power Platform SKUs.

### `src/Application/Application.HybridUserService.psm1`
- Added defensive collection-count helper for user-service Graph/auth profile shaping.
- Added mailbox object validation so wrapper/null/error-like Exchange Online responses are not treated as loaded mailboxes.
- Exchange Online statistics/delegation/distribution/forwarding calls now only run when the mailbox object looks like a real mailbox.

## Expected Result
- Graph profile and Authentication Posture should no longer fail on scalar/null/non-countable Graph responses.
- Mailboxless ADM/admin accounts should not show Exchange Online mailbox data as loaded unless a concrete mailbox object is returned.
- License rows should prefer friendly names when a SKU part number or subscribed SKU map is available.
