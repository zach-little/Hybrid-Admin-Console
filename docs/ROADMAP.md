# ROADMAP.md

# Hybrid Admin Console Roadmap

This roadmap represents the long-term engineering plan for the Hybrid Admin Console. The project is intentionally milestone-driven, with each milestone producing a stable, testable increment.

---

# Current Status

**Current Version:** 0.6.0

**Completed Milestones**

* ✅ Milestone 1 – Project Foundation
* ✅ Milestone 2 – Domain Models
* ✅ Milestone 3 – Active Directory Provider
* ✅ Milestone 4 – Provider Architecture
* ✅ Milestone 5 – Authentication Platform
* ✅ Milestone 6 – Microsoft 365 Platform Foundation

Current development has shifted from building infrastructure to delivering complete vertical slices through the application.

---

# Milestone 7 – First Vertical Slice

Objective:

Deliver the first end-to-end Hybrid Admin Console experience using the architecture established in Milestones 1–6.

## Phase 1 – Vertical Slice Foundation ✅

* Hybrid User Service
* Initial application service layer
* First WPF application shell
* Canonical `Hybrid.User` composition
* Mock provider integration
* End-to-end architecture validation

## Phase 2 – Live Active Directory

* Replace mock AD provider with live provider
* Search real Active Directory users
* Display live AD properties
* Provider health integration

## Phase 3 – Live Microsoft Graph

* Replace mock Graph provider
* Live Graph authentication
* Merge Entra ID properties
* License information
* Group membership foundation

## Phase 4 – Live Exchange Online

* Replace mock Exchange provider
* Live mailbox lookup
* Mailbox status
* Recipient information
* Exchange health

## Phase 5 – Unified Search Experience

* Multi-result search
* Duplicate resolution
* Loading overlay
* Provider status indicators
* Search performance improvements
* Intelligent caching

## Phase 6 – User Overview

Single Hybrid.User dashboard displaying:

* Active Directory
* Microsoft Graph
* Exchange Online

within one unified interface.

Deliverable:

A usable application capable of searching production users through the complete platform.

---

# Milestone 8 – User Management

Focus shifts from viewing users to managing them.

Planned features include:

* Enable / Disable
* Unlock Account
* Password Reset
* Group Membership
* Move Subordinates
* Change Manager
* Exchange Mailbox
* Mailbox Delegation
* Distribution Groups
* Licensing
* Device Overview

---

# Milestone 9 – Device Management

* Intune Provider
* Device search
* Primary user
* Compliance
* BitLocker
* Sync
* Remote actions
* Autopilot integration

---

# Milestone 10 – Administration

Administrative capabilities.

Examples:

* Azure AD Connect
* Domain Controller Sync
* Health Dashboard
* Authentication Diagnostics
* Provider Diagnostics
* Logging
* Debug Console

---

# Milestone 11 – Reporting

* Reporting engine
* Export framework
* Audit reporting
* License reporting
* Device reporting
* Scheduled reports

---

# Milestone 12 – UI Customization

* UI Theme via profile - set colors
* New User Wizard - Customized flow via organization profile

---

# Milestone 13 – Production Release

Focus areas:

* Performance
* UI polish
* Accessibility
* Documentation
* Installer
* Configuration wizard
* Upgrade support
* Release candidate testing

---

# Engineering Principles

Throughout all milestones the following rules remain constant:

* UI never communicates directly with providers.
* Providers never authenticate directly.
* Authentication is owned by the Authentication Manager.
* Application Services aggregate provider data.
* Canonical Hybrid models are returned to the UI.
* Every phase must be independently testable.
* Every milestone must conclude with a stable, merge-ready branch.
* New functionality is delivered as complete vertical slices whenever practical.

---

# Long-Term Vision

The Hybrid Admin Console should become a unified administration platform capable of presenting and managing resources from multiple Microsoft services through a single consistent interface while maintaining clear architectural boundaries between the UI, service layer, provider layer, and authentication platform.
