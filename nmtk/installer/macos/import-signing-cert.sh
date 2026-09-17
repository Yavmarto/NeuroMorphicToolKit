#!/usr/bin/env bash
set -euo pipefail

# Import a Developer ID certificate into the macOS keychain for CI or local release builds.
#
# Required environment:
#   MACOS_CERTIFICATE_P12       Base64-encoded .p12 export of the signing certificate
#   MACOS_CERTIFICATE_PASSWORD  Password used when exporting the .p12
#
# Optional:
#   MACOS_KEYCHAIN_PATH         Defaults to a temporary CI keychain path
#   MACOS_KEYCHAIN_PASSWORD     Defaults to a random value when creating a temp keychain

if [ -z "${MACOS_CERTIFICATE_P12:-}" ] || [ -z "${MACOS_CERTIFICATE_PASSWORD:-}" ]; then
  echo "Skipping certificate import: MACOS_CERTIFICATE_P12 and MACOS_CERTIFICATE_PASSWORD are not set."
  exit 0
fi

if ! command -v security >/dev/null 2>&1; then
  echo "Error: macOS 'security' tool is required to import signing certificates." >&2
  exit 1
fi

KEYCHAIN_PATH="${MACOS_KEYCHAIN_PATH:-$RUNNER_TEMP/nmtk-signing.keychain-db}"
KEYCHAIN_PASSWORD="${MACOS_KEYCHAIN_PASSWORD:-$(openssl rand -base64 32)}"
P12_PATH="${RUNNER_TEMP:-/tmp}/nmtk-signing-cert.p12"

mkdir -p "$(dirname "$KEYCHAIN_PATH")"
printf '%s' "$MACOS_CERTIFICATE_P12" | base64 -d > "$P12_PATH"

if [ ! -f "$KEYCHAIN_PATH" ]; then
  security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
fi

security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security import "$P12_PATH" \
  -P "$MACOS_CERTIFICATE_PASSWORD" \
  -A \
  -t cert \
  -f pkcs12 \
  -k "$KEYCHAIN_PATH"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security list-keychains -d user -s "$KEYCHAIN_PATH"
security find-identity -v -p codesigning "$KEYCHAIN_PATH"

rm -f "$P12_PATH"
echo "Imported Developer ID certificate into $KEYCHAIN_PATH"
