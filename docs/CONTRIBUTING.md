# Contributing

## Rules

1. `main` should remain runnable.
2. Prefer small, reviewable commits.
3. Keep Atlas-specific logic in `profiles/Atlas` or Atlas plugins.
4. UI code must not call Active Directory, Graph, Exchange, or Azure directly.
5. Infrastructure providers must not know about WPF.
6. Public functions require comment-based help.
7. Use `Verb-HybridNoun` naming for exported functions.
8. Destructive actions must be explicit workflow operations.

## Test

Run:

```powershell
.	ests\Test-Milestone1.ps1
```
