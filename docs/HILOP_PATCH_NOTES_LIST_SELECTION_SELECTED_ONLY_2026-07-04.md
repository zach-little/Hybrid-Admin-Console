# HILOP Patch Notes - List Selection Selected-Only Contrast

Date: 2026-07-04

## Purpose

Corrects the previous list selection contrast patch so list item foregrounds are not forced to white during normal/unselected state.

## Changes

- Preserves the File/Edit menu highlight contrast fix.
- Removes the global base foreground override from ListBoxItem and ListViewItem styles.
- Keeps the selected-state override only:
  - selected row background: navy
  - selected row text: white
- Allows unselected ListBox/ListView rows to inherit their normal/default text color from the parent control or existing item content.

## Files Updated

- `src/UI/Start-HybridAdminConsole.ps1`

## Validation Notes

After applying the drop-in:

1. Open User Lookup.
2. Confirm File/Edit menu highlighted items remain readable.
3. Search a user with values in Groups, Direct Reports, Delegation, Distribution Groups, Licenses, and PIM Roles.
4. Confirm unselected rows are not forced white.
5. Select a row and confirm the selected row is navy with white text.
