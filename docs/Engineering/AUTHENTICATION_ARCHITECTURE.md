# Authentication Architecture

Authentication is a platform concern. Providers request sessions from the Authentication Manager; they never authenticate directly.

Flow:
UI -> Service Layer -> Authentication Manager -> Adapter -> Authentication Session -> Microsoft APIs

Runtime profiles may include a `Authentication` block for cloud providers. App-only authentication is the default posture for Microsoft Graph and Exchange Online read operations that support application permissions. Delegated interactive authentication is reserved for capabilities that require a user context, such as future PIM role visibility or delegated-only licensing views.

Supported cloud values are `Commercial`, `GCCHigh`, and `DoD`. Certificate app-only authentication is preferred. Client secret compatibility is represented only by a `SecretReference`; plaintext secrets must not be stored in profile JSON.

Example profile shape:

```json
"Authentication": {
  "Cloud": "Commercial",
  "AppOnly": {
    "Enabled": true,
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
