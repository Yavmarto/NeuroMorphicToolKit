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

# ── XSRF protection ──────────────────────────────────────────────────────────
# The backend (suite_api) writes notebooks via the Contents API server-to-server.
# Jupyter's XSRF check is designed to protect browser sessions, not internal
# service calls. Since auth is already disabled (network isolation is the
# security boundary), we disable XSRF checking so PUT /api/contents/* from
# the backend is not rejected with 403.
c.ServerApp.disable_check_xsrf = True

# ── Root user ────────────────────────────────────────────────────────────────
# Docker containers run as root by default; Jupyter refuses to start as root
# unless this flag is explicitly set.
c.ServerApp.allow_root = True

# ── Browser ──────────────────────────────────────────────────────────────────
c.ServerApp.open_browser = False
c.ServerApp.default_url = '/lab'

# ── CORS ─────────────────────────────────────────────────────────────────────
# Allow the Flutter WebView (and any local tooling) to talk to the server.
# Note: allow_credentials must NOT be combined with a wildcard allow_origin.
c.ServerApp.allow_origin = "*"

# ── Logging ──────────────────────────────────────────────────────────────────
c.Application.log_level = "INFO"

# ── NMTK environment manager ───────────────────────────────────────────────────
# Server extension exposing /nmtk-envs/api/* for cloning the immutable
# NeuroStudio kernel into customisable environments. See workers/jupyter_server/
# nmtk_env_manager/.
c.ServerApp.jpserver_extensions = {"nmtk_env_manager": True}
