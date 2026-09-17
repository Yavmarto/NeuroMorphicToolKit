#!/usr/bin/env bash
# One-time host-side trust install for the webtop kiosk's mkcert CA.
#
# Extracts /config/mkcert/rootCA.pem from the running nmtk-webtop container,
# copies it into the system trust store (and Firefox NSS if certutil is
# present), then verifies by checking the cert fingerprint against the
# running webtop's HTTPS endpoint.
#
# Idempotent: re-running this script is a no-op once the CA is trusted.
# Safe to call from `make webtop-up` on every start.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${REPO_ROOT}/docker-compose.webtop.yml"
SERVICE_NAME="nmtk-webtop"
CA_HOST_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/nmtk/webtop"
HOST_CA="${CA_HOST_DIR}/rootCA.pem"
CA_NAME="NMTK Webtop CA"
CERT_NICK="NMTK Webtop CA"

log()  { printf '[webtop-trust] %s\n' "$*"; }
warn() { printf '[webtop-trust] WARN: %s\n' "$*" >&2; }
die()  { printf '[webtop-trust] ERROR: %s\n' "$*" >&2; exit 1; }

command -v docker >/dev/null 2>&1 || die "docker is not on PATH. Install Docker and retry."
[ -f "$COMPOSE_FILE" ] || die "compose file not found: $COMPOSE_FILE"

# ---------------------------------------------------------------------------
# Resolve the running container. Prefer the live container id, but fall
# back to compose if no container is up.
# ---------------------------------------------------------------------------
CONTAINER_ID="$(docker compose -f "$COMPOSE_FILE" ps -q "$SERVICE_NAME" 2>/dev/null || true)"
if [ -z "$CONTAINER_ID" ]; then
    die "container '$SERVICE_NAME' is not running. Run 'make webtop' first."
fi

# ---------------------------------------------------------------------------
# Extract the CA from the container.
# ---------------------------------------------------------------------------
mkdir -p "$CA_HOST_DIR"
TMP_CA="$(mktemp "${CA_HOST_DIR}/.rootCA.pem.XXXXXX")"
trap 'rm -f "$TMP_CA"' EXIT

if ! docker cp "${CONTAINER_ID}:/config/mkcert/rootCA.pem" "$TMP_CA" 2>/dev/null; then
    die "could not copy /config/mkcert/rootCA.pem out of container ${CONTAINER_ID}. Is the mkcert startup script in the image?"
fi
chmod 0644 "$TMP_CA"

# Only update the cached copy if the cert actually changed (avoids
# re-triggering trust installs on every webtop-up).
if [ ! -f "$HOST_CA" ] || ! cmp -s "$TMP_CA" "$HOST_CA"; then
    mv "$TMP_CA" "$HOST_CA"
    trap - EXIT
    NEEDS_TRUST=1
else
    rm -f "$TMP_CA"
    trap - EXIT
    NEEDS_TRUST=0
fi
log "CA cached at $HOST_CA"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
cert_fingerprint() {
    openssl x509 -in "$HOST_CA" -noout -fingerprint -sha256 2>/dev/null \
        | sed -n 's/^sha256 Fingerprint=//Ip' | tr -d ':' | tr '[:upper:]' '[:lower:]'
}

os_id() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        printf '%s\n' "${ID:-unknown}"
    elif command -v sw_vers >/dev/null 2>&1; then
        printf 'macos\n'
    else
        printf 'unknown\n'
    fi
}

# ---------------------------------------------------------------------------
# Idempotency: was this exact cert already installed?
# ---------------------------------------------------------------------------
CA_FP="$(cert_fingerprint || true)"
already_trusted_system() {
    case "$1" in
        debian|ubuntu)
            [ -f "/usr/local/share/ca-certificates/nmtk-webtop-ca.crt" ] || return 1
            local installed_fp
            installed_fp="$(openssl x509 -in /usr/local/share/ca-certificates/nmtk-webtop-ca.crt -noout -fingerprint -sha256 2>/dev/null \
                | sed -n 's/^sha256 Fingerprint=//Ip' | tr -d ':' | tr '[:upper:]' '[:lower:]')"
            [ "$installed_fp" = "$CA_FP" ]
            ;;
        fedora|rhel|centos|rocky|alma|arch|manjaro)
            [ -f "/etc/ca-certificates/trust-source/anchors/nmtk-webtop-ca.crt" ] \
                || [ -f "/etc/pki/ca-trust/source/anchors/nmtk-webtop-ca.crt" ] || return 1
            local installed_fp path
            for path in /etc/ca-certificates/trust-source/anchors/nmtk-webtop-ca.crt \
                        /etc/pki/ca-trust/source/anchors/nmtk-webtop-ca.crt; do
                [ -f "$path" ] || continue
                installed_fp="$(openssl x509 -in "$path" -noout -fingerprint -sha256 2>/dev/null \
                    | sed -n 's/^sha256 Fingerprint=//Ip' | tr -d ':' | tr '[:upper:]' '[:lower:]')"
                [ "$installed_fp" = "$CA_FP" ] && return 0
            done
            return 1
            ;;
        macos)
            security find-certificate -c "$CA_NAME" /Library/Keychains/System.keychain >/dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

run_privileged() {
    # Run a command with sudo non-interactively. `sudo -n` fails fast
    # (no password prompt) when the user has not been granted NOPASSWD
    # access, which is what we want in CI/headless contexts: the caller
    # sees a clean non-zero exit and falls back to printing the manual
    # command. This avoids the "timed out reading password" hang that
    # non-interactive shells (e.g. `make webtop-up` from an editor task
    # runner) hit when sudo requires a TTY.
    sudo -n "$@"
}

install_system() {
    case "$1" in
        debian|ubuntu)
            run_privileged install -m 0644 "$HOST_CA" /usr/local/share/ca-certificates/nmtk-webtop-ca.crt \
                && run_privileged update-ca-certificates >/dev/null
            ;;
        fedora|rhel|centos|rocky|alma|arch|manjaro)
            # Arch uses /etc/ca-certificates/trust-source/anchors/ (p11-kit
            # tool); Fedora family uses /etc/pki/ca-trust/source/anchors/.
            # Both honour the same update-ca-trust command.
            local anchors_dir="/etc/ca-certificates/trust-source/anchors"
            [ -d "/etc/pki/ca-trust/source/anchors" ] && anchors_dir="/etc/pki/ca-trust/source/anchors"
            run_privileged install -m 0644 "$HOST_CA" "$anchors_dir/nmtk-webtop-ca.crt" \
                && run_privileged update-ca-trust >/dev/null
            ;;
        macos)
            run_privileged security add-trusted-cert -d -r trustRoot \
                -k /Library/Keychains/System.keychain "$HOST_CA"
            ;;
        *)
            warn "unrecognized OS ($1); skipping system trust install."
            warn "manually trust $HOST_CA in your browser/OS to remove the cert warning."
            return 1
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Firefox NSS trust (best-effort; only if certutil is present and profiles
# are detected).
# ---------------------------------------------------------------------------
install_firefox() {
    command -v certutil >/dev/null 2>&1 || { log "certutil not found; skipping Firefox NSS install"; return 0; }
    local profile_dir
    profile_dir="${HOME}/.mozilla/firefox"
    [ -d "$profile_dir" ] || { log "no Firefox profile dir; skipping NSS install"; return 0; }
    local installed=0
    while IFS= read -r -d '' profdb; do
        # Idempotency: if a cert with the same nickname is already present, skip.
        if certutil -L -d "sql:${profdb%/*}" 2>/dev/null | grep -qF "$CERT_NICK"; then
            continue
        fi
        if certutil -A -n "$CERT_NICK" -t 'C,,' -i "$HOST_CA" -d "sql:${profdb%/*}" >/dev/null 2>&1; then
            installed=$((installed + 1))
        fi
    done < <(find "$profile_dir" -path '*/cert9.db' -print0 2>/dev/null)
    if [ "$installed" -gt 0 ]; then
        log "trusted CA in $installed Firefox profile(s)"
    else
        log "no Firefox profiles needed updating"
    fi
}

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------
OS="$(os_id)"
SYSTEM_TRUST_OK=0
if [ "$NEEDS_TRUST" = "1" ] || ! already_trusted_system "$OS"; then
    log "installing CA into system trust store ($OS)…"
    if install_system "$OS"; then
        SYSTEM_TRUST_OK=1
    else
        warn "system trust install failed. To finish manually:"
        warn "  sudo cp '$HOST_CA' /usr/local/share/ca-certificates/nmtk-webtop-ca.crt && sudo update-ca-certificates"
    fi
else
    log "CA already trusted in system store ($OS)"
    SYSTEM_TRUST_OK=1
fi

install_firefox

# ---------------------------------------------------------------------------
# Verify against the live HTTPS endpoint. Pass the CA explicitly so
# openssl can actually verify the chain (without -CAfile it always returns
# success, which is misleading).
# ---------------------------------------------------------------------------
verify_endpoint() {
    local port="${WEBTOP_HTTPS_PORT:-3031}"
    local probe_host
    probe_host="$(python3 -c "import socket; s=socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.connect(('8.8.8.8', 80)); print(s.getsockname()[0]); s.close()" 2>/dev/null || echo "localhost")"
    if echo | openssl s_client -connect "${probe_host}:${port}" -servername "$probe_host" -CAfile "$HOST_CA" -verify_return_error >/dev/null 2>&1; then
        log "verified: https://${probe_host}:${port} cert is trusted"
    else
        warn "https://${probe_host}:${port} cert is NOT yet trusted by this host. Try: openssl s_client -connect ${probe_host}:${port} -CAfile '$HOST_CA' -showcerts"
    fi
}
if [ "$SYSTEM_TRUST_OK" = "1" ]; then
    verify_endpoint
fi

if [ "$SYSTEM_TRUST_OK" = "1" ]; then
    log "done. Open http://localhost:${WEBTOP_PORT:-3030}/ to use the desktop (HTTPS auto-redirect, no cert warning)."
else
    log "done. Cert extracted to $HOST_CA — trust it manually to remove the browser warning."
fi
