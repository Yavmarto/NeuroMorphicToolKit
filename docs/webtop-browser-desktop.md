# NMTK Browser Desktop via Webtop/KasmVNC

## Motivation

The NMTK launcher (`nmtk/neuro_toolkit`) is a Flutter Linux desktop app that depends on
`desktop_webview_window` and `flutter_inappwebview` — packages incompatible with Flutter Web.
To serve the desktop app through a browser, it must run inside a container with a virtual
display and a browser-accessible VNC frontend.

## Approach

- **Base image**: `linuxserver/webtop:ubuntu-xfce` (provides XFCE desktop + KasmVNC + noVNC)
- **Display mode**: Kiosk — only the NMTK app window, no desktop chrome
- **Compose file**: standalone `docker-compose.webtop.yml` (kept separate from backend services)
- **Make target**: `make webtop` (build + start), plus `webtop-build`, `webtop-up`, `webtop-down`

## Files

| File | Action | Purpose |
|---|---|---|
| `Dockerfile.webtop` | New | Extends webtop, installs Flutter + Linux deps, builds NMTK, kiosk startup |
| `docker-compose.webtop.yml` | New | Standalone compose for the webtop service |
| `scripts/webtop-kiosk-startup.sh` | New | Overrides default desktop session to launch NMTK only |
| `Makefile` | Edit | Add webtop targets |

## Dockerfile.webtop

```dockerfile
FROM linuxserver/webtop:ubuntu-xfce

# Flutter Linux build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    clang cmake ninja-build pkg-config libgtk-3-dev \
    curl git unzip xz-utils liblzma-dev libglu1-mesa \
    && rm -rf /var/lib/apt/lists/*

# Flutter SDK (pinned; matches pubspec.yaml constraint >=3.6.0)
ARG FLUTTER_VERSION=3.32.4
RUN git clone --depth 1 --branch ${FLUTTER_VERSION} \
    https://github.com/flutter/flutter.git /opt/flutter
ENV PATH="/opt/flutter/bin:${PATH}"
RUN flutter config --no-analytics

# Build NMTK Linux binary
COPY . /app/nmtk
WORKDIR /app/nmtk/nmtk/neuro_toolkit
RUN flutter pub get && flutter build linux --release

# Kiosk startup — launch NMTK instead of full XFCE desktop
COPY scripts/webtop-kiosk-startup.sh /custom-services.d/startup.sh
RUN chmod +x /custom-services.d/startup.sh
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

## docker-compose.webtop.yml

```yaml
services:
  nmtk-webtop:
    build:
      context: .
      dockerfile: Dockerfile.webtop
    ports:
      - "${WEBTOP_PORT:-3030}:3000"
    environment:
      - PUID=${PUID:-1000}
      - PGID=${PGID:-1000}
      - TZ=${TZ:-UTC}
      - WEBTOP_TITLE=NMTK NeuroMorphic Toolkit
    volumes:
      - nmtk_webtop_config:/config
    restart: unless-stopped
    shm_size: 2gb

volumes:
  nmtk_webtop_config:
```

## Makefile targets

```makefile
WEBTOP_PORT ?= 3030

webtop-build:
	docker compose -f docker-compose.webtop.yml build

webtop-up:
	docker compose -f docker-compose.webtop.yml up -d --wait
	@echo "NMTK Desktop available at http://localhost:$(WEBTOP_PORT)"

webtop-down:
	docker compose -f docker-compose.webtop.yml down

webtop: webtop-build webtop-up
```

## Usage

```bash
# One-shot: build and start
make webtop

# Or step-by-step:
make webtop-build   # build the Docker image (first time takes several minutes)
make webtop-up      # start the container
# Open http://localhost:3030 in any browser
make webtop-down    # stop
```

## Notes

- First build is slow (Flutter SDK download + Flutter Linux compilation). Subsequent
  builds should be cached by Docker layers (copy source after `flutter pub get` layer).
- The `linuxserver/webtop` image already handles KasmVNC, noVNC, and audio. No additional
  VNC setup needed.
- For GPU acceleration, uncomment the `devices: /dev/dri` block in the compose file
  (Linux host with Intel/AMD GPU only).
- The compose file uses port 3030 by default to avoid conflicting with Grafana (3000).
- This is a development/convenience target. For production, consider the existing
  `docker-ex` remote deployment targets in the Makefile.
