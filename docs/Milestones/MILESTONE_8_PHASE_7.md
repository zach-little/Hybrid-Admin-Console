# Milestone 8 Phase 7 - Deployment and Packaging

## Status

Complete.

## Purpose

Phase 7 closes Milestone 8 by adding deployment layout validation and packaging support for the runtime platform.

Milestone 8 introduced runtime profiles, centralized bootstrap, provider modes, startup diagnostics, a startup shell, shell regions, and a runtime profile wizard. Phase 7 packages those foundations into an operational deployment workflow.

## Scope

Phase 7 adds:

- Deployment layout discovery.
- Runtime profile discovery.
- First-run profile validation.
- Deployment directory initialization.
- Deployment readiness validation.
- Portable package creation.
- Deployment validation and packaging tools.
- Deployment documentation.

## New Module

`src/Core/Core.Deployment.psm1`

Exports:

- `Get-HybridDeploymentLayout`
- `Get-HybridDeploymentRuntimeProfile`
- `Initialize-HybridDeployment`
- `Test-HybridDeploymentLayout`
- `New-HybridDeploymentPackage`

## Design Rules

- Deployment support is additive.
- No runtime bootstrap behavior is changed.
- No provider authentication is triggered during packaging.
- No Device Code authentication is introduced.
- No UI redesign is included in this phase.
- Simulation remains the default first-run and offline validation profile.
- Packaging does not include transient logs as deployment dependencies.

## Deployment Model

A valid deployment contains:

- `src`
- `profiles`
- `profiles/Runtime`
- `docs`
- `tools`
- `tests`
- `logs`
- `build`
- `src/UI/Start-HybridAdminConsole.ps1`
- at least one readable runtime profile
- `profiles/Runtime/Simulation.json`

## Tools

- `tools/Apply-Milestone8Phase7.ps1`
- `tools/Test-HybridDeployment.ps1`
- `tools/New-HybridAdminDeploymentPackage.ps1`

## Tests

`tests/Test-Milestone8Phase7.ps1`

The test validates:

- deployment module and manifest exist;
- expected exports are available;
- deployment layout resolves correctly;
- deployment directories are initialized;
- runtime profiles are discoverable;
- Simulation profile is available for first-run validation;
- Device Code authentication is not introduced in the UI entry point;
- deployment package creation succeeds;
- Phase 7 tools and documentation exist.

## Acceptance Criteria

- Phase 7 tests pass.
- Phase 6.1 through Phase 1 cumulative tests continue to pass.
- UI smoke test continues to launch the startup shell and console.
- Deployment package can be produced from the repository.

## Result

Milestone 8 is now ready for closeout documentation. HAP has a runtime platform that can be initialized, diagnosed, configured through profiles, launched through a startup shell, and packaged for deployment.
