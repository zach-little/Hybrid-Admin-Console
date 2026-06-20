# Hybrid Administration Platform Roadmap

## Vision

Hybrid Administration Platform (HAP) is a modular PowerShell application designed to simplify administration of hybrid Microsoft environments.

The platform is:

* Enterprise-first
* Profile-driven
* Provider-agnostic
* Plugin-native
* Offline developable
* Commercially extensible

Atlas Technologies serves as the initial deployment profile and reference implementation. Long-term, the platform will support multiple organizations through configuration profiles without requiring code changes.

---

## Development Philosophy

Every feature must satisfy the following principles:

* Enterprise quality over rapid implementation
* Separation of concerns
* Strong typing where practical
* Testability
* Extensibility
* Documentation-first
* Provider abstraction
* UI independence
* Performance through caching
* Safe by default

---

## Current Progress

### Version 0.4.0

Status: Released

Completed:

* Core framework
* Domain foundation
* Hybrid User Engine
* Active Directory Provider
* Shared provider base
* Provider lifecycle
* Provider health
* Capability discovery

---

## Milestone 1 - Core Framework

Status: Complete

Completed:

* Bootstrap
* Module Loader
* Configuration Manager
* Logging Framework
* Service Registry
* Plugin Loader
* Mock Provider
* Shell Host
* Framework Test Harness

---

## Milestone 2 - Domain Foundation

Status: Complete

Completed:

* Domain Models
* User Service
* Mock Directory Provider
* Search-HybridUser
* Get-HybridUser
* Initial Unit Tests

---

## Milestone 3 - Hybrid User Engine

Status: Complete

Objective:

Create the canonical HybridUser object used throughout the platform.

Completed:

* Strong domain models
* User hydration
* Mailbox hydration
* Group hydration
* Device hydration
* License hydration
* Manager hydration
* Direct Reports hydration
* Cache integration
* Unit tests

Result:

Every UI component consumes one HybridUser object.

---

## Milestone 4 - Active Directory Provider

Status: Complete

Objective:

Extract Active Directory functionality from the legacy application into a provider-driven infrastructure module.

Completed:

* Search
* User retrieval
* Groups
* Manager
* Direct Reports
* Password Reset
* Enable / Disable
* Unlock
* OU operations
* Group add / remove
* Manager update
* Provider registration
* Shared provider base
* Provider lifecycle
* Provider health
* Capability discovery
* Command wrapper
* Cache integration
* Structured errors
* NoNet support
* Provider contract tests

Result:

Active Directory is now represented by a provider that follows the shared platform provider contract.

---

## Milestone 5 - Microsoft Graph Provider

Status: Next

Objective:

Create a Microsoft Graph provider for Entra ID and Graph-backed identity data.

Deliverables:

* Provider skeleton using shared provider base
* GCC High endpoint support
* App-only authentication
* Delegated authentication
* Delegated PIM-compatible role access
* User properties
* Authentication methods
* Azure roles
* Conditional Access information
* Devices
* Sign-in information
* Risk information
* Provider health
* Capability discovery
* Unit tests

---

## Milestone 6 - Exchange Provider

Deliverables:

* Mailboxes
* Delegation
* Shared Mailboxes
* Distribution Groups
* Mail Contacts
* Forwarders
* Send As
* Send on Behalf
* Full Access

---

## Milestone 7 - Intune Provider

Deliverables:

* Devices
* Compliance
* Primary User
* BitLocker
* Autopilot
* Device Actions

---

## Milestone 8 - Workflow Engine

Deliverables:

* Create User
* Disable User
* Move User
* Change Manager
* Password Reset
* Azure AD Sync
* Sync All DCs
* Employee Transfers
* Offboarding

---

## Milestone 9 - Modern UI

Deliverables:

* Dashboard
* Navigation
* Dynamic Cards
* Search
* Notifications
* Theme Engine
* Command Palette
* Debug Console

---

## Milestone 10 - Atlas Feature Migration

Goal:

Retire the legacy application.

Includes:

* User Overview
* Azure Cards
* Exchange Cards
* Group Management
* Azure AD Roles
* Mailbox Delegation
* Utilities
* Azure Sync
* DC Sync
* Search Experience

---

## Milestone 11 - Plugin SDK

Deliverables:

* Plugin API
* Dynamic Menu Registration
* Command Registration
* Dependency Injection
* Plugin Discovery
* Plugin Lifecycle
* SDK Documentation

Initial Plugins:

* ScreenConnect
* JAMIS
* Zammad
* Bastion
* Defender
* VMware
* DNS
* DHCP

---

## Milestone 12 - Productization

Deliverables:

* Installer
* Automatic Updates
* Configuration Wizard
* Profile Manager
* Branding Engine
* Documentation Generator
* Code Signing
* Release Pipeline

---

## Version Targets

| Version | Target                              |
| ------- | ----------------------------------- |
| 0.2     | Core Framework                      |
| 0.3     | Hybrid User Engine                  |
| 0.4     | Infrastructure Provider Foundation  |
| 0.5     | Graph / Exchange / Intune Providers |
| 0.6     | Workflow Engine                     |
| 0.7     | Modern UI                           |
| 0.8     | Plugin SDK                          |
| 0.9     | Beta                                |
| 1.0     | Production Release                  |

---

## Success Criteria

Version 1.0 is ready when:

* No dependency on the legacy application remains.
* All functionality is provider-driven.
* The UI consumes only application services.
* Every module is independently testable.
* The application supports multiple customer profiles.
* New functionality can be added through plugins without modifying the core framework.
* The platform can be deployed to a new organization by creating a profile rather than changing source code.
