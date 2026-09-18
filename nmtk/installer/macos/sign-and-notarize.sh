#!/usr/bin/env bash
set -euo pipefail

# Developer ID signing and Apple notarization for macOS release artifacts.
#
# Usage:
#   sign-and-notarize.sh sign-app <path-to.app>
#   sign-and-notarize.sh sign-dmg <path-to.dmg>
#   sign-and-notarize.sh notarize <path-to.zip|dmg>
#   sign-and-notarize.sh --check
#   sign-and-notarize.sh --dry-run <command> [args...]
#
# Environment (signing):
#   MACOS_SIGNING_IDENTITY  Developer ID Application identity name
#
# Environment (notarization — all three required):
#   APPLE_ID
#   APPLE_PASSWORD or APPLE_APP_SPECIFIC_PASSWORD
#   APPLE_TEAM_ID
#
# Optional:
#   MACOS_NOTARIZE=true     Enable notarization when credentials are present

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

DRY_RUN=false
CHECK_ONLY=false

usage() {
  cat <<'EOF'
Usage: sign-and-notarize.sh [--check | --dry-run] <command> [args...]

Commands:
  sign-app <path-to.app>     Sign an application bundle (hardened runtime)
  sign-app-adhoc <path-to.app>  Ad-hoc sign for portable unsigned builds
  sign-dmg <path-to.dmg>     Sign a DMG installer
  notarize <path>            Submit artifact to Apple notary service and staple

Flags:
  --check                    Print signing/notarization readiness and exit
  --dry-run                  Print commands without executing external tools
EOF
}

resolve_apple_password() {
  if [ -n "${APPLE_PASSWORD:-}" ]; then
    printf '%s' "$APPLE_PASSWORD"
    return 0
  fi
  if [ -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]; then
    printf '%s' "$APPLE_APP_SPECIFIC_PASSWORD"
    return 0
  fi
  return 1
}

signing_identity() {
  printf '%s' "${MACOS_SIGNING_IDENTITY:-}"
}

signing_ready() {
  [ -n "$(signing_identity)" ]
}

notarization_ready() {
  signing_ready \
    && [ -n "${APPLE_ID:-}" ] \
    && resolve_apple_password >/dev/null \
    && [ -n "${APPLE_TEAM_ID:-}" ]
}

should_notarize() {
  case "${MACOS_NOTARIZE:-}" in
    1 | true | TRUE | yes | YES) return 0 ;;
    *) return 1 ;;
  esac
}

run_cmd() {
  if [ "$DRY_RUN" = true ]; then
    printf 'DRY-RUN:'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

print_check_status() {
  local signing="false"
  local notarize="false"
  if signing_ready; then
    signing="true"
  fi
  if notarization_ready; then
    notarize="true"
  fi
  cat <<EOF
macos_signing_ready=${signing}
macos_notarization_ready=${notarize}
macos_signing_identity=${MACOS_SIGNING_IDENTITY:-}
macos_notarize_requested=$(should_notarize && echo true || echo false)
EOF
}

# codesign --deep treats python/include/python3.12 as a nested bundle and fails
# (CEL-348). Sign nested binaries bottom-up and skip the include tree.
sign_app_bundle_nested() {
  local app_path="$1"
  local identity="$2"
  shift 2
  local -a extra_args=("$@")

  if [ "$DRY_RUN" = true ]; then
    run_cmd codesign --force "${extra_args[@]}" --sign "$identity" "$app_path"
    return 0
  fi

  find "$app_path/Contents" -type f \( -name '*.dylib' -o -name '*.so' \) \
    ! -path '*/python/include/*' -print0 |
    while IFS= read -r -d '' item; do
      run_cmd codesign --force "${extra_args[@]}" --sign "$identity" "$item"
    done

  find "$app_path/Contents/Frameworks" -maxdepth 1 -type d -name '*.framework' -print0 2>/dev/null |
    while IFS= read -r -d '' item; do
      run_cmd codesign --force "${extra_args[@]}" --sign "$identity" "$item"
    done

  find "$app_path/Contents/MacOS" -type f -perm -111 -print0 2>/dev/null |
    while IFS= read -r -d '' item; do
      run_cmd codesign --force "${extra_args[@]}" --sign "$identity" "$item"
    done

  if [ -d "$app_path/Contents/Frameworks/python" ]; then
    find "$app_path/Contents/Frameworks/python" -type f \
      \( -name '*.dylib' -o -name '*.so' -o -perm -111 \) \
      ! -path '*/include/*' -print0 |
      while IFS= read -r -d '' item; do
        run_cmd codesign --force "${extra_args[@]}" --sign "$identity" "$item"
      done
  fi

  run_cmd codesign --force "${extra_args[@]}" --sign "$identity" "$app_path"
}

sign_app_bundle() {
  local app_path="$1"
  local identity
  identity="$(signing_identity)"

  if [ ! -d "$app_path" ]; then
    echo "Error: App bundle not found at $app_path" >&2
    exit 1
  fi
  if [ -z "$identity" ]; then
    echo "Error: MACOS_SIGNING_IDENTITY is required to sign $app_path" >&2
    exit 1
  fi

  echo "==> Code signing app bundle with identity: $identity"
  sign_app_bundle_nested "$app_path" "$identity" --options runtime --timestamp
  if [ "$DRY_RUN" = false ]; then
    codesign --verify --deep --strict --verbose=2 "$app_path"
  else
    run_cmd codesign --verify --deep --strict --verbose=2 "$app_path"
  fi
}

sign_app_bundle_adhoc() {
  local app_path="$1"

  if [ ! -d "$app_path" ]; then
    echo "Error: App bundle not found at $app_path" >&2
    exit 1
  fi

  echo "==> Re-signing app ad-hoc for portability..."
  sign_app_bundle_nested "$app_path" "-"
}

sign_dmg_file() {
  local dmg_path="$1"
  local identity
  identity="$(signing_identity)"

  if [ ! -f "$dmg_path" ]; then
    echo "Error: DMG not found at $dmg_path" >&2
    exit 1
  fi
  if [ -z "$identity" ]; then
    echo "Error: MACOS_SIGNING_IDENTITY is required to sign $dmg_path" >&2
    exit 1
  fi

  echo "==> Code signing DMG with identity: $identity"
  run_cmd codesign --force --timestamp --sign "$identity" "$dmg_path"
}

notarize_artifact() {
  local artifact_path="$1"
  local apple_password
  local submit_path="$artifact_path"
  local zip_path=""

  if ! notarization_ready; then
    echo "Error: notarization requires MACOS_SIGNING_IDENTITY, APPLE_ID, APPLE_PASSWORD (or APPLE_APP_SPECIFIC_PASSWORD), and APPLE_TEAM_ID" >&2
    exit 1
  fi
  if [ ! -e "$artifact_path" ]; then
    echo "Error: Artifact not found at $artifact_path" >&2
    exit 1
  fi

  apple_password="$(resolve_apple_password)"

  if [ -d "$artifact_path" ]; then
    zip_path="${artifact_path}.zip"
    echo "==> Creating notarization zip for app bundle..."
    if [ "$DRY_RUN" = true ]; then
      run_cmd ditto -c -k --sequesterRsrc --keepParent "$artifact_path" "$zip_path"
    else
      ditto -c -k --sequesterRsrc --keepParent "$artifact_path" "$zip_path"
    fi
    submit_path="$zip_path"
  fi

  echo "==> Submitting $submit_path to Apple notary service..."
  run_cmd xcrun notarytool submit "$submit_path" \
    --apple-id "$APPLE_ID" \
    --password "$apple_password" \
    --team-id "$APPLE_TEAM_ID" \
    --wait

  if [ -d "$artifact_path" ]; then
    echo "==> Stapling notarization ticket to app bundle..."
    run_cmd xcrun stapler staple "$artifact_path"
    if [ -n "$zip_path" ] && [ "$DRY_RUN" = false ] && [ -f "$zip_path" ]; then
      rm -f "$zip_path"
    elif [ -n "$zip_path" ] && [ "$DRY_RUN" = true ]; then
      run_cmd rm -f "$zip_path"
    fi
  else
    echo "==> Stapling notarization ticket to $artifact_path..."
    run_cmd xcrun stapler staple "$artifact_path"
  fi
}

if [ "${1:-}" = "--check" ]; then
  print_check_status
  exit 0
fi

if [ "${1:-}" = "--dry-run" ]; then
  DRY_RUN=true
  shift
fi

if [ $# -lt 1 ]; then
  usage >&2
  exit 1
fi

COMMAND="$1"
shift

case "$COMMAND" in
  sign-app)
    [ $# -eq 1 ] || { echo "Error: sign-app requires exactly one argument" >&2; exit 1; }
    sign_app_bundle "$1"
    ;;
  sign-app-adhoc)
    [ $# -eq 1 ] || { echo "Error: sign-app-adhoc requires exactly one argument" >&2; exit 1; }
    sign_app_bundle_adhoc "$1"
    ;;
  sign-dmg)
    [ $# -eq 1 ] || { echo "Error: sign-dmg requires exactly one argument" >&2; exit 1; }
    sign_dmg_file "$1"
    ;;
  notarize)
    [ $# -eq 1 ] || { echo "Error: notarize requires exactly one argument" >&2; exit 1; }
    notarize_artifact "$1"
    ;;
  -h | --help | help)
    usage
    ;;
  *)
    echo "Error: Unknown command: $COMMAND" >&2
    usage >&2
    exit 1
    ;;
esac
