# Project Status

## Current Status

Milestone 1 2 and Milestone 3 are complete.

## Latest Validation

Run:

```powershell
Get-ChildItem -Path . -Recurse -File | Unblock-File
Remove-Module Application.UserService,Infrastructure.Mock,Hybrid.Models -Force -ErrorAction SilentlyContinue
.\tests\Test-Milestone3.ps1
```
