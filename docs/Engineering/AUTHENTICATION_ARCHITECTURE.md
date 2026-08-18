# Authentication Architecture

Authentication is a platform concern. Providers request sessions from the Authentication Manager; they never authenticate directly.

Flow:
UI -> Service Layer -> Authentication Manager -> Adapter -> Authentication Session -> Microsoft APIs

Runtime profiles may include an `Authentication` block for cloud providers. Microsoft Graph uses delegated interactive authentication so every Graph operation executes in the signed-in technician's context. The application does not assign its own roles or use application-level RBAC; Microsoft Entra ID permissions, tenant consent, Conditional Access, PIM activation where applicable, and other tenant controls determine what the technician may do. Active Directory operations are similarly constrained by the technician's effective AD permissions.

HILOP does not elevate the technician or substitute an internal authorization decision for a provider's decision. A denied operation remains denied and is surfaced to the operator.

Supported cloud values are `Commercial`, `GCCHigh`, and `DoD`. Delegated interactive authentication is the Microsoft Graph posture. The `AppOnly` profile shape remains available for providers and compatibility paths that explicitly support it, but it does not replace delegated Graph authorization. Where app-only credentials are supported, certificate credentials are preferred; client secret compatibility is represented only by a `SecretReference`, and plaintext secrets must not be stored in profile JSON.

Example profile shape:

```json
"Authentication": {
  "Cloud": "Commercial",
  "AppOnly": {
    "Enabled": false,
    "TenantId": "",
    "ClientId": "",
    "CredentialMode": "Certificate",
    "CertificateThumbprint": "",
    "CertificatePath": "",
    "SecretReference": ""
  },
  "Delegated": {
    "Enabled": true,
    "ClientId": "",
    "PromptWhenRequired": true
  }
}
```

Device Code authentication remains prohibited.

## Approval Boundary

Authentication and authorization must not be confused with an application approval service. HILOP is a local workstation application with no network-aware approval coordinator. It may ask the current operator to confirm a high-impact action, but it does not route requests to other users, maintain shared approval queues, or wait for remote approval. Building a network layer for those capabilities is outside the product scope.
