# Milestone 8 Final UI Polish Hotfix 1

Corrects the final Runtime Home polish pass.

## Changes

- Preserves the final integration marker `Phase 8.3 RuntimeSummaryPanel`.
- Fixes the PowerShell string escaping bug in `Test-Milestone8FinalUiPolish.ps1`.
- Enlarges the default shell window to better support the Runtime Home layout.
- Restores the fixed action footer as a visible command-tile row.
- Replaces plain/native-looking action button content with styled command tile content.

## Validation

Run:

```powershell
.\tests\Test-Milestone8FinalUiPolish.ps1
.\tests\Test-Milestone8FinalIntegration.ps1
.\tests\Test-Milestone8Phase8_2.ps1
```
