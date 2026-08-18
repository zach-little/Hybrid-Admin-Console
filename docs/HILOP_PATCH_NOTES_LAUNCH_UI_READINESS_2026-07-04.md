# HILOP Patch Notes - Launch UI Readiness Polish - 2026-07-04

## Scope
This drop-in patch updates only the main runtime launch/user selection UI in `src/UI/Start-HybridAdminConsole.ps1`.

## Changes
- Snaps the File/Edit menu bar to the top-left edge of the console view instead of leaving it visually floating inside the content margin.
- Replaces noisy launch-page cards with more actionable operational summaries:
  - `PROFILE READINESS`
  - `LAUNCH REQUIREMENTS`
  - `LAUNCH READINESS`
  - `OPERATIONAL PREVIEW`
- Removes device-code wording from the launch/profile preview UI.
- Stops treating authentication as a fake provider-status line.
- Makes provider readiness summarize blockers and enabled providers instead of dumping long provider/status strings.
- Makes runtime preview show what will load, configuration blockers, and operator impact.

## Notes
Live connectivity is still validated during launch and user hydration. This patch only improves the pre-launch UI and does not alter provider connection behavior.
