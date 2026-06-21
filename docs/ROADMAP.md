# Hybrid Admin Console Roadmap

## Current Status

**Current Version:** 0.7.0-dev  
**Current Branch:** `feature/milestone7-service-layer`  
**Current Milestone:** Milestone 7 - Hybrid Service Layer  
**Current Phase:** Phase 5 - Microsoft Graph Vertical

## Milestone 7 - Hybrid Service Layer

| Phase | Description | Status |
| --- | --- | --- |
| Phase 1 | Service Layer Foundation | Complete |
| Phase 2 | Active Directory Vertical | Complete |
| Phase 3 | Entra ID Vertical | Complete |
| Phase 4 | Exchange Vertical | Complete / Stable Baseline |
| Phase 5 | Microsoft Graph Vertical | In Progress |
| Phase 6 | Authentication Vertical | Pending |
| Phase 7 | Aggregation and Orchestration | Pending |

## Phase 5 Goal

Expose Microsoft Graph user profile and authentication posture data through the same vertical-slice pattern used by the earlier Milestone 7 phases.

## Engineering Rules

- Previous milestone functionality must not regress.
- Each phase must include UI, service layer, provider or simulator data, infrastructure, tests, and documentation.
- Directory Simulator is the canonical simulated enterprise provider.
- Every new feature must be visible in the UI.
- Cumulative milestone tests must pass before the phase is considered stable.
