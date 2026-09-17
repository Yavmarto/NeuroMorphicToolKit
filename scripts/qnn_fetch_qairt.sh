#!/usr/bin/env bash
# ponytail: best-effort QAIRT Community zip fetch; Qualcomm may return 403 without portal session.
set -euo pipefail

VERSION="${QAIRT_VERSION:-2.47.0.260601}"
DEST_DIR="${1:-${PAPERCLIP_SCRATCH_DIR:-./qairt-download}}"
ZIP_NAME="v${VERSION}.zip"
URL="https://softwarecenter.qualcomm.com/api/download/software/sdks/Qualcomm_AI_Runtime_Community/All/${VERSION}/${ZIP_NAME}"

mkdir -p "$DEST_DIR"
DEST_DIR="$(cd "$DEST_DIR" && pwd)"
ZIP_PATH="${DEST_DIR}/${ZIP_NAME}"

echo "=== QAIRT Community SDK fetch ==="
echo "Version: $VERSION"
echo "URL:     $URL"
echo "Dest:    $ZIP_PATH"

if [[ -f "$ZIP_PATH" ]]; then
  echo "Zip already exists: $ZIP_PATH"
else
  if ! curl -fL --retry 2 -o "$ZIP_PATH" "$URL"; then
    echo "ERROR: download failed (often HTTP 403 until a Qualcomm developer account accepts the license in Software Center)."
    echo "Manual path:"
    echo "  1. Create a free Qualcomm ID at https://myaccount.qualcomm.com/signup"
    echo "  2. Download 'Qualcomm AI Runtime - Community Edition' from Qualcomm Software Center"
    echo "  3. export QAIRT_SDK_ROOT=/path/to/qairt/${VERSION}"
    exit 1
  fi
fi

if [[ ! -f "${DEST_DIR}/qairt/${VERSION}/bin/envsetup.sh" ]]; then
  unzip -q "$ZIP_PATH" -d "$DEST_DIR"
fi

EXTRACT_DIR="${DEST_DIR}/qairt/${VERSION}"
if [[ ! -f "${EXTRACT_DIR}/bin/envsetup.sh" ]]; then
  echo "ERROR: extracted SDK missing bin/envsetup.sh at ${EXTRACT_DIR}"
  exit 1
fi

echo "PASS: QAIRT SDK ready at ${EXTRACT_DIR}"
echo "export QAIRT_SDK_ROOT=${EXTRACT_DIR}"
