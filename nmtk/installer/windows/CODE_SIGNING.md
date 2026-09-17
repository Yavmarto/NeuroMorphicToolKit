# Windows Code Signing

This directory builds the standalone NeuroMorphicToolKit `.exe` installer for Windows. Release builds should be Authenticode-signed so Windows SmartScreen does not block the installer on end-user machines. Unsigned installers trigger a "Windows protected your PC" warning; Extended Validation (EV) certificates eliminate the warning immediately while Organization Validation (OV) certificates build reputation over time.

## Scripts

| Script | Purpose |
|--------|---------|
| `build-standalone.ps1` | Bundle Python + modules, build Flutter app, compile Inno Setup installer, conditionally sign |
| `sign-installer.ps1` | Reusable Authenticode signing helper with `-Check` and `-DryRun` modes |

## Certificate requirements

| Property | Requirement |
|----------|-------------|
| Type | OV (Organization Validation) or EV (Extended Validation) |
| Key usage EKU | `1.3.6.1.5.5.7.3.3` — Code Signing |
| Providers | DigiCert, Sectigo, GlobalSign, Certum |
| Format for CI | PKCS#12 / PFX (`.p12`) exported with password, then base64-encoded |

EV certificates use a hardware token (USB key) and cannot be used in a standard GitHub Actions runner — for CI you need a cloud HSM signing service (e.g. DigiCert KeyLocker, SSL.com eSigner) or an OV certificate.

## Local setup

### 1. Install Windows SDK

Download and install the [Windows SDK](https://developer.microsoft.com/windows/downloads/windows-sdk/) to get `signtool.exe`.

### 2. Import the signing certificate

```powershell
# Import a PFX certificate into the current user's Personal certificate store
$password = Read-Host "PFX password" -AsSecureString
Import-PfxCertificate -FilePath .\CodeSigning.p12 -CertStoreLocation Cert:\CurrentUser\My -Password $password
```

### 3. Find the certificate thumbprint

```powershell
Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.EnhancedKeyUsageList -match "Code Signing" } | Format-List Subject, Thumbprint
```

### 4. Sign the installer

```powershell
.\sign-installer.ps1 -InstallerPath .\NMTKSetup.exe -Thumbprint <YOUR_THUMBPRINT>
```

Or set the environment variable and let `build-standalone.ps1` sign automatically:

```powershell
$env:WINDOWS_SIGNING_THUMBPRINT = "<YOUR_THUMBPRINT>"
.\build-standalone.ps1
```

### 5. Dry run (verify command without executing)

```powershell
.\sign-installer.ps1 -InstallerPath .\NMTKSetup.exe -Thumbprint <YOUR_THUMBPRINT> -DryRun
```

### 6. Check prerequisites

```powershell
.\sign-installer.ps1 -Check
# With a thumbprint to also verify the certificate is present:
.\sign-installer.ps1 -Check -Thumbprint <YOUR_THUMBPRINT>
```

## CI/CD setup (GitHub Actions)

Configure these repository secrets for `.github/workflows/release-desktop.yml`:

| Secret | Description |
|--------|-------------|
| `WINDOWS_CERTIFICATE_P12` | Base64-encoded `.p12` / `.pfx` export |
| `WINDOWS_CERTIFICATE_PASSWORD` | Password for the `.p12` file |
| `WINDOWS_SIGNING_THUMBPRINT` | SHA-1 thumbprint of the imported certificate |

Encode a certificate for CI:

```powershell
# PowerShell
[Convert]::ToBase64String([IO.File]::ReadAllBytes(".\CodeSigning.p12")) | Set-Clipboard
```

```bash
# macOS / Linux
base64 -i CodeSigning.p12 | pbcopy
```

When secrets are absent, the release workflow still builds an unsigned installer and a SmartScreen warning will appear. When all signing secrets are present, the workflow imports the certificate into the runner's cert store, then `build-standalone.ps1` invokes `sign-installer.ps1` automatically.

## Verification

After signing, verify the Authenticode signature:

```powershell
Get-AuthenticodeSignature .\NMTKSetup.exe | Format-List
```

Expected output includes `Status: Valid` and `SignerCertificate` with your organization name.

## Pytest coverage

Cross-platform and Windows-specific tests live in `tests/test_windows_installer_signing.py`.
