# Give Docker deployment real Akida hardware access

## Origin
Started as a port-8002 bind-conflict investigation on `make docker-ex-m REMOTE_HOST=moosebun2@192.168.68.53`. Root cause turned out to be the native `neurochip.service` (real Akida SDK, real hardware access) fighting the Docker container `neurochip-hw-worker` (no Akida SDK installed, zero hardware routes) for the same port.

## Decision
Don't containerize Akida hardware access (no vendor device-node/driver info exists anywhere in this repo). Instead, redirect the app's existing `NEUROCHIP_HW_WORKER_URL` proxy mechanism at the native `neurochip.service` via `host.docker.internal`, opt-in via `AKIDA_NATIVE=1`.

## Files changed
- `docker-compose.akida-native.yml` (new overlay) — drops `neurochip-hw-worker`'s port publish (`!reset []`), repoints `suite_api`/`launcher-control` at `host.docker.internal:8002` + API key.
- `docker-compose.yml` — fixed stale "18002 vs 8002" comment on `launcher-control`.
- `suite_api/proxy.py` — `proxy_to_worker()` gained optional `extra_headers` param.
- `suite_api/config.py` / `suite_api/domains/neurochip/router.py` — new `neurochip_hw_worker_api_key` setting, sent as `X-API-Key` on hardware-route proxy calls.
- `nmtk/launcher_control/server.py` — Akida discovery probe now sends `X-API-Key` from `NEUROCHIP_HW_WORKER_API_KEY`; fixed matching stale comment.
- `Makefile` — `AKIDA_NATIVE ?= 0` flag: excludes port 8002 from the native-process eviction list, adds a preflight (`systemctl start neurochip.service` if inactive) and SSH-fetches the API token straight into the deploy env (never written to disk) when set.
- `scripts/remote_docker_compose_up.sh` — accepts `COMPOSE_FILE_ARGS` + `NEUROCHIP_HW_WORKER_API_KEY` env inputs, additive only (empty defaults reproduce the exact prior command).

## Usage
```
make docker-ex-m REMOTE_HOST=moosebun2@192.168.68.53 AKIDA_NATIVE=1
```
Omitting `AKIDA_NATIVE` (or `=0`) is byte-for-byte the old behavior — safe for boxes without a card.

## Verified locally
- `docker compose -f docker-compose.yml -f docker-compose.akida-native.yml config` — confirmed `ports:` cleared on `neurochip-hw-worker`, env overrides applied on `suite_api`/`launcher-control`, `extra_hosts` present.
- `python3 -m py_compile` on all touched Python files — passes.
- `make -n docker-ex-deploy ... AKIDA_NATIVE=1` vs without — confirmed port 8002 present in eviction list only when the flag is unset.
- `bash -n scripts/remote_docker_compose_up.sh` — passes.

## Not yet verified (needs the actual remote box)
- End-to-end deploy with `AKIDA_NATIVE=1` against moosebun2@192.168.68.53.
- `suite_api`'s proxied `/api/neurochip/akida/status` returning real (non-401, non-503) status through the full stack.
- Passwordless `sudo` availability on moosebun2 for `systemctl start neurochip.service` and `cat /opt/neurochip-akida-host/credentials/api-token` — assumed present per existing provisioning-script convention, not re-confirmed here.
