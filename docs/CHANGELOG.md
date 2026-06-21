# Changelog

## Version 0.6.0 – Microsoft 365 Platform Foundation

### Added

#### Authentication Platform

* Added platform authentication manager.
* Added authentication session abstraction.
* Added authentication request model.
* Added authentication cache with session refresh support.
* Added authentication adapter registration framework.
* Added Interactive MSAL authentication adapter.
* Added App-only MSAL authentication adapter.
* Established provider-independent authentication contract.

#### Microsoft Graph Provider

* Added Microsoft Graph provider foundation.
* Added Microsoft Graph provider context.
* Added Microsoft Graph provider service abstraction.
* Added provider health reporting.
* Added Graph user search operation.
* Added Graph user retrieval operation.
* Added canonical `Hybrid.User` conversion pipeline.

#### Exchange Online Provider

* Added Exchange Online provider foundation.
* Added Exchange Online provider context.
* Added Exchange Online provider service abstraction.
* Added mailbox search operation.
* Added mailbox retrieval operation.
* Added provider health reporting.
* Integrated Exchange provider with the platform authentication manager.

### Changed

* Authentication is now fully centralized through the Authentication Manager.
* Providers no longer perform authentication directly.
* Microsoft 365 providers now consume platform authentication sessions.
* Standardized provider contracts across Active Directory, Microsoft Graph, and Exchange Online.
* Improved provider health reporting consistency.
* Standardized platform object type names.
* Improved session lifecycle management and cache behavior.

### Testing

Milestone 6 completed successfully.

Completed validation:

* Phase 1 – Authentication Manager
* Phase 2 – Live-capable MSAL Adapters
* Phase 3 – Microsoft Graph Provider Foundation
* Phase 4 – Exchange Online Provider Foundation

All milestone validation tests passed.
