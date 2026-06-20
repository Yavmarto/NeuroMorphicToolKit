# NMTK Browser Desktop via Webtop/KasmVNC

## Motivation

The NMTK launcher (`nmtk/neuro_toolkit`) is a Flutter Linux desktop app that depends on
`desktop_webview_window` and `flutter_inappwebview` — packages incompatible with Flutter Web.
To serve the desktop app through a browser, it must run inside a container with a virtual
display and a browser-accessible VNC frontend.

## Approach

- **Base image**: `linuxserver/webtop:ubuntu-xfce` (provides XFCE desktop + KasmVNC + noVNC)
- **Display mode**: Kiosk — only the NMTK app window, no desktop chrome
- **TLS**: `mkcert` issues a LAN-aware cert at container start; the host trust store is
  auto-populated on first `make webtop` so the browser accepts any of `<lan-ip>`,
  `<hostname>`, `localhost`, or `127.0.0.1` with no warning.
- **HTTP→HTTPS**: `scripts/webtop-mkcert-startup.sh` splices a 301-redirector block
  into the upstream `linuxserver/webtop` default nginx site, replacing only the
  plain-HTTP block (port 3000) and leaving the SSL block (port 3001, which serves
  the Selkies frontend over TLS) intact. Plain-HTTP requests get a 301 to
  `https://<host>:<WEBTOP_HTTPS_PORT>/` instead of the stock 400. A previous
  version overwrote the whole default site and accidentally deleted the SSL
  block — the splice approach avoids that.
- **Compose file**: standalone `docker-compose.webtop.yml` (kept separate from backend services)
- **Make target**: `make webtop` (build + start), plus `webtop-build`, `webtop-up`,
  `webtop-trust`, `webtop-down`

## Files

| File | Action | Purpose |
|---|---|---|
| `Dockerfile.webtop` | New | Extends webtop, installs Flutter + Linux deps + mkcert, builds NMTK, kiosk startup |
| `docker-compose.webtop.yml` | New | Standalone compose; maps HTTP and HTTPS ports, sets `CAROOT` |
| `scripts/webtop-kiosk-startup.sh` | New | Overrides default desktop session to launch NMTK only |
| `scripts/webtop-mkcert-startup.sh` | New | Idempotent LAN cert generator; splices the 301-redirector into the upstream nginx default site (preserving the SSL block), reloads nginx in place, and sleeps to keep the s6 longrun alive |
| `scripts/webtop-http-redirect.conf` | New | Reference for the 301-redirector block spliced into the upstream default site on port 3000 |
| `scripts/webtop-trust-ca.sh` | New | Host-side one-time CA install (system store + Firefox NSS) |
| `Makefile` | Edit | Add webtop targets and auto-trust on `webtop-up` |

## Dockerfile.webtop

```dockerfile
FROM linuxserver/webtop:ubuntu-xfce

# Flutter Linux build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    clang cmake ninja-build pkg-config libgtk-3-dev \
    curl git unzip xz-utils liblzma-dev libglu1-mesa \
    && rm -rf /var/lib/apt/lists/*

# mkcert — issues a LAN-aware TLS cert signed by a local CA at container
# start, so browsers on the host trust the HTTPS origin on first visit.
ARG MKCERT_VERSION=1.4.4
RUN set -eux; \
    curl -fsSL -o /usr/local/bin/mkcert \
        "https://github.com/FiloSottile/mkcert/releases/download/v${MKCERT_VERSION}/mkcert-v${MKCERT_VERSION}-linux-amd64"; \
    chmod +x /usr/local/bin/mkcert; \
    /usr/local/bin/mkcert --version

# Flutter SDK (stable channel; satisfies pubspec.yaml constraint >=3.6.0)
RUN git clone --depth 1 --branch stable \
    https://github.com/flutter/flutter.git /opt/flutter
ENV PATH="/opt/flutter/bin:${PATH}"
RUN flutter config --no-analytics

# Build NMTK Linux binary
COPY . /app/nmtk
WORKDIR /app/nmtk/nmtk/neuro_toolkit
RUN flutter pub get && flutter build linux --release

# mkcert cert generator — runs at container start; reloads nginx in place.
# Also renders the HTTP→HTTPS redirect site with the correct WEBTOP_HTTPS_PORT
# baked in (replaces nginx's "plain HTTP request was sent to HTTPS port" 400
# with a 301 to the HTTPS listener).
COPY scripts/webtop-mkcert-startup.sh /custom-services.d/00-mkcert-startup.sh

# Kiosk startup — launch NMTK instead of full XFCE desktop
COPY scripts/webtop-kiosk-startup.sh /custom-services.d/10-kiosk-startup.sh
RUN chmod +x /custom-services.d/00-mkcert-startup.sh /custom-services.d/10-kiosk-startup.sh
```

## scripts/webtop-kiosk-startup.sh

```bash
#!/bin/bash
# Override webtop's default XFCE session to run NMTK as a single-app kiosk.
# KasmVNC expects DISPLAY :1 and an X server already running (handled by webtop init).

NMTK_BIN=/app/nmtk/nmtk/neuro_toolkit/build/linux/x64/release/bundle/neuro_toolkit

if [ ! -f "$NMTK_BIN" ]; then
    echo "ERROR: NMTK binary not found at $NMTK_BIN" >&2
    exit 1
fi

export DISPLAY=:1
exec "$NMTK_BIN"
```

## scripts/webtop-http-redirect.conf

Reference snippet showing the *generated* form (the actual conf is written at
container start by `webtop-mkcert-startup.sh` with the `WEBTOP_HTTPS_PORT` env
var substituted for the `:3001` literal below). The script uses
`$http_host` and strips the trailing port so the redirect lands on the
public HTTPS port, not the container-internal `:3001`.

```nginx
server {
    listen      3000 default_server;
    listen [::]:3000 default_server;

    set $redirect_host $http_host;
    if ($redirect_host ~ "^(.+):[0-9]+$") {
        set $redirect_host $1;
    }
    return 301 https://$redirect_host:3001$request_uri;
}
```

## scripts/webtop-mkcert-startup.sh (excerpt)

Idempotent: regenerates the cert only when missing or when the SAN list no longer
matches the host's current LAN IPs/hostname. Cert SAN coverage is
`<lan-ip> <hostname> localhost 127.0.0.1`. The host's LAN IPs reach the script
via the `HOST_IPS` env var (set by the Makefile, forwarded by the compose file)
because the container can't see the host's IPs from its own network namespace.
Cert and CA live in `/config/mkcert` and `/config/ssl`, which both persist in
the `nmtk_webtop_config` named volume.

## scripts/webtop-trust-ca.sh (excerpt)

`docker cp`s `/config/mkcert/rootCA.pem` from the container to
`${XDG_DATA_HOME:-$HOME/.local/share}/nmtk/webtop/rootCA.pem` on the host, then
installs it into:

- Debian/Ubuntu: `/usr/local/share/ca-certificates/nmtk-webtop-ca.crt` + `update-ca-certificates`
- Fedora / RHEL / CentOS / Rocky / Alma: `/etc/pki/ca-trust/source/anchors/nmtk-webtop-ca.crt` + `update-ca-trust`
- Arch / Manjaro: `/etc/ca-certificates/trust-source/anchors/nmtk-webtop-ca.crt` + `update-ca-trust`
- macOS: `security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain`
- Firefox (any OS): NSS `certutil -A` for each profile under `~/.mozilla/firefox`

Idempotent: re-running is a no-op once the cert fingerprint matches the system store.
Falls back gracefully to a printed manual command if `sudo` needs a password
the script can't read (uses `sudo -n` everywhere so non-interactive shells
fail fast with a non-zero exit rather than hanging on a password prompt).

## docker-compose.webtop.yml

```yaml
services:
  nmtk-webtop:
    build:
      context: .
      dockerfile: Dockerfile.webtop
    ports:
      - "${WEBTOP_PORT:-3030}:3000"
      - "${WEBTOP_HTTPS_PORT:-3031}:3001"
    environment:
      - PUID=${PUID:-1000}
      - PGID=${PGID:-1000}
      - TZ=${TZ:-UTC}
      - WEBTOP_TITLE=NMTK NeuroMorphic Toolkit
      - CAROOT=/config/mkcert
      - WEBTOP_HTTPS_PORT=${WEBTOP_HTTPS_PORT:-3031}
      - HOST_IPS=${HOST_IPS:-}
    volumes:
      - nmtk_webtop_config:/config
    restart: unless-stopped
    shm_size: 2gb

volumes:
  nmtk_webtop_config:
```

## Makefile targets

```makefile
WEBTOP_PORT       ?= 3030
WEBTOP_HTTPS_PORT ?= 3031
HOST_IPS          ?= $(shell python3 -c "import socket; s=socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.connect(('8.8.8.8', 80)); print(s.getsockname()[0]); s.close()" 2>/dev/null || true)

webtop-build:
	docker compose -f docker-compose.webtop.yml build

webtop-trust:
	@WEBTOP_HTTPS_PORT=$(WEBTOP_HTTPS_PORT) WEBTOP_PORT=$(WEBTOP_PORT) bash scripts/webtop-trust-ca.sh

webtop-up:
	@echo "==> Host IPs for cert SANs: $(HOST_IPS)"
	@HOST_IPS='$(HOST_IPS)' docker compose -f docker-compose.webtop.yml up -d --wait
	@$(MAKE) --no-print-directory webtop-trust || true
	@echo "NMTK Desktop is up at: http://$$WEBTOP_IP:$(WEBTOP_PORT)"
	@echo "  (auto-redirects to HTTPS; first run installs the local CA into your host trust store)"
	@echo "  (direct HTTPS equivalent:  https://$$WEBTOP_IP:$(WEBTOP_HTTPS_PORT))"
	@echo "  (localhost also works:      http://localhost:$(WEBTOP_PORT))"

webtop-down:
	docker compose -f docker-compose.webtop.yml down

webtop: webtop-build webtop-up
```

## Usage

```bash
# One-shot: build and start (auto-trusts the local CA on first run)
make webtop

# Or step-by-step:
make webtop-build   # build the Docker image (first time takes several minutes)
make webtop-up      # start the container, auto-trust the CA
make webtop-trust   # re-run the host trust install (idempotent)
# Open http://localhost:3030 in any browser (HTTPS auto-redirect, no cert warning)
make webtop-down    # stop
```

## Notes

- First build is slow (Flutter SDK download + Flutter Linux compilation). Subsequent
  builds should be cached by Docker layers (copy source after `flutter pub get` layer).
- The `linuxserver/webtop` image already handles KasmVNC, noVNC, and audio. No additional
  VNC setup needed.
- For GPU acceleration, uncomment the `devices: /dev/dri` block in the compose file
  (Linux host with Intel/AMD GPU only).
- The compose file uses host ports 3030 (HTTP) and 3031 (HTTPS) by default to avoid
  conflicting with Grafana (3000) and the Flutter dev server (varies). Override with
  `WEBTOP_PORT=<port>` and/or `WEBTOP_HTTPS_PORT=<port>`.
- The mkcert CA is generated once inside the container and persisted in
  `nmtk_webtop_config` (under `/config/mkcert`). The host trust install (`webtop-trust`)
  is auto-invoked on first `webtop-up` and is idempotent on subsequent runs.
- The cert is valid for `<lan-ip> <hostname> localhost 127.0.0.1`. If the host picks up
  a new IP (e.g., new DHCP lease), restart the container; mkcert will detect the
  mismatch and reissue.
- This is a development/convenience target. For production, consider the existing
  `docker-ex` remote deployment targets in the Makefile.
