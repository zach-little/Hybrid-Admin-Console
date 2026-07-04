# HAP UI Patch - Workflow Selector Copy and Highlight Readability

Date: 2026-07-04

## Scope

This drop-in patch updates the workflow selection screen shown after a runtime profile is launched.

## Changes

- Removed visible version/milestone wording from the three workflow cards.
- Replaced workflow card descriptions with enterprise-ready application language.
- Renamed the card label from "Device Management" to "Device Manager" to match the requested workflow naming.
- Added a dedicated `WorkflowCardButton` style for the workflow selector cards.
- Added workflow card title, description, and highlight text styles with darker hover/pressed foreground colors so text remains readable against the lighter highlight background.

## Files included

- `src/UI/Start-HybridAdminConsole.ps1`
- Prior drop-in files from `HAP_License_FriendlyNames_ADM_Fix.zip` are retained so applying this UI patch does not regress the license friendly-name / ADM mailboxless-account fixes.

## Notes

Apply this patch over the current repository root. It is intended to be a drop-in overlay.
