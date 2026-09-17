# macOS Code Signing and Notarization

This directory builds the standalone NeuroMorphicToolKit `.app` bundle and optional DMG installer. Release builds should use a Developer ID certificate and Apple notarization so Gatekeeper accepts the installer on end-user Macs.

## Scripts

| Script | Purpose |
|--------|---------|
| `build-standalone.sh` | Bundle Python + modules, build Flutter app, sign, optionally create/notarize DMG |
| `sign-and-notarize.sh` | Reusable signing/notarization helper with `--check` and `--dry-run` modes |
| `import-signing-cert.sh` | Import a base64 `.p12` certificate into a CI keychain |
| `create-dmg.sh` | Package a signed `.app` into a DMG |

## Local release build (unsigned)

```bash
./nmtk/installer/macos/build-standalone.sh --dmg
```

This produces an ad-hoc signed bundle suitable for internal testing only.

## Signed + notarized release build

### 1. Create certificates (one-time)

1. Enroll in the [Apple Developer Program](https://developer.apple.com/programs/).
2. In Xcode or the Developer portal, create a **Developer ID Application** certificate.
3. Export the certificate + private key as a `.p12` file protected by a password.
4. Create an [app-specific password](https://appleid.apple.com/account/manage) for notarization.

### 2. Install the certificate locally

```bash
# Import the .p12 into your login keychain (Keychain Access also works)
security import DeveloperID.p12 -k ~/Library/Keychains/login.keychain-db -P "$P12_PASSWORD" -T /usr/bin/codesign

# Confirm the identity name codesign will use
security find-identity -v -p codesigning
```

Use the full identity string from the output, for example:

`Developer ID Application: Your Org (TEAMID1234)`

### 3. Export environment variables

```bash
export MACOS_SIGNING_IDENTITY='Developer ID Application: Your Org (TEAMID1234)'
export APPLE_ID='release@example.com'
export APPLE_APP_SPECIFIC_PASSWORD='xxxx-xxxx-xxxx-xxxx'
export APPLE_TEAM_ID='TEAMID1234'
export MACOS_NOTARIZE=true
```

Or use the Makefile wrapper:

```bash
make build-macos-dmg-signed
```

Check readiness without building:

```bash
make macos-signing-check
```

### 4. Build

```bash
./nmtk/installer/macos/build-standalone.sh --dmg --sign "$MACOS_SIGNING_IDENTITY" --notarize
```

## GitHub Actions secrets

Configure these repository secrets for `.github/workflows/release-desktop.yml`:

| Secret | Description |
|--------|-------------|
| `MACOS_CERTIFICATE_P12` | Base64-encoded `.p12` export |
| `MACOS_CERTIFICATE_PASSWORD` | Password for the `.p12` file |
| `MACOS_SIGNING_IDENTITY` | Full Developer ID Application identity string |
| `APPLE_ID` | Apple ID email used for notarization |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password (not your Apple ID password) |
| `APPLE_TEAM_ID` | 10-character Team ID |

Encode a certificate for CI:

```bash
base64 -i DeveloperID.p12 | pbcopy
```

When secrets are absent, the release workflow still builds an unsigned DMG. When all signing + notarization secrets are present, the workflow imports the certificate, signs the bundle and DMG, and submits the DMG to Apple notary service.

## CI verification without certificates

The signing helper supports dry-run mode so CI can prove the release path would invoke `codesign` and `notarytool`:

```bash
MACOS_SIGNING_IDENTITY='Developer ID Application: Example (TEAMID)' \
APPLE_ID='ci@example.com' \
APPLE_APP_SPECIFIC_PASSWORD='secret' \
APPLE_TEAM_ID='TEAMID' \
bash nmtk/installer/macos/sign-and-notarize.sh --dry-run sign-app /tmp/example.app
```

Pytest coverage lives in `tests/test_macos_installer_signing.py`.
