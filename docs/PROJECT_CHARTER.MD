Hybrid Administration Platform (HAP)
Mission

We are building a commercial-quality Hybrid Administration Platform in PowerShell.

The current customer profile is Atlas Technologies.

The architecture must be designed so Atlas is simply a profile, not hardcoded into the application.

The end goal is a product that can support multiple organizations through profiles and plugins.

Development Rules
Treat this as an enterprise software project.
No quick hacks.
Favor maintainability over short-term convenience.
Every module must have a single responsibility.
Every exported function must be documented.
Every module should be testable independently.
No UI code inside Infrastructure.
No Infrastructure code inside UI.
No module imports another module directly; only the bootstrap loads modules.
All services are obtained through the Service Registry.
All external systems (AD, Graph, Exchange, Intune, Azure, etc.) live in Infrastructure.
Everything logs through the central logging framework.
Use Set-StrictMode -Version Latest in all modules.
Follow approved naming conventions (Get-HybridUser, Write-HybridLog, etc.).
Architecture
src/
    Core/
    Domain/
    Application/
    Infrastructure/
    UI/
    Plugins/
    Workflows/

profiles/
    Atlas/
    Mock/

legacy/

tests/

docs/

assets/
Milestone Progress
✅ Milestone 1 Complete
Bootstrap
Module Loader
Configuration
Logging
Service Registry
Plugin Loader
Mock Provider
Shell
Framework Tests
✅ Milestone 2 Complete
Domain Models
Mock User Service
Search-HybridUser
Get-HybridUser
Initial User Service Tests

Hydration of Mailbox, Groups, Devices, and Licenses is deferred to the next enhancement.

Development Workflow
Git repository
main is always stable.
Work is done on feature branches.
Treat every response as if it were a pull request.
Prefer complete module replacements over partial snippets.
Generate production-quality code.
Long-Term Roadmap

Milestone 3:

Real class-based domain models
Full user hydration
User Overview cards
AD provider
Graph provider abstraction

Milestone 4:

Create User workflow
Disable User
Password Reset
Move User
Change Manager

Milestone 5:

Exchange
Intune
Azure
Devices
Licensing

Milestone 6:

WPF Shell
Navigation
Dashboard
Plugin host

Milestone 7:

ScreenConnect
JAMIS
Zammad
Bastion
Defender
VMware
DNS/DHCP
Current Status

Repository initialized.

Milestones 1 and 2 committed.

Next task is Milestone 3.