# Project Status

## Current Milestone

Milestone 4 - Active Directory Provider

## Status

In Progress

## Recently Completed

- Milestone 1 - Core Framework
- Milestone 2 - Domain Foundation
- Milestone 3 - Hybrid User Engine

## Milestone 4 Scope

Objective: Extract Active Directory functionality from the legacy application into a provider-driven infrastructure module.

Initial implementation started:

- Active Directory provider module scaffold
- Offline-safe provider initialization
- RSAT/ActiveDirectory module availability detection
- AD user to Hybrid.User mapper
- Provider contract for search, user retrieval, groups, manager, direct reports, password reset, enable/disable, unlock, and OU move
- Milestone 4 foundation tests

## Next Milestone 4 Work

- Validate live AD search on a domain-joined workstation
- Expand group mapping accuracy once live AD data is available
- Add application-service wrappers for write actions
- Add workflow-safe result handling for AD writes
- Add guarded tests for live-provider scenarios
