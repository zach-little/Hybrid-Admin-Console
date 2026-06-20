# Plugin SDK

Milestone 1 establishes the plugin registry.

A future plugin should live under `src/Plugins/<PluginName>` and expose a `*.plugin.psm1` file.

Plugin modules register themselves using:

```powershell
Register-HybridPlugin -Name 'Example' -Version '0.1.0'
```

Plugin command, menu, and UI contracts will be expanded in a later milestone.
