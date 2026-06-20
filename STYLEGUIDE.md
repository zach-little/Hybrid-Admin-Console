# Style Guide

- Use `Set-StrictMode -Version Latest` in modules.
- Use `$script:State` for module-local state.
- Use structured logging through `Write-HybridLog`.
- Return domain models where possible.
- Avoid hardcoded tenant, domain, path, or customer-specific values in core modules.
