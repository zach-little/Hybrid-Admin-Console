# Engineering Guide

## Version 0.5 Cloud Foundation Notes

Milestone 5 introduced the shared cloud foundation used by future Microsoft Graph, Exchange Online, Intune, Azure, and licensing providers.

Version 0.5 is now complete.

---

# Cloud Foundation Architecture

```text
Cloud Environment
        │
        ▼
Tenant Context
        │
        ▼
Organization Context
        │
        ▼
Authentication Framework
        │
        ▼
Authentication Sessions / Token Contracts
        │
        ▼
Shared HTTP Pipeline
        │
        ▼
Microsoft Graph Provider Foundation
```

Each layer owns a separate concern.

Providers should consume these layers rather than implementing duplicate infrastructure.

---

# Phase Summary

## Phase 5.1: Cloud Environment Abstraction

`Core.CloudEnvironment` owns sovereign cloud endpoint resolution.

Providers should not hard-code Graph, login, portal, or management URLs. They should resolve endpoints from the registered cloud environment instead.

Built-in environments include:

- Commercial
- GCC High
- DoD

Aliases are supported so environment names can be friendly while still resolving to the same environment object.

---

## Phase 5.2: Tenant and Organization Context

`Core.TenantContext` represents tenant identity metadata only.

It does not authenticate, call Graph, perform discovery, or validate live connectivity.

Tenant context contains:

- Tenant ID
- Tenant name
- Cloud environment
- Verified domains
- Default domain
- Optional attributes

`Core.OrganizationContext` represents the current organization runtime context.

Organization context contains:

- Organization name
- Tenant context
- Branding metadata
- Registered providers
- Registered capabilities
- Authentication state placeholder
- Optional attributes

The organization context intentionally includes an authentication state placeholder, but authentication is implemented separately.

---

## Phase 5.3: Authentication Framework

`Core.Authentication` defines the framework for authentication policies and authentication methods.

The authentication framework is responsible for:

- Authentication policies
- Allowed methods
- Default methods
- Required scopes
- Method registration
- Method discovery
- Method validation

Device Code Flow is intentionally rejected.

Authentication remains a platform service.

Providers must not acquire credentials directly.

---

## Phase 5.4: Session and Token Contracts

Phase 5.4 added the platform contracts that future authentication implementations and providers will consume.

Contracts include:

- Authentication requests
- Authentication sessions
- Token descriptors
- Authentication results
- Authentication cache keys
- Authentication cache entries
- Session state helpers

These contracts allow future providers to consume authenticated sessions without understanding how those sessions were acquired.

---

## Phase 5.5: Shared HTTP Pipeline

The shared HTTP pipeline provides reusable request and response infrastructure.

The pipeline owns:

- Request objects
- Response objects
- Standardized errors
- Retry policy contracts
- Retry execution
- Bearer token injection
- Correlation ID injection
- User-Agent injection
- Request headers
- Response diagnostics
- Pagination state
- Mock transport support

Providers should not call `Invoke-RestMethod` directly when the shared pipeline can be used.

---

## Phase 5.6: Microsoft Graph Foundation

The Microsoft Graph foundation introduced the first Microsoft cloud provider built on the Version 0.5 cloud platform.

Graph modules consume:

- Cloud environment endpoint resolution
- Tenant context
- Authentication sessions
- HTTP pipeline
- Retry policy
- Diagnostics

Initial Graph modules include:

- Graph Provider
- Graph Client
- Graph Users
- Graph Groups
- Graph Organization
- Graph Models

Phase 5.6 intentionally remains offline-testable.

It does not require Microsoft Graph, MSAL, live authentication, or internet access.

---

## Phase 5.6.1: Graph Infrastructure Completion

Phase 5.6.1 completed reusable Graph infrastructure before Version 0.5 finalization.

Added infrastructure includes:

- Graph endpoint builder
- Graph resource URI builder
- Graph OData query builder
- Graph error translator
- Graph request builders
- Graph diagnostics
- Graph batch request and response contracts

These utilities are intended to prevent future Graph, Exchange, Intune, Entra, and Azure modules from duplicating request construction, query construction, diagnostics, or error handling.

---

# Provider Lifecycle Pattern

Version 0.5 establishes a common provider lifecycle shared by Active Directory and Microsoft Graph.

Future providers should follow this pattern:

```text
Initialize Provider
        │
        ▼
Register Provider
        │
        ▼
Register Capabilities
        │
        ▼
Create Client
        │
        ▼
Create Requests
        │
        ▼
Invoke Shared Pipeline
        │
        ▼
Convert Native Models
        │
        ▼
Report Health and Diagnostics
```

Providers should:

- Report capabilities.
- Report health.
- Use shared authentication sessions.
- Use shared HTTP infrastructure where applicable.
- Translate native objects into Hybrid models.
- Avoid UI logic.
- Avoid direct credential prompts.
- Avoid duplicated platform infrastructure.

---

# Graph Provider Rules

Graph modules should:

- Resolve service roots through cloud environments.
- Use Graph endpoint builders for API URIs.
- Use Graph query builders for OData parameters.
- Use request builders for common resource requests.
- Use the shared HTTP pipeline.
- Use authentication sessions supplied by the platform.
- Convert Graph objects into Hybrid models.
- Return platform response and model objects.

Graph modules should not:

- Implement authentication directly.
- Hard-code sovereign cloud URLs.
- Manually concatenate OData query strings when the query builder can be used.
- Parse Graph error JSON directly when the error translator can be used.
- Bypass the shared HTTP pipeline.
- Return raw provider-native objects as final platform output.

---

# Development Process

Every phase produces:

- Changed source files
- Updated tests
- `Engineering_Guide.md`
- `CHANGELOG.md`
- `MANIFEST.txt`
- Drop-in ZIP containing changed files only

`Project_Status.md`, `ROADMAP.md`, and `VERSION.md` are updated only during the final phase of a version.

---

# Standard Validation Procedure

Use the standard validation procedure before considering a phase complete.

```powershell
Get-ChildItem -Path . -Recurse -File | Unblock-File

Remove-Module Infrastructure.ActiveDirectory,Core.ProviderBase,ActiveDirectory,Hybrid.Models,Core.CloudEnvironment,Core.TenantContext,Core.OrganizationContext,Core.Authentication,Core.HttpResponse,Core.HttpRetry,Core.HttpPipeline,Graph.Provider,Graph.Client,Graph.Models,Graph.Users,Graph.Groups,Graph.Organization,Graph.EndpointBuilder,Graph.Query,Graph.Error,Graph.Diagnostics,Graph.RequestBuilders,Graph.Batch -Force -ErrorAction SilentlyContinue

.\tests\Test-Milestone5.ps1
```

---

# Design Rules

- Cloud environments define endpoints.
- Tenant context identifies the tenant and selected cloud.
- Organization context identifies the current organization runtime.
- Providers consume these contexts; they do not own them.
- Authentication is not allowed inside tenant or organization context constructors.
- Authentication is a platform service.
- Providers consume authentication sessions; they do not acquire credentials.
- HTTP behavior belongs in the shared pipeline.
- Retry behavior belongs in retry policy infrastructure.
- Graph request construction belongs in Graph request builders.
- Graph OData construction belongs in the Graph query builder.
- Graph diagnostics should flow into provider health.
- Device Code Flow remains unsupported by project charter.
