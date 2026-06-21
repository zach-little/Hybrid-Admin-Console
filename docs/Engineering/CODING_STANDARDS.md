# Coding Standards

## Directory Simulator Standard

Mock data for the Hybrid Admin Console must be produced by the directory simulator when a feature requires realistic user, manager, group, mailbox, or provider data.

### Rules

- Do not add new hard-coded mock users directly inside UI scripts.
- Do not create impossible directory relationships.
  - A user must not be their own manager.
  - A user must not appear in their own direct reports.
  - Direct reports should be coherent with manager relationships.
- Mock data should be deterministic so repeat searches return stable records.
- Mock providers should expose the same service-facing operations as live providers wherever practical.
- UI code should consume application services and service-backed simulator providers, not simulator internals.
- Simulator data should look like a plausible enterprise directory: realistic names, departments, titles, groups, OU paths, mailbox properties, and Exchange relationships.

### Placement

Directory simulator code belongs under:

```text
src/Infrastructure/Mock/
```

Feature tests that validate simulator behavior belong under:

```text
tests/
```

### Purpose

The simulator is not disposable fake data. It is a development and test harness that allows vertical slices to be exercised without live Microsoft services while preserving realistic administrative behavior.
