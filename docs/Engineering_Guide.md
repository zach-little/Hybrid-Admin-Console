# Engineering Guide

## Development Process

Every phase produces:
- Changed source files
- Updated tests
- Engineering_Guide.md
- CHANGELOG.md
- MANIFEST.txt
- Drop-in ZIP (changed files only)

Project_Status, ROADMAP and VERSION are updated only during the final phase of a version.

Use the standard validation procedure before considering a phase complete.

```powershell
Get-ChildItem -Path . -Recurse -File | Unblock-File
Remove-Module Infrastructure.ActiveDirectory,Core.ProviderBase,ActiveDirectory,Hybrid.Models -Force -ErrorAction SilentlyContinue
.\tests\Test-MilestoneX.ps1
```
