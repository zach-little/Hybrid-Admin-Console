# Hybrid Administration Platform (HAP)

## Engineering Workflow

### Development Hierarchy
Version → Milestone → Phase. Every phase must leave the repository buildable and testable.

### Branch Strategy
- Develop on feature branches.
- Merge only after tests pass and required documentation is updated.

### Phase Deliverables
1. Source code
2. Automated tests
3. Documentation (`Engineering_Guide.md`, `CHANGELOG.md`)
4. Drop-in ZIP containing only changed files
5. `MANIFEST.txt`
6. Validation commands

### Validation
```powershell
Get-ChildItem -Path . -Recurse -File | Unblock-File

Remove-Module Infrastructure.ActiveDirectory,Core.ProviderBase,ActiveDirectory,Hybrid.Models -Force -ErrorAction SilentlyContinue

.\tests\Test-MilestoneX.ps1
```

### Documentation Cadence
Every phase:
- Engineering_Guide.md
- CHANGELOG.md

End of Version only:
- PROJECT_STATUS.md
- ROADMAP.md
- VERSION.md

### Definition of Done
A phase is complete only when implementation, tests, documentation, drop-in ZIP, manifest and validation instructions have been produced.
