# Milestone 7 Phase 1

## First Vertical Slice Foundation

### Fix Note

The UI launcher resolves the repository root from `src/UI` and loads the application service from:

```text
src/Application/Application.HybridUserService.psm1
```

### Objective

Introduce the Hybrid User Service and a minimal WPF search shell so the project has a real application-facing path:

```text
UI
  ↓
Application Service
  ↓
Provider Services
  ↓
Hybrid.User
```
