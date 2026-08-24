# Workers

Isolated processes for hardware I/O and long-running compute. Everything not listed here runs in-process inside the single `suite_api` container.

| Directory | Compose service | Port | Starts by default | What it owns |
| --- | --- | --- | --- | --- |
| `neurochip_hw/` | `neurochip-hw-worker` | 8002 | yes | `/api/neurochip` prefixes `akida`, `hardware/lava`, `hardware/speck`, `hardware/pynq`, `serial` |
| `neurobench_runner/` | `neurobench-runner-worker` | 8003 | yes | all of `/api/neurobench` |
| `neurosense_hw/` | `neurosense-hw-worker` | 8004 | **no** — profile `neurosense` | recording, sessions, export, devices, stream, sense |
| `neurocnl_physics/` | `neurocnl-physics-worker` | 8006 | yes | the MuJoCo route of `/api/neurocnl` |
| `snn_mlir_compiler/` | `snn-mlir-compiler` | 8007 | yes | MLIR compilation |
| `jupyter_server/` | `jupyter-server` | 8008 | yes | JupyterLab and its nine kernels |
| `lava_backend/` | `lava-backend` | 8012 | yes | Lava simulation backend |

`neurosense-hw-worker` is the only profile-gated service, in both `docker-compose.yml` and `docker-compose.prod.yml`. Every other worker starts on a plain `docker compose up`, including the hardware workers whose hardware is usually absent — they come up and report unavailable rather than being skipped.

Proxied routes return HTTP 503 while their worker is not running. See the [root README](../README.md#architecture) for how the workers sit relative to `suite_api`.

## Notes on individual workers

- `neurobench_runner/` is a thin re-host, not its own service: `main.py` injects `Neurobench/neurobench` onto `sys.path` and re-exports that app.
- `jupyter_server/` is a JupyterLab container rather than a FastAPI app — it has no `main.py`. Its kernels are provisioned unconditionally at startup: `Python (NeuroStudio)` plus snnTorch, Nengo, Rockpool, Sinabs, Brian2, Lava, PyNN/SpiNNaker, and Akida. There is no separate PyTorch kernel; torch ships in the base image.
- `lava_backend/` has no `Dockerfile` even though `docker-compose.yml` defines a `lava-backend` service.

## License

GNU Affero General Public License v3.0 or later (AGPL-3.0-or-later). Each worker directory carries its own copy of [LICENSE](../LICENSE).
