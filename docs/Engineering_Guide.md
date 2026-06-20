# Engineering Guide

## Version 0.5 Cloud Foundation Notes

Milestone 5 introduces the shared cloud foundation used by future Microsoft Graph, Exchange Online, Intune, Azure, and licensing providers.

### Phase 1: Cloud Environment Abstraction

`Core.CloudEnvironment` owns sovereign cloud endpoint resolution. Providers should not hard-code Graph, login, portal, or management URLs. They should resolve endpoints from the registered cloud environment instead.

Built-in environments include:

- Commercial
- GCC High
- DoD

Aliases are supported so environment names can be friendly while still resolving to the same environment object.

### Phase 2: Tenant and Organization Context

`Core.TenantContext` represents tenant identity metadata only. It does not authenticate, call Graph, perform discovery, or validate live connectivity.

Tenant context contains:

- Tenant ID
- Tenant name
- Cloud environment
- Verified domains
- Default domain
- Optional attributes

`Core.OrganizationContext` represents the current organization runtime context. It is the application-level context object that future providers and UI pages can consume instead of each feature building its own isolated state.

Organization context contains:

- Organization name
- Tenant context
- Branding metadata
- Registered providers
- Registered capabilities
- Authentication state placeholder
- Optional attributes

The organization context intentionally includes an authentication state placeholder, but Phase 2 does not implement authentication. Authentication begins in a later Milestone 5 phase.

### Design Rules

- Cloud environments define endpoints.
- Tenant context identifies the tenant and selected cloud.
- Organization context identifies the current organization runtime.
- Providers consume these contexts; they do not own them.
- Authentication is not allowed inside tenant or organization context constructors.
- Device Code Flow remains unsupported by project charter.

### Phase 3: Authentication Framework Shell

`Core.Authentication` introduces the shared authentication framework contracts used by future Microsoft Graph, Exchange Online, Intune, Azure, and licensing providers.

Phase 3 does not perform live authentication and does not call Microsoft Graph. It defines the platform-owned authentication surface that future implementation phases will fill in.

Authentication framework objects include:

- `Hybrid.AuthenticationPolicy`
- `Hybrid.AuthenticationMethod`
- `Hybrid.AuthenticationRequest`
- `Hybrid.AuthenticationSession`

Built-in authentication methods include:

- Interactive
- InteractiveBrowser
- AppOnlyClientCredentials
- ManagedIdentity

Device Code Flow remains intentionally unsupported and is rejected by both method registration and policy creation.

Authentication requests bind together:

- Tenant context
- Cloud environment
- Authentication method
- Client ID
- Scopes
- Sovereign authority URL

Authentication sessions are shell session objects. They can represent a mock or future live token session, but Phase 3 does not acquire tokens.

### Authentication Design Rules

- Authentication belongs to `Core.Authentication`.
- Providers must never prompt for credentials.
- Providers must never cache tokens.
- Providers must never construct authentication authorities directly.
- Authentication requests derive authority from Tenant Context and Cloud Environment.
- Device Code Flow is prohibited by the Project Charter.
- Live MSAL, WAM, browser, managed identity, and client credential flows are deferred to later Milestone 5 phases.
