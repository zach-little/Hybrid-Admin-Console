# Hybrid Identity Lifecycle & Operations Platform (HILOP)

**Document**
Architecture

**Purpose**
Defines the technical architecture of the Hybrid Identity Lifecycle & Operations Platform (HILOP) and the relationships between its major subsystems.

**Scope**
This document describes the architecture of the platform. Engineering philosophy is documented in **DESIGN_PRINCIPLES.md**.

---

# 1. Architectural Goals

The architecture of HILOP is designed to satisfy the following objectives:

* Provider independence
* Enterprise scalability
* Multi-organization support
* Multi-tenant support
* Multi-cloud support
* Testability
* Extensibility
* Maintainability
* Long-term evolution

The platform is designed as reusable infrastructure rather than a collection of administrative scripts.

## 1.1 Deployment and Authorization Boundary

HILOP is a local, single-operator desktop application. Each instance runs on a technician's workstation under that technician's operating-system and directory identity. It is not a server, shared web application, or network coordination service.

HILOP therefore does not implement application-level role-based access control (RBAC). Authorization is enforced by the systems being administered:

* Microsoft Graph requests use delegated access and are limited by the signed-in technician's Microsoft Entra ID permissions, tenant consent, Conditional Access, and other applicable Entra controls.
* Active Directory operations run with the technician's effective AD permissions.
* Other providers remain responsible for enforcing the identity and permissions supplied to them.

HILOP must not grant, simulate, or elevate permissions beyond those external controls. Authorization failures are reported to the operator rather than bypassed.

Centralized or multi-user approval workflows are also outside the product boundary. A local instance has no network awareness through which to discover approvers, route requests, or coordinate approval state. Local confirmations for destructive or high-impact actions remain appropriate safeguards, but they are not approval workflows.

Adding a server or peer-to-peer network layer solely to support RBAC or approvals is explicitly out of scope. Such a layer would change the product from a technician-operated local console into a network service and would require a separate architectural and product decision.

---

# 2. High-Level Architecture

```text
                 User Interface
                       │
                       ▼
              Application Services
                       │
                       ▼
                Domain Models
                       │
                       ▼
                Core Platform
                       │
                       ▼
          Infrastructure Providers
                       │
                       ▼
              External Systems
```

Each layer has a single responsibility.

Dependencies always flow downward.

---

# 3. Repository Structure

```text
src/

    Core/
    Domain/
    Application/
    Infrastructure/
    UI/
    Plugins/
    Workflows/

profiles/

tests/

docs/

assets/

legacy/
```

The repository is organized around architectural responsibilities rather than technologies.

---

# 4. Core Platform

The Core layer contains reusable platform infrastructure.

Examples include:

* Configuration
* Logging
* Authentication
* Service Registry
* Provider Registry
* Plugin Registry
* Caching
* Telemetry
* Health Monitoring
* Profile-scoped append-only auditing
* Module Loading
* Environment Detection

Core components never contain business logic.

---

# 5. Domain Layer

The Domain layer defines the canonical Hybrid models.

Examples include:

* HybridUser
* HybridGroup
* HybridDevice
* HybridMailbox
* HybridLicense

These models represent the platform's source of truth.

Provider-native objects never leave the provider layer.

---

# 6. Application Layer

Application Services coordinate business operations.

Responsibilities include:

* Service orchestration
* Workflow support
* Provider selection
* Business validation
* Object hydration
* Result aggregation

Application Services communicate only through provider contracts and domain models.

---

# 7. Infrastructure Layer

Infrastructure modules communicate with external technologies.

Examples include:

* Active Directory
* Microsoft Graph
* Exchange Online
* Intune
* Azure Resource Manager
* VMware
* ScreenConnect
* JAMIS
* Zammad

Infrastructure modules never expose provider-specific objects.

---

# 8. Provider Architecture

Every provider follows a common lifecycle.

```text
Application Service

        │

        ▼

Provider Contract

        │

        ▼

Provider Implementation

        │

        ▼

External System
```

Providers are responsible for:

* Authentication (through the Authentication Service)
* Data retrieval
* Data modification
* Native object translation
* Capability reporting
* Health reporting

Providers never communicate directly with other providers.

---

# 9. Authentication Architecture

Authentication is implemented as shared platform infrastructure.

```text
Provider

      │

      ▼

Authentication Manager

      │

      ▼

Authentication Provider

      │

      ▼

Microsoft Identity Platform
```

Authentication responsibilities include:

* Session acquisition
* Token caching
* Token refresh
* Cloud selection
* Tenant selection
* Authentication policy
* Permission management

Authentication implementations remain independent of provider implementations.

---

# 10. Organization and Tenant Architecture

Organizations and tenants are distinct concepts.

```text
Organization

    │

    ├── Tenant

    ├── Tenant

    ├── Tenant

    └── Tenant
```

Each Tenant defines:

* Cloud Environment
* Authentication Configuration
* Provider Configuration
* Service Endpoints
* Capabilities

Providers operate against Tenant Contexts rather than organizations.

---

# 11. Cloud Architecture

Cloud environments are abstracted from provider implementations.

Examples include:

* Commercial
* GCC
* GCC High
* DoD

Providers consume endpoint information supplied by the platform rather than embedding cloud-specific knowledge.

This allows a single organization to simultaneously manage multiple Microsoft cloud environments.

---

# 12. Service Registry

Application components communicate through registered services.

The bootstrap process is responsible for:

* Module loading
* Service registration
* Provider registration
* Plugin discovery

Modules never import one another directly.

---

# 13. Plugin Architecture

Plugins extend platform functionality without modifying the core platform.

Plugins may contribute:

* Providers
* Workflows
* Commands
* UI Components
* Services

Plugins communicate through established platform contracts.

---

# 14. Workflow Architecture

Workflows coordinate multiple services into complete administrative operations.

Examples include:

* User Creation
* Employee Transfer
* Offboarding
* Password Reset
* Azure Synchronization

Workflows compose existing services rather than duplicating provider logic.

---

# 15. Testing Architecture

Testing occurs at multiple layers.

Platform tests validate:

* Core infrastructure
* Provider contracts
* Application services
* Domain models
* Workflows
* Integration boundaries

Every milestone expands the automated test suite.

---

# 16. Future Evolution

The architecture is designed to grow through extension rather than replacement.

Future providers should integrate by implementing established contracts while automatically benefiting from shared platform infrastructure including authentication, configuration, logging, caching, telemetry, capability discovery, and workflow orchestration.
