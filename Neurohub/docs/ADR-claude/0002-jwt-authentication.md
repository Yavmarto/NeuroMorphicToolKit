# ADR 0002: JWT Authentication

## Status
Accepted

## Context
As a community registry where users share models, datasets, and hardware profiles, Neurohub requires user identity management with secure authentication. Simple API key auth (used by other modules) lacks user identity and role-based access control.

## Decision
Implement JWT-based authentication with access tokens (30-minute expiry) and refresh tokens (7-day expiry) using python-jose. Passwords are hashed with bcrypt via passlib. OAuth2 password bearer flow is used for token acquisition. A hardcoded default secret key serves as a development fallback.

## Consequences
- **Positive:** Stateless JWT tokens enable horizontal scaling without session storage; refresh tokens reduce re-authentication friction for long sessions.
- **Negative:** JWT revocation requires additional infrastructure (blacklist or short expiry); the default secret key in development mode is a security risk if accidentally deployed to production.

## Status Update (2026-07-16 audit)
Two corrections to the Decision text:

1. **Password hashing:** `neurohub/app/services/auth_service.py` imports `bcrypt` directly
   (`bcrypt.hashpw` / `bcrypt.checkpw`) — it does not go through passlib. `passlib` is not
   listed in `pyproject.toml`'s `dependencies` (only `bcrypt>=4.0.1,<5` is); it does still
   appear in `uv.lock`, which looks like a stale artifact from before the switch to bcrypt and
   is not exercised by any executable code path.
2. **Secret key:** there is no hardcoded default secret key. `neurohub/app/main.py` reads
   `NEUROHUB_SECRET_KEY` via `os.environ.get("NEUROHUB_SECRET_KEY", "")`, i.e. the fallback is
   an empty string, not a baked-in secret. `_validate_startup_config()` fails fast at startup
   (`raise SystemExit(1)`) when `ENVIRONMENT=production` and the key is empty or matches the
   known-insecure value in `_INSECURE_SECRET_KEYS`, so an insecure key cannot silently reach
   production.
