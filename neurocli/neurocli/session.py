"""Open the same authenticated backend session the launcher app uses.

The launcher app reaches a remote backend over an SSH tunnel and authenticates
every launcher-control call with an admin token it reads from the deployment
host. This module gives the CLI the identical path so `neuro backend ...` can
run any action the app can run.

Credential policy — the CLI never writes a secret to a plain file:

* Host, username and port are read from the app's own (non-secret) target list.
* The SSH password, if the target needs one, lives in the OS keychain and is
  handed to `ssh` through ``SSH_ASKPASS`` — never on a command line.
* The launcher admin token is never stored at all; it is read live over the
  authenticated SSH connection, exactly like the app does.
"""

from __future__ import annotations

import contextlib
import json
import os
import plistlib
import socket
import stat
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

import httpx

APP_BUNDLE_ID = "io.github.completedspoon6.neurotoolkit"
_TARGETS_PREF_KEY = "flutter.clientDeployment.targets.v1"
_KEYCHAIN_SERVICE = "neurocli-ssh"
_LOOPBACK = {"", "localhost", "127.0.0.1", "::1"}

# Remote ports the app forwards; see BackendTunnelService.open().
REMOTE_PORTS = {"launcher": 8090, "suite": 9000, "jupyter": 8008}

# Same probe the app runs (remote_deployment_runner.buildAdminTokenProbeScript):
# try the isolated nmtk-deploy account's token first, then the login account's.
_TOKEN_PROBE = """
set -- "$HOME/.nmtk/deploy/credentials/admin-token"
nmtk_deploy_home=$(getent passwd nmtk-deploy 2>/dev/null | cut -d: -f6)
if [ -n "$nmtk_deploy_home" ]; then
  set -- "$nmtk_deploy_home/.nmtk/deploy/credentials/admin-token" "$@"
fi
for nmtk_token_file in "$@"; do
  nmtk_token=$(cat "$nmtk_token_file" 2>/dev/null) || continue
  [ -n "$nmtk_token" ] || continue
  nmtk_code=$(curl -s -o /dev/null -m 5 -w '%{http_code}' \
    -H "X-NMTK-Admin-Token: $nmtk_token" \
    "http://127.0.0.1:8090/api/launcher/modules" 2>/dev/null)
  if [ "$nmtk_code" = "200" ]; then
    printf 'NMTK_ADMIN_TOKEN|%s\\n' "$nmtk_token"
    exit 0
  fi
done
exit 1
"""


class SessionError(RuntimeError):
    """The backend session could not be established."""


# ── target discovery ────────────────────────────────────────────────────────


@dataclass(frozen=True)
class Target:
    """A backend the CLI can talk to, mirroring the app's DeploymentTarget."""

    id: str
    display_name: str
    host: str
    username: str
    ssh_port: int
    auth_mode: str

    @property
    def is_local(self) -> bool:
        return self.host in _LOOPBACK

    @property
    def ssh_destination(self) -> str:
        return f"{self.username}@{self.host}" if self.username else self.host

    @property
    def keychain_account(self) -> str:
        return f"{self.ssh_destination}:{self.ssh_port}"


LOCAL_TARGET = Target(
    id="local",
    display_name="This machine",
    host="127.0.0.1",
    username="",
    ssh_port=22,
    auth_mode="none",
)


def _read_app_prefs() -> dict:
    """Read the launcher app's preferences plist (macOS only)."""
    plist = Path.home() / "Library" / "Preferences" / f"{APP_BUNDLE_ID}.plist"
    if sys.platform != "darwin" or not plist.is_file():
        return {}
    try:
        with plist.open("rb") as handle:
            data = plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException):
        return {}
    return data if isinstance(data, dict) else {}


def app_targets() -> list[Target]:
    """Targets the user already configured in the launcher app."""
    raw = _read_app_prefs().get(_TARGETS_PREF_KEY)
    if not isinstance(raw, str) or not raw:
        return []
    try:
        entries = json.loads(raw)
    except ValueError:
        return []
    targets = []
    for entry in entries if isinstance(entries, list) else []:
        if not isinstance(entry, dict) or not entry.get("id"):
            continue
        targets.append(
            Target(
                id=str(entry["id"]),
                display_name=str(entry.get("displayName") or entry["id"]),
                host=str(entry.get("host") or ""),
                username=str(entry.get("username") or ""),
                ssh_port=int(entry.get("sshPort") or 22),
                auth_mode=str(entry.get("authMode") or "ssh_key"),
            )
        )
    return targets


def resolve_target(target_id: str | None) -> Target:
    """Pick the target to connect to, preferring an explicit id."""
    targets = app_targets()
    wanted = target_id or os.environ.get("NMTK_TARGET")
    if wanted:
        for target in targets:
            if wanted in (target.id, target.display_name, target.host):
                return target
        if "@" in wanted or "." in wanted:  # user@host / bare host
            username, _, host = wanted.rpartition("@")
            return Target(wanted, wanted, host, username, 22, "ssh_key")
        raise SessionError(
            f"No backend named {wanted!r}. Run `neuro backend targets` to list "
            "the ones this machine knows about."
        )
    remote = [t for t in targets if not t.is_local]
    if len(remote) == 1:
        return remote[0]
    if len(remote) > 1:
        names = ", ".join(t.id for t in remote)
        raise SessionError(f"Several backends are configured ({names}); pass --target.")
    return LOCAL_TARGET


# ── keychain ────────────────────────────────────────────────────────────────


def keychain_read(account: str) -> str | None:
    """Read a stored SSH password from the OS keychain."""
    if sys.platform == "darwin":
        argv = ["security", "find-generic-password", "-s", _KEYCHAIN_SERVICE, "-a", account, "-w"]
    else:
        argv = ["secret-tool", "lookup", "service", _KEYCHAIN_SERVICE, "account", account]
    try:
        done = subprocess.run(argv, capture_output=True, text=True, check=False)
    except FileNotFoundError:
        return None
    return done.stdout.strip() or None if done.returncode == 0 else None


def keychain_write(account: str, secret: str) -> None:
    """Store an SSH password in the OS keychain."""
    if sys.platform == "darwin":
        argv = ["security", "add-generic-password", "-U", "-s", _KEYCHAIN_SERVICE, "-a", account, "-w", secret]
    else:
        argv = ["secret-tool", "store", "--label", f"NMTK {account}", "service", _KEYCHAIN_SERVICE, "account", account]
    try:
        # ponytail: macOS `security` has no stdin form for -w, so the secret goes
        # through argv here. Acceptable: macOS hides other users' argv, and this
        # is the same call the `security` man page documents.
        done = subprocess.run(argv, input=None if sys.platform == "darwin" else secret, capture_output=True, text=True, check=False)
    except FileNotFoundError as exc:
        raise SessionError(
            "No OS keychain helper found (`security` on macOS, `secret-tool` on "
            "Linux). Use an SSH key or agent instead — the CLI will not write a "
            "password to disk."
        ) from exc
    if done.returncode != 0:
        raise SessionError(f"Could not save the password to the keychain: {done.stderr.strip()}")


def keychain_delete(account: str) -> bool:
    """Forget a stored SSH password. Returns True if something was removed."""
    if sys.platform == "darwin":
        argv = ["security", "delete-generic-password", "-s", _KEYCHAIN_SERVICE, "-a", account]
    else:
        argv = ["secret-tool", "clear", "service", _KEYCHAIN_SERVICE, "account", account]
    try:
        return subprocess.run(argv, capture_output=True, text=True, check=False).returncode == 0
    except FileNotFoundError:
        return False


# ── the session ─────────────────────────────────────────────────────────────


def _free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


@dataclass
class Backend:
    """An open, authenticated connection to the NMTK backend."""

    target: Target
    urls: dict[str, str]
    admin_token: str
    _tempdir: tempfile.TemporaryDirectory | None = None
    _control_path: str | None = None
    _ssh_base: list[str] = field(default_factory=list)

    def request(
        self,
        method: str,
        path: str,
        *,
        service: str = "launcher",
        body: object | None = None,
        params: dict[str, str] | None = None,
        timeout: float = 60.0,
    ) -> httpx.Response:
        """Call a backend endpoint with the app's admin credentials."""
        base = self.urls.get(service)
        if base is None:
            raise SessionError(f"Unknown backend service {service!r}.")
        headers = {"X-NMTK-Admin-Token": self.admin_token} if self.admin_token else {}
        return httpx.request(
            method.upper(),
            f"{base}{path}",
            headers=headers,
            json=body,
            params=params,
            timeout=timeout,
        )

    def close(self) -> None:
        """Tear the SSH tunnel down."""
        if self._control_path:
            subprocess.run(
                [*self._ssh_base, "-O", "exit", self.target.ssh_destination],
                capture_output=True,
                check=False,
            )
            self._control_path = None
        if self._tempdir is not None:
            self._tempdir.cleanup()
            self._tempdir = None

    def __enter__(self) -> Backend:
        return self

    def __exit__(self, *_exc: object) -> None:
        self.close()


def _askpass_dir(password: str) -> tempfile.TemporaryDirectory:
    """A private helper directory that feeds the password to ssh over SSH_ASKPASS."""
    tmp = tempfile.TemporaryDirectory(prefix="neurocli-ssh-")
    helper = Path(tmp.name) / "askpass"
    helper.write_text('#!/bin/sh\nprintf %s "$NEUROCLI_SSH_PASSWORD"\n')
    helper.chmod(stat.S_IRWXU)
    return tmp


def _local_admin_token() -> str:
    for candidate in (Path.home() / ".nmtk" / "deploy" / "credentials" / "admin-token",):
        with contextlib.suppress(OSError):
            token = candidate.read_text().strip()
            if token:
                return token
    return os.environ.get("NMTK_ADMIN_TOKEN", "")


def open_backend(target_id: str | None = None) -> Backend:
    """Resolve credentials, open the tunnel if needed, return a live session."""
    override = os.environ.get("NMTK_LAUNCHER_URL")
    if override:
        return Backend(
            target=LOCAL_TARGET,
            urls={
                "launcher": override.rstrip("/"),
                "suite": (os.environ.get("NMTK_SUITE_API_URL") or "http://127.0.0.1:9000").rstrip("/"),
                "jupyter": (os.environ.get("NMTK_JUPYTER_URL") or "http://127.0.0.1:8008").rstrip("/"),
            },
            admin_token=os.environ.get("NMTK_ADMIN_TOKEN", ""),
        )

    target = resolve_target(target_id)
    if target.is_local:
        return Backend(
            target=target,
            urls={name: f"http://127.0.0.1:{port}" for name, port in REMOTE_PORTS.items()},
            admin_token=_local_admin_token(),
        )
    return _open_tunnel(target)


def _open_tunnel(target: Target) -> Backend:
    tmp = tempfile.TemporaryDirectory(prefix="neurocli-ctl-")
    control_path = str(Path(tmp.name) / "ctl")
    ports = {name: _free_port() for name in REMOTE_PORTS}  # ponytail: bind-then-release; a racing process could steal one

    ssh_base = [
        "ssh",
        "-p",
        str(target.ssh_port),
        "-S",
        control_path,
        "-o",
        "StrictHostKeyChecking=accept-new",
        "-o",
        "ConnectTimeout=15",
    ]
    forwards: list[str] = []
    for name, remote_port in REMOTE_PORTS.items():
        forwards += ["-L", f"{ports[name]}:127.0.0.1:{remote_port}"]

    env = dict(os.environ)
    askpass: tempfile.TemporaryDirectory | None = None
    if target.auth_mode == "ssh_password":
        password = keychain_read(target.keychain_account)
        if not password:
            tmp.cleanup()
            raise SessionError(
                f"No saved password for {target.ssh_destination}. Run "
                f"`neuro login --target {target.id}` once to store it in the OS keychain."
            )
        askpass = _askpass_dir(password)
        env["SSH_ASKPASS"] = str(Path(askpass.name) / "askpass")
        env["SSH_ASKPASS_REQUIRE"] = "force"
        env["NEUROCLI_SSH_PASSWORD"] = password
        env["DISPLAY"] = env.get("DISPLAY", ":0")
    else:
        ssh_base += ["-o", "BatchMode=yes"]

    started = subprocess.run(
        [*ssh_base, "-M", "-f", "-N", "-o", "ExitOnForwardFailure=yes", *forwards, target.ssh_destination],
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
    if askpass is not None:
        askpass.cleanup()
    if started.returncode != 0:
        tmp.cleanup()
        raise SessionError(
            f"Could not open the secure tunnel to {target.ssh_destination}: "
            f"{(started.stderr or started.stdout).strip()}"
        )

    backend = Backend(
        target=target,
        urls={name: f"http://127.0.0.1:{ports[name]}" for name in REMOTE_PORTS},
        admin_token="",
        _tempdir=tmp,
        _control_path=control_path,
        _ssh_base=ssh_base,
    )
    probe = subprocess.run(
        [*ssh_base, target.ssh_destination, "sh", "-s"],
        input=_TOKEN_PROBE,
        capture_output=True,
        text=True,
        check=False,
    )
    for line in probe.stdout.splitlines():
        if line.startswith("NMTK_ADMIN_TOKEN|"):
            backend.admin_token = line.split("|", 1)[1].strip()
            break
    if not backend.admin_token:
        backend.close()
        raise SessionError(
            "Connected over SSH, but the backend's administrator credential could "
            "not be read. Deploy or repair the backend from the app, then retry."
        )
    return backend
