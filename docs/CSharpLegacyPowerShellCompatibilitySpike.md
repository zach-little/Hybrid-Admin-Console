# C# Migration Spike - Legacy PowerShell Compatibility

Status: analysis and compatibility testing only. This follows `Migration.MD` Task 3 and does not begin the .NET application rewrite.

## Objective

Test the existing HILOP PowerShell runtime under Windows PowerShell 5.1, PowerShell 7, nested in-process runspaces, and out-of-process worker-style execution. Document compatibility findings and recommend a temporary legacy hosting approach for the C# migration.

## Environment Observed

| Runtime | Result |
|---|---|
| `powershell.exe` | Present at `C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe` |
| Windows PowerShell version | 5.1.26100.8655, Desktop edition |
| `pwsh.exe` | Present at `C:\Program Files\PowerShell\7\pwsh.exe` |
| PowerShell 7 version | 7.4.18, Core edition |
| Repository root | `D:\Atlas` |

## Commands Exercised

The spike intentionally avoided live authentication prompts and live write operations.

- Read PowerShell engine versions from `powershell.exe` and `pwsh.exe`.
- Imported `Core.RuntimeProfile.psm1` and `Application.RuntimeProfileManager.psm1` in both engines.
- Enumerated runtime profiles and resolved the selected profile in both engines.
- Imported `Core.Runtime.psm1` and launched the `Simulation` runtime in both engines.
- Checked module availability for `ActiveDirectory`, `ExchangeOnlineManagement`, `Microsoft.Graph.Authentication`, `Microsoft.Graph.Users`, and `MSAL.PS`.
- Imported HILOP auth, Graph, Exchange Online, and Exchange On-Premises provider modules in both engines.
- Created Exchange Online deferred provider health with intentionally empty app-only configuration in both engines.
- Created nested runspaces inside both engines and repeated runtime profile enumeration.
- Created nested runspaces inside both engines and repeated simulation runtime initialization.

## Compatibility Matrix

| Area | Windows PowerShell 5.1 Out-of-Process | PowerShell 7 Out-of-Process | Windows PowerShell 5.1 Nested Runspace | PowerShell 7 Nested Runspace | Finding |
|---|---|---|---|---|---|
| Engine availability | Pass | Pass | Pass | Pass | Both engines are installed and callable. |
| Runtime profile module import | Pass | Pass | Pass | Pass | `Core.RuntimeProfile` and `Application.RuntimeProfileManager` import cleanly. |
| Runtime profile enumeration | Pass | Pass | Pass | Pass | Both engines returned 2 profiles, first profile `Simulation`, and a valid selection. |
| Simulation runtime initialization | Pass with warnings | Pass with warnings | Pass with warnings | Pass with warnings | Both engines registered `DirectorySimulator`, `ActiveDirectory`, `MicrosoftGraph`, `ExchangeOnline`, and `ExchangeOnPremises`; diagnostics reported `Warning` with no errors. |
| HILOP auth/provider module imports | Pass | Pass | Not separately tested | Not separately tested | Auth, MSAL, tenant, Graph provider, Exchange Online provider, and Exchange On-Premises provider modules import in both engines. |
| Active Directory module availability | Available | Available | Not separately tested | Not separately tested | AD module is visible to both engines at the Windows PowerShell module path. |
| Active Directory runtime readiness | Unavailable in current environment | Unavailable in current environment | Not separately tested | Not separately tested | Import succeeds, but runtime readiness reports unavailable because no default ADWS server is reachable. |
| Microsoft Graph PowerShell modules | Available | Not available | Not separately tested | Not separately tested | `Microsoft.Graph.Authentication` and `Microsoft.Graph.Users` are installed for Windows PowerShell profile/module path, not visible to PowerShell 7 in this environment. |
| ExchangeOnlineManagement module | Not available | Not available | Not separately tested | Not separately tested | Both engines report missing ExchangeOnlineManagement. |
| `MSAL.PS` module | Not available | Not available | Not separately tested | Not separately tested | HILOP's current MSAL module has internal HTTP/contract logic, but external `MSAL.PS` is not present. |
| Exchange Online deferred provider health | Pass with stream noise | Pass with stream noise | Not separately tested | Not separately tested | Returns structured `NotConfigured` health, but emits strict-mode property errors after JSON when given an empty config object. Worker protocol must capture streams separately. |
| Interactive Graph delegated auth | Not live-tested | Not live-tested | Not live-tested | Not live-tested | Requires a controlled interactive test because it opens browser/loopback auth and can prompt MFA. |
| Exchange On-Premises live remoting | Not live-tested | Not live-tested | Not live-tested | Not live-tested | Should be treated as high risk until tested against a real endpoint with timeout/cancellation. |
| Object serialization | Partial pass | Partial pass | Partial pass | Partial pass | Simple DTO projections serialize to JSON. Raw provider services contain scriptblocks and must not cross process boundaries. |
| Cancellation and timeout | Not implemented in current scripts | Not implemented in current scripts | Not implemented in current scripts | Not implemented in current scripts | Must be enforced by the worker host, not assumed from legacy modules. |

## Provider-Specific Findings

### Directory Simulator

The simulator is the safest first bridge target. It works in Windows PowerShell 5.1 and PowerShell 7, both out-of-process and nested-runspace approximations. It registers the expected logical providers and returns structured runtime diagnostics.

### Active Directory

The `ActiveDirectory` module is installed and visible to both engines. HILOP's AD provider module imports, but live readiness is unavailable in the current test context with this warning:

`Unable to find a default server with Active Directory Web Services running.`

This is an environmental connectivity/readiness issue, not a parser/import issue. AD live tests should remain explicit, read-only, and time-bounded.

### Microsoft Graph

HILOP Graph-related modules import in both engines. Microsoft Graph PowerShell SDK modules are installed only where Windows PowerShell can see them in this environment. HILOP's current Graph provider uses internal HTTP/MSAL-style functions as well as shared auth modules, so module import compatibility is better than Graph SDK availability alone suggests.

Delegated interactive auth was not live-tested because it can launch a browser and MFA prompt. The existing code has loopback-browser behavior and launch-time delegated auth requirements, so the legacy worker needs an explicit host-interaction policy before this is automated.

### Exchange Online

`ExchangeOnlineManagement` is not installed for either engine in the tested environment. HILOP's Exchange Online provider module imports and can return structured `NotConfigured` health when deferred, but the test surfaced extra strict-mode errors after the JSON result when configuration is empty.

Implication: the worker protocol must never parse all human output as data. It needs an operation envelope, correlation ID, a data channel, warnings, errors, and captured stream diagnostics.

### Exchange On-Premises

The HILOP Exchange On-Premises provider module imports in both engines. Live remoting was not tested. Because on-prem Exchange often depends on remote PowerShell behavior, authentication mode, endpoint policy, and older module assumptions, this provider should be treated as a strong reason to prefer an out-of-process legacy worker.

## In-Process vs Out-of-Process Assessment

In-process runspaces are viable for simple profile and simulator commands based on the nested-runspace tests. They are not recommended as the default migration host because:

- Graph delegated auth can open browser/loopback prompts and must be serialized with WPF.
- Exchange Online and Exchange On-Premises can bring module/assembly/session conflicts.
- Raw provider services include scriptblocks and mutable module state.
- Failed or hung remote sessions are harder to cleanly isolate.
- The C# app must not inherit PowerShell module path or assembly side effects.

Out-of-process hosting is slightly slower but gives better containment:

- Separate engine selection per operation or profile.
- Hard timeout and process kill for hangs.
- Separate stdout/stderr/progress streams.
- Process recycle to clear script-global state.
- Safer handling of Exchange and delegated auth failures.

## Recommendation

Use an out-of-process temporary legacy worker as the default migration host.

Start with PowerShell 7 for simulator/profile/read-only bridge commands where it works. Keep Windows PowerShell 5.1 available as a temporary compatibility engine for providers that require desktop PowerShell modules or can only see installed modules there, especially Active Directory and potentially existing Graph SDK installations.

Do not use in-process hosting for live Graph delegated auth, Exchange Online, or Exchange On-Premises unless a later targeted spike proves those paths are safe with timeout, cancellation, stream capture, and repeat launch/reset behavior.

## Initial Worker Policy

The first worker proof of concept should:

- Start a fresh `pwsh.exe` process for `Get-HapRuntimeProfiles`.
- Use JSON request/response envelopes.
- Include correlation ID, operation name, timeout, success state, warnings, errors, and data.
- Treat stderr, warning, verbose, information, and progress streams as diagnostics, not data.
- Never import `Start-HybridAdminConsole.ps1`.
- Never return raw PSObjects or scriptblock-bearing provider service objects.
- Project all results into DTO-safe objects before serialization.
- Support process termination on timeout.

## Follow-Up Compatibility Tests Before Live Cutover

- Live AD read-only readiness against a known domain controller.
- Live Graph app-only token acquisition with certificate thumbprint and certificate path.
- Live Graph delegated auth with explicit prompt ownership, timeout, cancellation, and exactly-one-prompt validation.
- ExchangeOnlineManagement installed in both engines, then deferred and connected provider checks.
- Exchange On-Premises remote session connection with timeout and cleanup.
- Repeated start/stop/reset cycles to detect leaked module state.
- Serialization checks for all planned bridge DTOs.
- Cancellation test that kills a hung provider command without freezing WPF.

## Decision

Proceed to Task 4 only after accepting this hosting direction:

- Temporary first-party compatibility: out-of-process legacy worker.
- Default early engine: PowerShell 7 for profile/simulator commands.
- Compatibility fallback engine: Windows PowerShell 5.1 only when explicitly selected by the worker for legacy first-party provider compatibility.
- Permanent customer extension host: separate protocol and separate host, not the legacy worker.
