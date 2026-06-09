# Debug Web Build via Docker

How to build the Flutter launcher in debug mode and serve it over the network via Docker so any device — desktop, tablet, or phone — can access the UI from a browser, without building a release app binary.

---

## 1. Current State

The project already has:

| Target | What it does |
|--------|-------------|
| `make dev-web` | `flutter run -d chrome` — live hot-reload in Chrome on localhost |
| `make dev` / `make dev-native` | Native desktop launcher (macOS/Linux/Windows) |
| `make docker` | Docker backends + native desktop launcher |
| `make dev-a` / `make dev-i` | Android / iOS via `flutter run -d <device>` |

No existing target builds the Flutter web output as static files and serves them through Docker for network-wide browser access.

---

## 2. How It Works

Flutter's `build web --debug` produces an un-minified, dart2js-compiled static site in `nmtk/neuro_toolkit/build/web/`. Serving that directory behind nginx in a Docker container makes it reachable from any device on the same network — no Flutter SDK needed on the client.

```
┌──────────────────────────────────────────────────────┐
│                    Host Machine                       │
│  ┌──────────────────────────────────────────────┐    │
│  │  Docker: nginx serving flutter build/web/    │    │
│  │  Port 8080 → container port 80               │    │
│  └──────────────────────────────────────────────┘    │
│                          │                           │
└──────────────────────────┼───────────────────────────┘
                           │
           ┌───────────────┼───────────────┐
           ▼               ▼               ▼
     ┌─────────┐     ┌─────────┐     ┌─────────┐
     │ Desktop │     │  Tablet │     │  Phone  │
     │ Browser │     │ Browser │     │ Browser │
     └─────────┘     └─────────┘     └─────────┘
      host:8080       host:8080      host:8080
```

The Flutter web app auto-adapts layout: the same build renders a full-width sidebar+content shell on desktop and a single-column navigation on mobile screens.

---

## 3. What Needs to Be Added

Three small files, all in the repo root:

### 3.1 `docker-compose.debug-web.yml`

```yaml
services:
  debug-web:
    image: nginx:alpine
    ports:
      - "${DEBUG_WEB_PORT:-8080}:80"
    volumes:
      - ./nmtk/neuro_toolkit/build/web:/usr/share/nginx/html:ro
      - ./docker/debug-web-nginx.conf:/etc/nginx/conf.d/default.conf:ro
```

### 3.2 `docker/debug-web-nginx.conf`

```nginx
server {
    listen 80;
    server_name _;

    root /usr/share/nginx/html;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    # Enable gzip for the Flutter web payload (canonicalize, main.dart.js, etc.)
    gzip on;
    gzip_types text/plain text/css application/javascript application/json
               image/svg+xml application/wasm;
    gzip_min_length 256;

    # CORS headers so the web app can reach the suite_api on another port
    add_header Access-Control-Allow-Origin *;
}
```

### 3.3 Makefile targets (appended to root `Makefile`)

```makefile
.PHONY: debug-web-build debug-web-up debug-web-down debug-web

DEBUG_WEB_PORT ?= 8080

debug-web-build:
	cd nmtk/neuro_toolkit && flutter build web --debug \
		--dart-define="NMTK_CONTROL_API_BASE_URL=http://localhost:8091" \
		--dart-define="NMTK_CONTROL_API_PORT=8091"

debug-web-up:
	DEBUG_WEB_PORT=$(DEBUG_WEB_PORT) docker compose -f docker-compose.debug-web.yml up -d
	@echo "==> Web UI at http://localhost:$(DEBUG_WEB_PORT)"
	@echo "    Other devices on the network use: http://<host-ip>:$(DEBUG_WEB_PORT)"

debug-web-down:
	docker compose -f docker-compose.debug-web.yml down

debug-web: debug-web-build debug-web-up
	@echo "==> Debug web build served via Docker on http://localhost:$(DEBUG_WEB_PORT)"
```

---

## 4. Usage

```bash
# Build and serve in one step
make debug-web

# Or step by step
make debug-web-build    # flutter build web --debug
make debug-web-up       # start nginx container
make debug-web-down     # stop the container

# Custom port
make debug-web DEBUG_WEB_PORT=3000
```

The app expects backends to be running. Start them separately:

```bash
make docker              # Docker backends + native launcher (skip the launcher part)
# or just
docker compose up -d     # starts suite_api, launcher-control, workers
```

---

## 5. What Changes Would Satisfy "Mobile and Desktop Versions"

No separate build is needed. The Flutter web app uses responsive layout widgets — `LayoutBuilder`, `MediaQuery`, and `NavigationRail`/`BottomNavigationBar` switching — so the same URL delivers the appropriate UI to any screen size.

| Device | Experience |
|--------|-----------|
| Desktop browser | Full sidebar + content shell |
| Tablet browser | Adaptive: sidebar collapses to bottom rail at narrow widths |
| Phone browser | Single-column, bottom nav, touch-optimized |

If a truly device-specific layout is desired later, that is a Dart-side concern (conditionals on `MediaQuery.of(context).size.width`) and does not change the build or serve strategy.

---

## 6. Comparison with Existing Targets

| Target | Backend | Frontend | Network Access |
|--------|---------|----------|---------------|
| `make dev` | Host process | Native desktop app | Host only |
| `make dev-web` | Host process | Chrome localhost | Host only |
| `make docker` | Docker | Native desktop app | Host only |
| **`make debug-web`** | **Docker (separate)** | **Docker nginx + Flutter web** | **Full LAN** |

`make debug-web` is the only target that makes the UI reachable from any device on the network through a standard browser — no Flutter SDK, no platform-specific build, no app install required on the client.

---

## 7. Notes

- `flutter build web --debug` produces larger output than release mode (~15–30 MB of JS). It is not suitable for production use but ideal for local/network development.
- The nginx `try_files` rule handles Flutter's client-side routing (GoRouter path strategy) so deep links work correctly.
- If the suite_api or launcher-control ports differ from defaults (8091, 9000), adjust the `--dart-define` values in `debug-web-build` and the nginx CORS config accordingly.
- Docker Desktop must expose the debug-web port (8080) to the LAN. Most installations do this by default; check Docker Desktop → Settings → Resources → Network if other devices cannot connect.
