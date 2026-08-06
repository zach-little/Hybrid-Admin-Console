# Microsoft Graph Capability Coverage

## Task 28 Disposition

| Capability | Current HAP Use | Native Surface | Permission Notes | Disposition |
| --- | --- | --- | --- | --- |
| Delegated authentication | Launch-time user sign-in for Graph profile/auth posture | OAuth/MSAL public client equivalent | `User.Read.All`, `Directory.Read.All`, auth/risk scopes as configured | NativeSupported |
| Application authentication | App-only read flow for profile/device/license data | OAuth client credentials equivalent | `.default` app permissions | NativeSupported |
| User search/profile | User search, mailboxless ADM profile lookups | Microsoft Graph users | Directory read permissions | NativeSupported |
| Authentication methods | MFA/auth posture card | Microsoft Graph authentication methods | Authentication method read permissions | NativeSupported |
| Sign-in/password/risk fields | Last sign-in, password changed, risk state | Microsoft Graph user/risk/signInActivity surfaces when licensed/permissioned | Audit/risk permissions may be tenant/license gated | NativeSupportedWithBehaviorChange |
| License display | Friendly license names | subscribedSkus plus assignedLicenses/licenseAssignmentStates | Directory read permissions | NativeSupported |
| PIM roles | Graph card role display | Role management/directory role APIs | Role management read permissions | NativeSupported |
| Devices/Intune | Device Management lookup | Directory devices and managedDevices where licensed | Device management read permissions | NativeSupportedWithBehaviorChange |
| Group membership | User memberships and Graph-managed groups | memberOf/transitiveMemberOf/group members | Directory read permissions | NativeSupported |
| Graph writes | Create/update/group/license/device/credential operations | Public Graph write APIs only | Non-production opt-in required | NativeSupportedWithGatedValidation |

## Native Scope for Tasks 29-33

- Task 29 implements session health, auth state, and deterministic error mapping without live secrets.
- Task 30 implements read DTO mapping without leaking SDK types.
- Task 31 exposes write capability results but keeps destructive live execution gated.
- Task 32 routes supported device reads/actions through Graph contracts.
- Task 33 retires legacy Graph only after gated live validation; until then, unsupported writes must return explicit errors.

## Validation Rules

- Unit tests use provider test doubles or deterministic in-memory data.
- Live reads require an explicit tenant profile and manual opt-in.
- Destructive writes require non-production target confirmation.
- No Graph PowerShell module or legacy worker may be used by native Graph.
