# ADR 0004: Install Status JSON Permission Handing

## Status
Accepted

## Context
When deploying Neurochip environments (such as the Akida host or PYNQ agents), the provisioning scripts generate an `install-status.json` file. This file records the health, python environment, and configuration that control services rely on.

We encountered recurring `[Errno 13] Permission denied` errors when these install scripts execute. Specifically, the Akida host script runs steps as `root` (e.g. `sudo apt-get`, `sudo mkdir`), but occasionally writes the `install-status.json` using `sudo -u $SERVICE_USER python3`. If the file was inadvertently created by `root` (either manually or by an older provisioning process), the subsequent execution using `sudo -u $SERVICE_USER` fails.

## Decision
All shell-based provisioning sequences that orchestrate `install-status.json` (or similar status files) using lower-privileged users (e.g., `sudo -u $SERVICE_USER` or running `python3` as the normal user without `sudo_cmd`) MUST proactively resolve file ownership before attempting to write or MUST elevate back to root before writing.

To enforce this safely, the write function steps shall either:
1. Guarantee file existence via `sudo -n touch "$INSTALL_STATUS_PATH" || true` and enforce correctly ownership using `sudo -n chown "$SERVICE_USER:$SERVICE_USER" "$INSTALL_STATUS_PATH" || true` before delegating the write to lowercase.
2. OR: Evaluate the JSON payload in-memory (e.g. `STATUS_JSON="$(python3 - <<'PY' ...)"`) and then write the file as root using `printf "%s" "$STATUS_JSON" | sudo_cmd tee "$INSTALL_STATUS_PATH" > /dev/null` to cleanly overwrite regardless of previous ownership.

## Consequences
- Provisioning becomes idempotent regarding `install-status.json` permissions.
- Avoids cryptic stack traces and failed rollouts when redeploying onto existing, possibly tainted, environments.
- Adds slight overhead in the install shell script but radically improves robustness.
