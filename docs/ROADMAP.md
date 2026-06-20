Roadmap

Hybrid Administration Platform (HAP) is a modular PowerShell application designed to simplify administration of hybrid Microsoft environments.

The platform is:

Enterprise-first
Profile-driven
Provider-agnostic
Plugin-native
Offline developable
Commercially extensible

Atlas Technologies serves as the initial deployment profile and reference implementation. Long-term, the platform will support multiple organizations through configuration profiles without requiring code changes.

Development Philosophy

Every feature must satisfy the following principles:

Enterprise quality over rapid implementation
Separation of concerns
Strong typing where practical
Testability
Extensibility
Documentation-first
Provider abstraction
UI independence
Performance through caching
Safe by default
Current Progress
✅ Milestone 1 – Core Framework

Completed

Bootstrap
Module Loader
Configuration Manager
Logging Framework
Service Registry
Plugin Loader
Mock Provider
Shell Host
Framework Test Harness

Status:

Complete

✅ Milestone 2 – Domain Foundation

Completed

Domain Models
User Service
Mock Directory Provider
Search-HybridUser
Get-HybridUser
Initial Unit Tests

Deferred

User Hydration
Strong PowerShell Classes

Status:

Complete

Milestone 3 – Hybrid User Engine

Objective

Create the canonical HybridUser object used throughout the platform.

Deliverables

Strongly typed domain classes
User hydration
Mailbox hydration
Group hydration
Device hydration
License hydration
Manager hydration
Direct Reports hydration
Cache integration
Unit tests

Result

Every UI component consumes one HybridUser object.

Milestone 4 – Active Directory Provider

Objective

Extract all Active Directory functionality from the legacy application.

Deliverables

Search
User retrieval
Groups
Manager
Direct Reports
Password Reset
Enable/Disable
Unlock
OU operations
Milestone 5 – Microsoft Graph Provider

Objective

Provider abstraction for Entra ID.

Deliverables

User properties
Authentication Methods
Azure Roles
Conditional Access information
PIM support
Devices
Sign-in information
Risk information
Milestone 6 – Exchange Provider

Deliverables

Mailboxes
Delegation
Shared Mailboxes
Distribution Groups
Mail Contacts
Forwarders
Send As
Send on Behalf
Full Access
Milestone 7 – Intune Provider

Deliverables

Devices
Compliance
Primary User
BitLocker
Autopilot
Device Actions
Milestone 8 – Workflow Engine

Extract business workflows from the legacy application.

Deliverables

Create User
Disable User
Move User
Change Manager
Password Reset
Azure AD Sync
Sync All DCs
Employee Transfers
Offboarding
Milestone 9 – Modern UI

Replace the legacy UI with a modular shell.

Deliverables

Dashboard
Navigation
Dynamic Cards
Search
Notifications
Theme Engine
Command Palette
Debug Console
Milestone 10 – Atlas Feature Migration

Port all remaining Atlas functionality.

Includes

User Overview
Azure Cards
Exchange Cards
Group Management
Azure AD Roles
Mailbox Delegation
Utilities
Azure Sync
DC Sync
Search Experience

Goal

Legacy application retired.

Milestone 11 – Plugin SDK

Deliverables

Plugin API
Dynamic Menu Registration
Command Registration
Dependency Injection
Plugin Discovery
Plugin Lifecycle
SDK Documentation

Initial Plugins

ScreenConnect
JAMIS
Zammad
Bastion
Defender
VMware
DNS
DHCP
Milestone 12 – Productization

Deliverables

Installer
Automatic Updates
Configuration Wizard
Profile Manager
Branding Engine
Documentation Generator
Code Signing
Release Pipeline
Version Targets
Version 0.2

Core Framework

Status

Released

Version 0.3

Hybrid User Engine

Version 0.4

Infrastructure Providers

Version 0.5

Workflow Engine

Version 0.6

Modern UI

Version 0.7

Plugin SDK

Version 0.8

Atlas Migration Complete

Version 0.9

Beta

Version 1.0

Production Release

Long-Term Vision

The Hybrid Administration Platform should become a complete administration framework capable of managing hybrid Microsoft environments through modular providers and plugins.

Future provider targets include:

Active Directory
Entra ID
Exchange Online
Intune
Azure
VMware
Hyper-V
DNS
DHCP
SQL Server
LAPS
BitLocker
Defender
Azure Virtual Desktop
SharePoint
Teams
ScreenConnect
JAMIS
Zammad

The goal is to allow organizations to deploy the platform simply by creating a profile and enabling the providers and plugins relevant to their environment.

Success Criteria

The project will be considered Version 1.0 ready when:

No dependency on the legacy application remains.
All functionality is provider-driven.
The UI consumes only application services.
Every module is independently testable.
The application supports multiple customer profiles.
New functionality can be added through plugins without modifying the core framework.
The platform can be deployed to a new organization by creating a profile rather than changing source code.