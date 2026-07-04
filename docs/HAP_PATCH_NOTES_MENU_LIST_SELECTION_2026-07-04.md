# HAP Patch Notes - Menu and List Selection Contrast

Date: 2026-07-04

## Scope

This is a UI-only drop-in patch for the Hybrid Admin Platform user selection console.

## Changes

- Updated global `MenuItem` highlight styling so File/Edit menu highlight states use dark readable text on the lighter highlight background.
- Updated global `ListBoxItem` selected-row styling so selected rows keep the existing navy selection background but render selected text in white.
- Added matching `ListViewItem` selected-row styling for programmatic ListView dialogs and future list-based UI surfaces.

## Primary affected screen areas

- User selection File menu
- User selection Edit menu
- Mailbox Delegation list
- Distribution Groups list
- Groups list
- Direct Reports list
- Graph Licenses list
- PIM Roles list
- Authentication method/risk detail lists

## Files included

- `src/UI/Start-HybridAdminConsole.ps1`
- `docs/HAP_PATCH_NOTES_MENU_LIST_SELECTION_2026-07-04.md`

## Notes

No provider, Graph, Exchange, licensing, ADM handling, or workflow behavior was changed.
