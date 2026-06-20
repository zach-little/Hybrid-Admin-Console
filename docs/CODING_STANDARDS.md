# Hybrid Administration Platform (HAP)

**Document**
Coding Standards

**Purpose**
Defines the engineering standards used throughout the Hybrid Administration Platform.

**Scope**
Applies to all production code, tests, workflows, plugins, and infrastructure providers.

---

# 1. General Standards

HAP is developed as production-quality enterprise software.

Every contribution should prioritize:

* Readability
* Maintainability
* Testability
* Reusability
* Consistency

Short-term convenience should never outweigh long-term architecture.

---

# 2. Repository Organization

Project structure follows architectural boundaries.

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

Files belong to the layer that owns the responsibility.

---

# 3. PowerShell Standards

Every module should begin with:

```powershell
Set-StrictMode -Version Latest
```

Modules should avoid global variables.

Module state belongs within module scope.

Functions should return objects rather than formatted text.

Errors should be terminating when execution cannot safely continue.

---

# 4. Naming Standards

Public functions use approved PowerShell verbs.

Examples:

```
Get-HybridUser
Search-HybridUser
Set-HybridPassword
New-HybridUser
```

Internal helper functions should remain private unless intentionally exported.

Variables, parameters, and property names should use PascalCase where appropriate and remain descriptive.

Avoid abbreviations unless universally understood.

---

# 5. Module Design

Each module has one responsibility.

Modules communicate through services and provider contracts rather than importing one another directly.

Bootstrap is responsible for module loading.

Circular dependencies are not permitted.

---

# 6. Dependency Injection

Application components obtain services through the Service Registry.

Modules should never instantiate provider implementations directly.

Dependencies should be resolved rather than constructed.

---

# 7. Provider Standards

Providers implement platform contracts.

Providers are responsible for:

* Communication with external systems
* Translation into Hybrid models
* Capability reporting
* Health reporting

Providers are not responsible for:

* UI
* Workflow orchestration
* Authentication policy
* Business logic

---

# 8. Authentication Standards

Authentication is implemented exclusively through the Authentication Service.

Providers must never:

* Prompt for credentials
* Instantiate authentication clients
* Cache tokens
* Select cloud endpoints

Providers consume authenticated sessions supplied by the platform.

Device Code Flow is prohibited.

---

# 9. Logging Standards

Operational events should be logged through the central logging framework.

Logging should be:

* Structured
* Actionable
* Consistent

Sensitive information must never be written to logs.

Authentication tokens, secrets, passwords, and secure strings must never be logged.

---

# 10. Error Handling

Errors should provide actionable information.

Exceptions should preserve the original failure whenever practical.

Provider-specific exceptions should be translated into Hybrid platform exceptions before leaving the provider layer.

---

# 11. Domain Models

Hybrid models are immutable representations of platform data once returned.

Provider-native objects must never be exposed outside provider implementations.

Model conversion occurs within providers.

---

# 12. Testing Requirements

Every exported command requires automated tests.

Tests should validate:

* Success paths
* Failure paths
* Edge cases
* Invalid parameters
* Provider contracts
* Model conversion
* Service registration

Existing tests must continue passing.

---

# 13. Documentation Requirements

Every exported function requires:

* Comment-based help
* Parameter documentation
* Examples where appropriate

Architectural changes require updates to the appropriate documentation before the milestone is considered complete.

---

# 14. Performance

Performance improvements should preserve readability.

Caching should be preferred over repeated external calls when appropriate.

Shared infrastructure should provide caching so providers do not implement duplicate cache logic.

---

# 15. Security

Security-sensitive operations should follow the principle of least privilege.

Secrets should never be embedded in source code.

Configuration should support secure secret storage.

Authentication methods must remain compatible with enterprise security requirements.

---

# 16. Git Workflow

The `main` branch must remain stable.

Development occurs on feature branches.

Every completed milestone should produce:

* Passing tests
* Updated documentation
* Updated version
* Updated changelog

Commits should represent complete, reviewable units of work.

---

# 17. Code Review Checklist

Before merging code, verify:

* Architecture remains consistent.
* No customer-specific logic exists.
* No duplicated functionality has been introduced.
* Shared infrastructure has been reused where appropriate.
* Provider abstraction is preserved.
* Tests have been added or updated.
* Documentation reflects implementation.
* Existing functionality remains unaffected.
* Public interfaces remain stable.

Every change should improve the platform rather than simply adding functionality.
