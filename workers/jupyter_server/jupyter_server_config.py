# Jupyter Server configuration for the NMTK worker.
# Authentication is intentionally disabled — access to the backend network
# equals access to Jupyter.  Do NOT enable token or password here; rely on
# network-level controls (localhost-only binding in standalone mode, Docker
# network isolation in container mode).

c = get_config()  # noqa: F821 — injected by Jupyter's config machinery

# ── Networking ───────────────────────────────────────────────────────────────
c.ServerApp.ip = "0.0.0.0"
c.ServerApp.port = 8008

# ── Authentication ───────────────────────────────────────────────────────────
c.ServerApp.token = ""
c.ServerApp.password = ""
c.IdentityProvider.token = ""

# ── Root user ────────────────────────────────────────────────────────────────
# Docker containers run as root by default; Jupyter refuses to start as root
# unless this flag is explicitly set.
c.ServerApp.allow_root = True

# ── Browser ──────────────────────────────────────────────────────────────────
c.ServerApp.open_browser = False

# ── CORS ─────────────────────────────────────────────────────────────────────
# Allow the Flutter WebView (and any local tooling) to talk to the server.
# Note: allow_credentials must NOT be combined with a wildcard allow_origin.
c.ServerApp.allow_origin = "*"

# ── Logging ──────────────────────────────────────────────────────────────────
c.Application.log_level = "INFO"
