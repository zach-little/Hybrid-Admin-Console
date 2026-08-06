# Native Packaging and Diagnostics

## Task 59 Packaging Policy

- Core HAP publishes from `src-dotnet/src/HAP.App/HAP.App.csproj`.
- The initial package is framework-dependent for `win-x64`.
- The production package must include native built-in providers and must not include the deleted legacy worker, bridge, protocol, or adapter.
- The permanent `HAP.PowerShellPluginHost` remains optional and separately policy-controlled for administrator-approved third-party providers.

## Publish Profile

Use:

```powershell
dotnet publish .\src\HAP.App\HAP.App.csproj -p:PublishProfile=NativeFrameworkDependent
```

Expected output:

```text
src\HAP.App\bin\Release\net10.0-windows\publish\native-framework-dependent\
```

## Diagnostics

`SupportBundleService` produces a redacted JSON support bundle containing:

- Product version.
- Non-sensitive configuration values.
- Recent events.
- Capability dispositions.

The bundle redacts values whose keys or event text indicate secrets, passwords, tokens, certificate values, thumbprints, or client secrets.

## Signing Hooks

No private signing material is stored in the repository. Release signing should run as an external pipeline step after publish output validation.
