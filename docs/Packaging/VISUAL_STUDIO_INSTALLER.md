# HILOP Visual Studio Signing and Installer

This guide keeps signing secrets local while making Visual Studio publish output predictable for installer creation.

## 1. Certificate

Use an Authenticode code-signing certificate issued to Little Innovation Tech. Do not commit `.pfx`, `.pvk`, passwords, or private keys.

Supported local signing inputs:

- Certificate installed in the Windows certificate store, referenced by thumbprint.
- Local `.pfx`, referenced by path and password through user secrets, environment variables, or Visual Studio publish properties.

## 2. Publish Signed Payload

In Visual Studio:

1. Open `src-dotnet\HILOP.sln`.
2. Right-click `HILOP.App`.
3. Select `Publish`.
4. Choose the `InstallerRelease` profile.
5. For an unsigned payload, publish as-is.
6. For a signed payload, add these MSBuild properties to the publish command or profile on your machine:

```powershell
/p:HilopEnableCodeSigning=true
/p:HilopSigningCertificateThumbprint=YOUR_CERT_THUMBPRINT
```

Alternative `.pfx` signing:

```powershell
/p:HilopEnableCodeSigning=true
/p:HilopSigningCertificatePath=C:\Secure\HILOP-CodeSigning.pfx
/p:HilopSigningCertificatePassword=YOUR_LOCAL_PASSWORD
```

The publish output is staged at:

```text
artifacts\publish\HILOP\
```

## 3. Create Installer In Visual Studio

Recommended Visual Studio path:

1. Install the `Microsoft Visual Studio Installer Projects` extension.
2. Add a new `Setup Project` to `src-dotnet\HILOP.sln`.
3. Name it `HILOP.Setup`.
4. In the setup project, add `Project Output` from `HILOP.App`, or add the published files from `artifacts\publish\HILOP`.
5. Set installer metadata:
   - Product Name: `HILOP`
   - Manufacturer: `Little Innovation Tech`
   - Default Location: `[ProgramFilesFolder]\Little Innovation Tech\HILOP`
   - Remove Previous Versions: `True`
   - Install All Users: `True`
6. Add a shortcut to `HILOP.App.exe` in the user Programs menu.
7. Build the setup project in `Release`.

## 4. Sign Installer

Sign the generated `.msi` or `.exe` with the same certificate:

```powershell
signtool sign /fd SHA256 /td SHA256 /tr http://timestamp.digicert.com /sha1 YOUR_CERT_THUMBPRINT .\HILOP.Setup.msi
```

## 5. Verify Signatures

```powershell
signtool verify /pa /v .\HILOP.App.exe
signtool verify /pa /v .\HILOP.Setup.msi
```

## Notes

- The repo includes signing hooks, but signing is disabled by default.
- Visual Studio can pass the signing properties through Publish.
- Keep installer output under `artifacts\`; that path is ignored by Git.
