"""App-credential login: the connect-time counterpart to the admin token.

`credentials/users.json` (`{"username": "<bcrypt hash>"}`) is minted by
`install.sh --app-username/--app-password` at provision time. This module
only ever reads that file and never opens SSH or needs sudo -- a client
that already has a host can log in against an already-running server with
nothing but this HTTP call, which is the whole point of the connect/provision
split (see CEL-25's plan document).

Sessions are held in memory only: a launcher-control restart signs every
client out, same as restarting any other stateless auth server. Additive to
the existing shared `admin-token` mechanism, not a replacement for it.
"""

from __future__ import annotations

import json
import os
import secrets
import threading
import time
from pathlib import Path
from typing import Any

import bcrypt

_SESSION_TTL_SECONDS = 24 * 60 * 60
# Computed once so a request for an unknown username still pays the same
# bcrypt cost as one for a known username -- otherwise response time leaks
# which usernames exist.
_DUMMY_HASH = bcrypt.hashpw(b"nmtk-timing-dummy", bcrypt.gensalt())


class InvalidCredentialsError(Exception):
    """Raised for both an unknown username and a wrong password."""


class LauncherAuthMixin:
    """Mixed into `LauncherControlState`; expects `_sessions`/`_sessions_lock`."""

    _sessions: dict[str, dict[str, Any]]
    _sessions_lock: threading.Lock

    def login(self, payload: dict[str, Any]) -> dict[str, Any]:
        username = str(payload.get("username") or "").strip()
        password = str(payload.get("password") or "")
        if not username or not password:
            raise ValueError("username and password are required")

        users = _load_app_users()
        stored_hash = users.get(username)
        password_bytes = password.encode("utf-8")
        valid = False
        try:
            if stored_hash is not None:
                valid = bcrypt.checkpw(password_bytes, stored_hash.encode("utf-8"))
            else:
                bcrypt.checkpw(password_bytes, _DUMMY_HASH)
        except ValueError:
            valid = False
        if not valid:
            raise InvalidCredentialsError("Invalid username or password.")

        token = secrets.token_urlsafe(32)
        expires_at = time.time() + _SESSION_TTL_SECONDS
        with self._sessions_lock:
            self._sessions[token] = {"username": username, "expiresAt": expires_at}
        return {
            "token": token,
            "username": username,
            "expiresAt": int(expires_at),
        }

    def is_session_token_valid(self, token: str) -> bool:
        """True if `token` is a live (unexpired) session minted by `login`."""
        if not token:
            return False
        with self._sessions_lock:
            session = self._sessions.get(token)
            if session is None:
                return False
            if session["expiresAt"] < time.time():
                del self._sessions[token]
                return False
            return True


def _load_app_users() -> dict[str, str]:
    users_file = os.environ.get("NMTK_APP_USERS_FILE", "").strip()
    if not users_file:
        return {}
    path = Path(users_file)
    try:
        raw = path.read_text(encoding="utf-8")
    except OSError:
        return {}
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return {}
    if not isinstance(data, dict):
        return {}
    return {
        key: value
        for key, value in data.items()
        if isinstance(key, str) and isinstance(value, str)
    }
