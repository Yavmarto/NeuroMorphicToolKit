"""One-time root SSH bootstrap: create a dedicated non-root deploy user.

Lets `launcher_control` accept transient root SSH credentials, use them for
a single SSH session to create a dedicated non-root deploy user (default
"nmtk") with its own freshly generated SSH keypair, and return that new
user's credentials. Root credentials passed into `ssh_root_bootstrap` are
never written to disk and never touch `DeploymentStore`/`FileBackedSecretStore`
— they live only as local variables for the duration of one function call.
The caller is expected to persist the returned deploy-user credentials
through the normal deployment-target secret flow, exactly as if they had
been pasted in manually.
"""

from __future__ import annotations

import os
import shlex
import subprocess
import tempfile

from .deployment_contracts import (
    container_engine_install_commands,
    encode_remote_script,
    sudo_elevation_preamble,
)
from .deployment_executors import build_ssh_argv

__all__ = ["ssh_root_bootstrap", "build_bootstrap_script", "generate_ed25519_keypair"]

DEFAULT_DEPLOY_USERNAME = "nmtk"


def generate_ed25519_keypair() -> tuple[str, str]:
    """Generate a fresh ed25519 keypair via `ssh-keygen`.

    Returns (private_key_pem, public_key_line). Both are read into memory;
    the temp directory holding the on-disk key files is removed immediately
    after, so no trace of the generated key is left on this machine either.
    """
    with tempfile.TemporaryDirectory(prefix="nmtk-keygen-") as tmpdir:
        key_path = os.path.join(tmpdir, "nmtk_deploy_key")
        result = subprocess.run(
            [
                "ssh-keygen",
                "-t",
                "ed25519",
                "-N",
                "",
                "-C",
                "nmtk-deploy",
                "-f",
                key_path,
            ],
            capture_output=True,
            text=True,
            check=False,
            timeout=15,
        )
        if result.returncode != 0:
            err = result.stderr.strip() or "ssh-keygen failed"
            raise RuntimeError(f"Could not generate deploy user SSH key: {err}")
        with open(key_path, "r") as fh:
            private_key = fh.read()
        with open(f"{key_path}.pub", "r") as fh:
            public_key = fh.read().strip()
    return private_key, public_key


def build_bootstrap_script(
    *, deploy_username: str, public_key_line: str, container_engine: str = "docker"
) -> str:
    """Build the remote bash script that creates the deploy user.

    Idempotent: if the user already exists, it's reused (not recreated) and
    its authorized_keys is still (re)written — the common reason to run this
    twice is retrying after a partial failure or rotating access, and
    erroring out would force a manual SSH cleanup by the same user this
    feature exists to spare that from.

    Every privileged step runs through `sudo_cmd` rather than assuming the
    SSH login itself is literally `root` — most real servers (default cloud
    images included) disable direct root login and only allow logging in as
    a sudo-capable admin account. `sudo_cmd`/`sudo_available` mirror the
    established pattern in provisioning_helpers.py's Akida install script:
    feed a sudo password via `NMTK_DEPLOY_SUDO_PASSWORD` (set by the caller
    to the same password used for SSH auth, when one was given) through
    `sudo -S`, or fall back to passwordless `sudo -n` -- which also covers a
    literal root login for free, since root never needs a sudo password.

    The public key is written to an unprivileged temp file first, then
    placed with `sudo_cmd install` -- NOT `sudo_cmd tee ... <<EOF`, since
    `sudo -S` and a heredoc both want to read the password/content from the
    same stdin, and the heredoc content would be swallowed by the password
    read instead of reaching the target file.

    Engine install commands (and the `sudo_cmd`/`sudo_available` preamble)
    are shared with `deployment_executors.DockerDeploymentExecutor`'s
    deploy-time install-if-missing step -- see `deployment_contracts`.
    """
    quoted_user = shlex.quote(deploy_username)
    install_block = container_engine_install_commands(container_engine)
    if container_engine != "podman":
        # Bootstrap-specific: grant the newly-created user docker access.
        # Not part of the shared install commands since the deploy-time
        # install step (an existing user) handles its own group fix-up
        # separately via _ensure_docker_permissions.
        install_block += (
            '\nsudo_cmd usermod -aG docker "$DEPLOY_USER"\n'
            "echo \"[nmtk-bootstrap] added '$DEPLOY_USER' to the docker group\"\n"
        )
    return f"""#!/usr/bin/env bash
set -euo pipefail

DEPLOY_USER={quoted_user}

{sudo_elevation_preamble()}
if id -u "$DEPLOY_USER" >/dev/null 2>&1; then
  echo "[nmtk-bootstrap] user '$DEPLOY_USER' already exists; reusing account and rotating its SSH key"
else
  echo "[nmtk-bootstrap] creating user '$DEPLOY_USER'"
  sudo_cmd useradd --create-home --shell /bin/bash "$DEPLOY_USER"
fi

{install_block}
HOME_DIR="$(getent passwd "$DEPLOY_USER" | cut -d: -f6)"
PUBKEY_TMP="$(mktemp)"
cat > "$PUBKEY_TMP" <<'NMTK_PUBKEY_EOF'
{public_key_line}
NMTK_PUBKEY_EOF
sudo_cmd install -d -m 700 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "$HOME_DIR/.ssh"
sudo_cmd install -m 600 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "$PUBKEY_TMP" "$HOME_DIR/.ssh/authorized_keys"
rm -f "$PUBKEY_TMP"

echo "[nmtk-bootstrap] done"
"""


def ssh_root_bootstrap(
    *,
    host: str,
    ssh_port: int = 22,
    root_username: str = "root",
    root_password: str = "",
    root_private_key: str = "",
    deploy_username: str = DEFAULT_DEPLOY_USERNAME,
    container_engine: str = "docker",
    timeout: int = 60,
) -> dict[str, str]:
    """Bootstrap a dedicated non-root deploy user via a one-time root SSH session.

    Exactly one of `root_password`/`root_private_key` must be provided.
    Neither is ever persisted anywhere — they're only used to open a single
    SSH connection, then discarded when this function returns.
    """
    if not host:
        raise ValueError("host is required")
    if bool(root_password) == bool(root_private_key):
        raise ValueError("Provide exactly one of root_password or root_private_key")

    private_key_pem, public_key_line = generate_ed25519_keypair()
    script = build_bootstrap_script(
        deploy_username=deploy_username,
        public_key_line=public_key_line,
        container_engine=container_engine,
    )
    remote_cmd = encode_remote_script(
        script,
        env=(
            {"NMTK_DEPLOY_SUDO_PASSWORD": root_password}
            if root_password
            else None
        ),
    )

    key_path = None
    try:
        if root_private_key:
            fd, key_path = tempfile.mkstemp(prefix="nmtk-root-ssh-key-")
            with os.fdopen(fd, "w") as fh:
                fh.write(root_private_key)
            os.chmod(key_path, 0o600)

        ssh_args, ssh_env = build_ssh_argv(
            ssh_port, key_path=key_path, password=root_password or None
        )
        remote = f"{root_username}@{host}"
        env = dict(os.environ)
        env.update(ssh_env)
        result = subprocess.run(
            ssh_args + [remote, remote_cmd],
            capture_output=True,
            text=True,
            check=False,
            timeout=timeout,
            env=env,
        )
    finally:
        if key_path:
            try:
                os.unlink(key_path)
            except OSError:
                pass

    if result.returncode != 0:
        stderr = (
            result.stderr.strip() or result.stdout.strip() or "root bootstrap failed"
        )
        hint = ""
        if (
            "[nmtk-bootstrap] creating user" in result.stdout
            and "[nmtk-bootstrap] done" not in result.stdout
        ):
            hint = (
                f" (the '{deploy_username}' account may have been partially created"
                " -- retrying this step is safe and will finish the setup)"
            )
        raise RuntimeError(f"Root bootstrap failed on remote host: {stderr}{hint}")

    return {"username": deploy_username, "sshPrivateKey": private_key_pem}
