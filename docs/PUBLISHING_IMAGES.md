# Publishing backend images to GHCR

The downloaded NMTK app sets up a server by **pulling prebuilt images**
(source-free), not by building on the server. For that to work, the backend
images must be published to GitHub Container Registry (GHCR) and be
**public** so a clean server can `docker compose ... pull` with no login.

- **Canonical registry path:** `ghcr.io/completed-spoon-6/neuromorphictoolkit/<service>`
  (the repo owner is `Completed-Spoon-6`; GHCR lowercases the path). This is
  what `docker-compose.prod.yml` pulls and what the release workflow pushes.
- **Tag:** `:latest` (the compose files pin `:latest`). Versioned
  `vX.Y.Z` / short-sha tags are also produced for pinning.
- **Architecture:** `linux/amd64` (the local-network servers are amd64). Do
  **not** publish arm64-only images from an Apple-Silicon Mac — they will not
  run on the servers.

## Services to publish (9)

| Service | Dockerfile | Notes |
|---|---|---|
| `suite-api` | `suite_api/Dockerfile` | |
| `neurosense-hw-worker` | `workers/neurosense_hw/Dockerfile` | |
| `neurobench-runner-worker` | `workers/neurobench_runner/Dockerfile` | |
| `neurochip-hw-worker` | `workers/neurochip_hw/Dockerfile` | |
| `neurocnl-physics-worker` | `workers/neurocnl_physics/Dockerfile` | build arg `INSTALL_PHYSICS=1` |
| `lava-backend` | `Dockerfile.lava` | |
| `launcher-control` | `Dockerfile.control` | |
| `jupyter-server` | `workers/jupyter_server/Dockerfile` | |
| `snn-mlir-compiler` | `workers/snn_mlir_compiler/Dockerfile` | dependency of suite_api/neurobench |

Monitoring services (`prometheus`, `loki`, `promtail`, `grafana`,
`alertmanager`) use public upstream images — nothing to publish.

## Option 1 — via CI (recommended, repeatable)

The workflow `.github/workflows/release-docker.yml` builds all nine for
`linux/amd64` and pushes `:latest` + version tags on any `v*` tag push:

```bash
git tag v0.1.0
git push origin v0.1.0
```

Watch the run in the repo's Actions tab. Then make the packages public
(see "Make packages public" below). This is the path to use for every
release.

## Option 2 — manual one-off build + push

Use when you need images published without cutting a release tag.

### 1. Log in to GHCR (you run this — needs a PAT with `write:packages`)

Create a classic Personal Access Token with `write:packages` (and
`read:packages`) at github.com → Settings → Developer settings → Tokens.

```bash
echo "$CR_PAT" | docker login ghcr.io -u <your-github-username> --password-stdin
```

### 2. Build + push each image (from the repo root, `linux/amd64`)

```bash
NS=ghcr.io/completed-spoon-6/neuromorphictoolkit

docker buildx build --platform linux/amd64 --push \
  -f suite_api/Dockerfile               -t $NS/suite-api:latest .
docker buildx build --platform linux/amd64 --push \
  -f workers/neurosense_hw/Dockerfile   -t $NS/neurosense-hw-worker:latest .
docker buildx build --platform linux/amd64 --push \
  -f workers/neurobench_runner/Dockerfile -t $NS/neurobench-runner-worker:latest .
docker buildx build --platform linux/amd64 --push \
  -f workers/neurochip_hw/Dockerfile    -t $NS/neurochip-hw-worker:latest .
docker buildx build --platform linux/amd64 --push \
  -f workers/neurocnl_physics/Dockerfile --build-arg INSTALL_PHYSICS=1 \
  -t $NS/neurocnl-physics-worker:latest .
docker buildx build --platform linux/amd64 --push \
  -f Dockerfile.lava                    -t $NS/lava-backend:latest .
docker buildx build --platform linux/amd64 --push \
  -f Dockerfile.control                 -t $NS/launcher-control:latest .
docker buildx build --platform linux/amd64 --push \
  -f workers/jupyter_server/Dockerfile  -t $NS/jupyter-server:latest .
docker buildx build --platform linux/amd64 --push \
  -f workers/snn_mlir_compiler/Dockerfile -t $NS/snn-mlir-compiler:latest .
```

> On an Apple-Silicon Mac, `--platform linux/amd64` builds via emulation
> (slower). Ensure `docker buildx` is available (`docker buildx version`).

## Make packages public (required for no-login pulls)

For each of the nine packages: github.com → org **Completed-Spoon-6** →
Packages → `<package>` → **Package settings** → **Change visibility** →
**Public**. (First publish of a package may default to private.)

## Verify (from a machine with no GHCR login)

```bash
docker logout ghcr.io
docker compose -f docker-compose.yml -f docker-compose.prod.yml pull
```

All nine first-party images should pull with no authentication. If any is
denied, its package is still private; recheck visibility.
