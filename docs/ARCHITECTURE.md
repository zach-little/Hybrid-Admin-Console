# Hybrid Administration Platform Architecture

Hybrid Administration Platform is profile-driven, provider-agnostic, and plugin-native.

## Layers

- `src/Core` contains the framework primitives: paths, logging, configuration, module loading, service registry, plugins, cache, theme, security, and environment.
- `src/Domain` contains common models used across the product.
- `src/Application` contains orchestration and service access helpers.
- `src/Infrastructure` contains technology-specific providers such as mock, Active Directory, Entra ID, Exchange, Intune, Azure, VMware, DNS, and DHCP.
- `src/UI` contains presentation only.
- `src/Plugins` contains optional extension modules.
- `profiles` contains deployment-specific configuration. Atlas is a profile, not core logic.

## Dependency Rule

Modules do not import each other directly. The bootstrap imports modules in a deterministic order. Shared capabilities are exposed through the host context and service registry.

## Current Milestone

Milestone 1 delivers the core framework and a mock provider. It intentionally does not migrate enterprise business logic yet.
