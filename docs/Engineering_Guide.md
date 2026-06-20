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

### Phase 4: Session and Token Contracts

Phase 4 extends `Core.Authentication` with provider-facing token and session contracts. It still does not perform live authentication, call MSAL, or call Microsoft Graph.

New contract objects include:

- `Hybrid.TokenDescriptor`
- `Hybrid.AuthenticationResult`
- `Hybrid.AuthenticationCacheKey`
- `Hybrid.AuthenticationCacheEntry`

`Hybrid.TokenDescriptor` represents token metadata in a provider-neutral way. It can hold access token text, token type, expiration, scopes, claims, and optional attributes without exposing any Microsoft-specific authentication library object outside the authentication layer.

`Hybrid.AuthenticationResult` represents the result of an authentication attempt. Future live authentication implementations will return this object whether authentication succeeds or fails.

`Hybrid.AuthenticationSession` now accepts a token descriptor. Providers continue to consume the session object rather than token library output.

Session state is resolved through `Get-HybridAuthenticationSessionState`, which currently reports:

- `Valid`
- `RefreshRequired`
- `Expired`
- `Unauthenticated`
- `Invalid`

Cache key and cache entry objects define the future token/session cache contract. Phase 4 defines the shape only; it does not implement persistent token caching.

### Session Contract Design Rules

- Providers consume `Hybrid.AuthenticationSession`.
- Providers must not consume MSAL result objects directly.
- Tokens are represented by `Hybrid.TokenDescriptor`.
- Authentication success and failure are represented by `Hybrid.AuthenticationResult`.
- Cache contracts are platform-owned and provider-neutral.
- Persistent token cache implementation is deferred to a later phase.

### Phase 5: Shared HTTP Pipeline

Phase 5 introduces the reusable HTTP infrastructure that future Microsoft Graph, Exchange Online, Intune, Azure, and other cloud providers will consume.

The HTTP pipeline is intentionally provider-agnostic. It does not know about Graph resources, Exchange cmdlets, Intune devices, or Azure subscriptions. Providers construct requests and consume standardized responses while the platform handles shared request behavior.

New platform contracts include:

- `Hybrid.HttpRequest`
- `Hybrid.PreparedHttpRequest`
- `Hybrid.HttpResponse`
- `Hybrid.HttpError`
- `Hybrid.HttpRetryPolicy`
- `Hybrid.HttpPaginationState`
- `Hybrid.HttpPipeline`
- `Hybrid.HttpPipelineDiagnostic`

The pipeline owns:

- Header merging
- Bearer token injection
- Correlation ID generation
- User-Agent injection
- Retry policy execution
- Request timing
- Standardized error wrapping
- Mock transport execution for offline tests

Phase 5 still does not perform live Microsoft Graph calls and does not acquire tokens. It uses mock transports so the pipeline can be tested without network access, MSAL, Graph permissions, or tenant connectivity.

Providers should not call `Invoke-RestMethod` directly once they are implemented on the cloud foundation. Providers should create `Hybrid.HttpRequest` objects and execute them through `Invoke-HybridHttpPipeline`.

### Phase 5 Design Rules

- Providers do not inject authorization headers themselves.
- Providers do not implement retry logic.
- Providers do not implement paging contracts independently.
- Providers do not create HTTP error shapes directly.
- Cloud provider HTTP behavior belongs in the shared pipeline.
- Live transports are deferred until the Microsoft Graph foundation phase.

### Phase 6: Microsoft Graph Foundation

Phase 6 introduces the first cloud provider foundation built on the Version 0.5 platform services.

The Graph provider is intentionally thin. It consumes:

- `Core.CloudEnvironment` for sovereign Microsoft Graph endpoint resolution.
- `Core.TenantContext` for tenant identity and selected cloud.
- `Core.Authentication` for authentication session contracts.
- `Core.HttpPipeline` for request execution, headers, retry behavior, diagnostics, and token injection.

Graph modules introduced in this phase:

- `Graph.Client` creates cloud-aware Graph clients and Graph requests.
- `Graph.Provider` registers the Microsoft Graph provider and reports capabilities and health.
- `Graph.Users` provides initial user request wrappers.
- `Graph.Groups` provides initial group request wrappers.
- `Graph.Organization` provides the initial organization request wrapper.
- `Graph.Models` defines initial Graph-to-Hybrid conversion contracts.

Phase 6 remains offline-testable. It does not acquire tokens, load MSAL, call Microsoft Graph, or require internet access. All tests use mock HTTP transports through the shared HTTP pipeline.

#### Graph Provider Rules

- Graph modules must not authenticate directly.
- Graph modules must not call `Invoke-RestMethod` directly.
- Graph modules must not hard-code Microsoft cloud endpoints.
- Graph modules must consume the shared HTTP pipeline.
- Graph modules must return Hybrid platform objects or pipeline responses.
- Live Microsoft Graph behavior belongs in later phases and versions after the shared foundation is complete.

### Phase 5.6.1: Graph Infrastructure Completion

Phase 5.6.1 completes the reusable Microsoft Graph infrastructure before Version 0.5 finalization.

This phase expands the Graph foundation with reusable platform contracts instead of feature-specific Graph code.

Added infrastructure includes:

- `Graph.EndpointBuilder` for sovereign-aware Graph endpoint and resource URI construction.
- `Graph.Query` for OData query string generation.
- `Graph.Error` for translating Graph error payloads into platform error objects.
- `Graph.RequestBuilders` for reusable users, groups, and organization request builders.
- `Graph.Diagnostics` for request diagnostics and provider runtime state.
- `Graph.Batch` for future batch request and response contracts.
- Graph mapper infrastructure for consistent Graph-to-Hybrid model conversion.

Design rules:

- Graph modules should not concatenate URLs directly.
- OData query construction belongs in `Graph.Query`.
- Graph errors should be translated through `Graph.Error` before surfacing to higher layers.
- Provider health should expose runtime state including cloud, tenant, authentication state, API version, scopes, transport, last request, and diagnostics.
- Batch support is contract-only in Version 0.5; live batch execution belongs in a later version.
- Graph feature modules should prefer request builders over ad-hoc request construction.

Phase 5.6.1 remains offline-testable and does not introduce live Graph calls, MSAL usage, or token acquisition.
