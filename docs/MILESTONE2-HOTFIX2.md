# Milestone 2 Hotfix 2

Fixes the Milestone 2 test assertions to use the canonical PowerShell Extended Type System path:

```powershell
$object.PSObject.TypeNames[0]
```

instead of the non-standard `.PSTypeNames` member. The application and model factories were already stamping type names correctly; the test was checking the wrong member.
