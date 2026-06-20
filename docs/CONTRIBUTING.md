# Contributing

1. Read Engineering_Guide.md
2. Create feature branch.
3. Complete one phase.
4. Update tests.
5. Update Engineering_Guide.md and CHANGELOG.md.
6. Produce drop-in ZIP (changed files only).
7. Run:

```powershell
Get-ChildItem -Path . -Recurse -File | Unblock-File
Remove-Module Infrastructure.ActiveDirectory,Core.ProviderBase,ActiveDirectory,Hybrid.Models -Force -ErrorAction SilentlyContinue
.\tests\Test-MilestoneX.ps1
```
