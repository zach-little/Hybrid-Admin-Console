Current Milestone: 3 Complete

Completed
- Core Framework
- Configuration
- Logging
- Module Loader
- Plugin Loader
- Service Registry
- Mock Provider
- User Service
- Search-HybridUser
- Get-HybridUser

Milestone 3 - Domain Hydration
- Added canonical hydration metadata to Hybrid.User
- Added provider-agnostic Get-HybridUserOverview application API
- Added Hybrid.UserOverview and Hybrid.UserOverviewCard models
- Updated mock hydration to return hydrated copies without mutating stored mock user records
- Added Test-Milestone3.ps1 coverage for full hydration and overview composition

Current Branch
main

Next Work
- Promote domain models to formal PowerShell classes where it does not reduce PowerShell 5.1 compatibility
- Begin AD provider abstraction
- Begin Graph provider abstraction
