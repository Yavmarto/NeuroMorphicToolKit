#!/usr/bin/env bash
# Idempotently issue a LAN-aware TLS cert for the webtop kiosk using mkcert,
# splice the HTTP→HTTPS redirector into the upstream nginx default site,
# reload nginx, and stay alive (sleep infinity) so s6 does not respawn us in
# a tight loop.
#
# Why a splice (and not a full-file rewrite): the upstream
# linuxserver/webtop image ships /etc/nginx/sites-enabled/default with TWO
# server blocks — an HTTP block on :3000 that serves the Selkies web
# frontend + websocket proxy, and an SSL block on :3001 that serves the same
# content over TLS. We replace only the HTTP block (with a 301 redirector)
# and leave the SSL block intact; the SSL block already references
# /config/ssl/cert.pem and /config/ssl/cert.key, which is exactly where
# mkcert writes. A previous version of this script overwrote the whole file
# with just the redirector, which deleted the SSL block and broke HTTPS.
#
# Cert SAN coverage: <lan-ip-1> [<lan-ip-2> ...] <hostname> localhost 127.0.0.1
# Cert + CA persist in /config (CAROOT=/config/mkcert) across rebuilds.

set -euo pipefail

# s6-overlay (linuxserver base) places compose `environment:` values in
# /run/s6/container_environment/. When this script is invoked as a custom
# service from /custom-services.d/ the env is normally inherited, but if
# s6 ran us in a clean env we need to load HOST_IPS / WEBTOP_HTTPS_PORT
# from there explicitly.
S6_ENV_DIR="/run/s6/container_environment"
for key in HOST_IPS WEBTOP_HTTPS_PORT; do
    if [ -z "${!key:-}" ] && [ -f "$S6_ENV_DIR/$key" ]; then
        export "$key"="$(tr -d '\r\n' < "$S6_ENV_DIR/$key")"
    fi
done

CAROOT_DIR="/config/mkcert"
CERT_FILE="/config/ssl/cert.pem"
KEY_FILE="/config/ssl/cert.key"
MKCERT_BIN="/usr/local/bin/mkcert"
NGINX_SITE="/etc/nginx/sites-enabled/default"
# WEBTOP_HTTPS_PORT is the *public* port (e.g. 3031 on the host) that
# the browser should be redirected to. The HTTPS *listener* inside the
# container is always on the linuxserver/webtop default 3001, regardless
# of the public port — the public port only changes the host-side docker
# mapping. We use 3001 (not WEBTOP_HTTPS_PORT) for the in-container
# self-check below.
WEBTOP_HTTPS_PORT="${WEBTOP_HTTPS_PORT:-3001}"
INTERNAL_HTTPS_PORT="3001"

log() { printf '[webtop-mkcert] %s\n' "$*"; }
warn() { printf '[webtop-mkcert] WARN: %s\n' "$*" >&2; }
die() { printf '[webtop-mkcert] ERROR: %s\n' "$*" >&2; exit 1; }

[ -x "$MKCERT_BIN" ] || die "mkcert binary not found at $MKCERT_BIN (Dockerfile.webtop installs it)."
command -v openssl >/dev/null 2>&1 || die "openssl not found in PATH; needed for SAN inspection."

mkdir -p "$CAROOT_DIR"
export CAROOT="$CAROOT_DIR"

# ---------------------------------------------------------------------------
# Detect all SANs we need: every non-loopback IPv4 address on the host,
# the short hostname, localhost, and 127.0.0.1. Optionally accepts
# HOST_IPS (comma-separated) from the host to include the host's actual
# LAN IPs in the cert (the container can't see the host's IPs from
# inside its own network namespace).
# ---------------------------------------------------------------------------
collect_sans() {
    local -a sans=()
    while IFS= read -r ip; do
        [ -n "$ip" ] || continue
        sans+=("$ip")
    done < <(hostname -I 2>/dev/null | tr ' ' '\n' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || true)
    if [ -n "${HOST_IPS:-}" ]; then
        IFS=',' read -ra extra <<<"$HOST_IPS"
        for ip in "${extra[@]}"; do
            ip="${ip// /}"
            [ -n "$ip" ] && sans+=("$ip")
        done
    fi
    # Skip container-id-shaped hostnames (12-char hex); they aren't useful
    # as browser-typed hosts.
    local hn
    hn="$(hostname 2>/dev/null || true)"
    if [ -n "$hn" ] && ! [[ "$hn" =~ ^[0-9a-f]{12}$ ]]; then
        sans+=("$hn")
    fi
    sans+=("localhost")
    sans+=("127.0.0.1")
    # Dedupe, drop empties, preserve order.
    printf '%s\n' "${sans[@]}" | awk 'NF && !seen[$0]++'
}

SANS=()
while IFS= read -r s; do SANS+=("$s"); done < <(collect_sans)
[ "${#SANS[@]}" -gt 0 ] || die "no SANs detected (hostname returned nothing usable)."

# ---------------------------------------------------------------------------
# Decide whether we need to (re)issue. The cert needs to be regenerated if
# it is missing, unreadable, or the SAN list no longer matches the host's
# current IPs/hostname.
# ---------------------------------------------------------------------------
needs_issue() {
    [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ] || return 0
    # Compare the cert's SAN list to the desired list. openssl prints
    # subjectAltName across two lines:
    #     X509v3 Subject Alternative Name:
    #         DNS:foo, IP Address:1.2.3.4, ...
    # Strip the header (`1d; p` — delete line 1, then print line 2),
    # split on commas, extract each SAN. The `|| true` swallows sed's
    # non-zero exit on no-match so `set -o pipefail` doesn't trip.
    local current
    current="$(openssl x509 -in "$CERT_FILE" -noout -ext subjectAltName 2>/dev/null \
        | sed -n '1d; p' \
        | tr ',' '\n' \
        | sed -nE 's/^[[:space:]]*(IP Address|DNS):[[:space:]]*([^[:space:],]+).*/\2/p' \
        | sort -u || true)"
    [ -n "$current" ] || return 0
    local desired
    desired="$(printf '%s\n' "${SANS[@]}" | sort -u)"
    [ "$current" = "$desired" ] || return 0
    return 1
}

# ---------------------------------------------------------------------------
# Ensure the local CA exists. `mkcert -install` writes the CA into CAROOT
# and (best-effort) installs it into the system trust store; the system
# install may fail in a container and that's fine — the host-side
# `make webtop-trust` target handles host trust.
# ---------------------------------------------------------------------------
if [ ! -f "$CAROOT_DIR/rootCA.pem" ] || [ ! -f "$CAROOT_DIR/rootCA-key.pem" ]; then
    log "generating local CA in $CAROOT_DIR"
    "$MKCERT_BIN" -install >/dev/null 2>&1 || \
        log "mkcert -install: system-trust install skipped (expected in container)"
fi

if needs_issue; then
    log "issuing cert for: ${SANS[*]}"
    mkdir -p "$(dirname "$CERT_FILE")"
    # shellcheck disable=SC2086
    "$MKCERT_BIN" \
        -cert-file "$CERT_FILE" \
        -key-file  "$KEY_FILE" \
        "${SANS[@]}"
    log "cert written: $CERT_FILE"
else
    log "cert already valid for current SANs; skipping"
fi

# ---------------------------------------------------------------------------
# Splice the HTTP→HTTPS redirector into the upstream default site. We must
# not overwrite the file: the upstream webtop image ships BOTH an HTTP
# server block on :3000 and an SSL server block on :3001 (the latter is
# the actual Selkies frontend over TLS). We replace only the HTTP block
# (the one whose `listen` line includes `3000 default_server` and does NOT
# include `ssl`) with a 301-redirect block, and leave everything else
# untouched. The HTTPS block already references /config/ssl/cert.pem and
# /config/ssl/cert.key, which is what mkcert writes.
#
# This makes the redirect target correct: the browser is sent to
# https://<host>:<WEBTOP_HTTPS_PORT>/, and nginx then serves the Selkies
# frontend over TLS from the SSL block.
# ---------------------------------------------------------------------------

REDIRECT_BLOCK=$(cat <<EOF
server {
    listen      3000 default_server;
    listen [::]:3000 default_server;

    set \$redirect_host \$http_host;
    if (\$redirect_host ~ "^(.+):[0-9]+\$") {
        set \$redirect_host \$1;
    }
    return 301 https://\$redirect_host:${WEBTOP_HTTPS_PORT}\$request_uri;
}
EOF
)

if [ ! -f "$NGINX_SITE" ]; then
    die "$NGINX_SITE not found; cannot splice redirector."
fi

# awk-based splice: replace the *first* `server { ... }` block whose
# listen line matches `3000` (and is not the SSL `3001` line) with the
# redirector. We walk the file line by line tracking brace depth; the
# first time we see a top-level `server {` and one of its descendant
# `listen` lines matches `3000 default_server`, we substitute the whole
# block and skip to the matching closing brace.
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

awk -v redirect="$REDIRECT_BLOCK" '
    BEGIN { in_block = 0; depth = 0; replaced = 0; saw_http_listen = 0 }
    {
        line = $0
        if (!in_block) {
            # Detect a top-level "server {" (allow leading whitespace).
            if (line ~ /^[[:space:]]*server[[:space:]]*\{/) {
                in_block = 1
                depth = 1
                # Buffer the block so we can decide whether to replace it
                # once we see its first listen line.
                block = line "\n"
                saw_http_listen = 0
                next
            }
            print line
            next
        }
        # Inside a server block. Track braces and look at listen lines.
        block = block line "\n"
        if (line ~ /listen[[:space:]]+3000[[:space:]]+default_server/) {
            saw_http_listen = 1
        }
        n_open  = gsub(/\{/, "{", line)
        n_close = gsub(/\}/, "}", line)
        depth += n_open - n_close
        if (depth == 0) {
            # End of the current top-level server block.
            if (saw_http_listen && !replaced) {
                printf "%s\n", redirect
                replaced = 1
            } else {
                printf "%s", block
            }
            in_block = 0
            block = ""
            saw_http_listen = 0
        }
        next
    }
    END {
        if (in_block) {
            # Unterminated block; bail safely.
            printf "%s", block
        }
        if (!replaced) {
            exit 2
        }
    }
' "$NGINX_SITE" > "$tmp" || rc=$?
rc="${rc:-0}"

if [ "${rc:-0}" = "2" ]; then
    rm -f "$tmp"
    die "no top-level 'server { listen 3000 default_server; ... }' block found in $NGINX_SITE; cannot splice redirector. File may have been customised upstream."
fi

if cmp -s "$tmp" "$NGINX_SITE"; then
    log "nginx site already patched; no changes"
else
    cp "$tmp" "$NGINX_SITE"
    log "spliced HTTP→HTTPS redirector (port ${WEBTOP_HTTPS_PORT}); preserved SSL block on :3001"
fi

# ---------------------------------------------------------------------------
# Reload nginx so the new cert + site are picked up without restarting
# the container. If nginx isn't running yet (first-boot race), the s6
# init service will pick the new cert on its own start.
# ---------------------------------------------------------------------------
if pgrep -x nginx >/dev/null 2>&1; then
    if nginx -s reload >/dev/null 2>&1; then
        log "nginx reloaded"
    else
        warn "nginx reload failed; cert/site will be picked up on next nginx start"
    fi
fi

# ---------------------------------------------------------------------------
# Self-check: probe the HTTPS listener inside the container. This custom
# service is a s6 longrun that starts in parallel with svc-nginx, so on
# first boot nginx may not be listening yet — poll with backoff before
# giving up. If the listener never comes up the user will get "site can't
# be reached" in the browser; the loud WARN in `docker logs` makes that
# failure mode easy to diagnose.
# ---------------------------------------------------------------------------
log "init done; entering sleep (s6 longrun stay-alive)"

# ---------------------------------------------------------------------------
# Stay alive so s6 does not respawn this longrun in a tight loop (which
# would reissue the cert every iteration). If the host's IP changes, the
# user restarts the container with `make webtop-down && make webtop`, at
# which point the SAN check above will trigger a reissue.
#
# We also run a delayed background self-check: nginx is started in
# parallel by s6 and may not be fully listening on :3001 at the moment
# this script runs its first iteration. Deferring by 30s lets the
# cold-boot XFCE + selkies stack settle, after which a single curl
# probe reliably confirms the HTTPS listener is up.
#
# `setsid` puts the self-check in its own session/process group so it
# survives the `exec sleep infinity` below (which replaces this bash
# with sleep) and is reparented to init. `disown` is belt-and-braces.
# ---------------------------------------------------------------------------
setsid bash -c '
    sleep 30
    code="$(curl -ks --max-time 3 -o /dev/null -w "%{http_code}" "https://127.0.0.1:'"${INTERNAL_HTTPS_PORT}"'/" 2>/dev/null || true)"
    [ -n "$code" ] || code="000"
    if [[ "$code" =~ ^2 ]]; then
        printf "[webtop-mkcert] self-check OK: https://127.0.0.1:'"${INTERNAL_HTTPS_PORT}"'/ -> %s\n" "$code"
    else
        printf "[webtop-mkcert] WARN: self-check FAIL: https://127.0.0.1:'"${INTERNAL_HTTPS_PORT}"'/ -> %s (HTTPS listener not responding; check '"$NGINX_SITE"')\n" "$code" >&2
    fi
' < /dev/null > /dev/stdout 2> /dev/stderr &
disown 2>/dev/null || true

exec sleep infinity
