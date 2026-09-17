# Deployment Guide — neurocnl Studio

> **Frontend status:** the standalone Flutter application described in older
> sections below has been retired. NeuroStudio now ships only as an internal
> feature of `nmtk/neuro_toolkit`; use the root NMTK app for every supported
> desktop, mobile, or web build. Backend deployment guidance remains applicable.

Complete CI/CD and deployment guide for the FastAPI backend. The historical
standalone Flutter examples below are retained only as migration context.

Important: backend support verdicts and generator fidelity annotations improve deployment transparency, but they are not substitutes for direct vendor-toolchain or hardware validation. Real chip routing behavior, resource contention, and on-device timing still require access to the actual platform or developer program.

**Note on Hardware Support Claims**: Exporter presence does not imply production-ready hardware support. Some hardware backends currently produce export code only (Lava, SpiNNaker2, sinabs, rockpool, PYNQ), whereas others provide functional simulation paths (Nengo, Loihi sim-cfg). Always verify behavior on physical hardware for code-only targets. Additionally, rockpool export is currently non-functional due to unfixed bugs in the converter; sinabs export is limited to sequential topologies only; and the PYNQ FINN compilation stage is a Phase 2 placeholder not yet implemented.

---

## 1. Architecture Overview

```
                    ┌─────────────────────────┐
                    │     GitHub Actions       │
                    │  (CI: test + build)       │
                    └──────────┬──────────────┘
                               │
              ┌────────────────┼────────────────┐
              │                │                │
              ▼                ▼                ▼
  ┌───────────────────┐  ┌──────────────┐  ┌──────────────────┐
  │ Backend (FastAPI)  │  │ Flutter Web  │  │ Docker Compose   │
  │ Railway / Fly.io   │  │ Firebase     │  │ VPS (optional)   │
  │ Render / Cloud Run │  │ Vercel       │  │ self-hosted      │
  │                    │  │ Cloudflare   │  │                  │
  └───────────────────┘  └──────────────┘  └──────────────────┘
```

The backend and frontend can be deployed together (Docker Compose on a VPS) or separately (backend on a container platform, frontend on a static hosting CDN).

When you deploy Studio, users will now see backend support output in the validation flow:

- `faithful`: best current match for the selected backend
- `approximate`: usable with explicit caveats or heuristic lowering
- `unsupported`: parser/runtime may work upstream, but the selected backend cannot currently be claimed as supported

---

## 2. Local Development

### 2.1 Prerequisites

- Docker and Docker Compose
- Python 3.11+ (for running backend without Docker)
- Flutter 3.2+ (for running frontend without Docker)

### 2.2 Run Everything with Docker Compose

```bash
# Clone the repository
git clone https://github.com/Yavmarto/neurocnl.git
cd neurocnl

# Start both services
docker compose up --build

# The app is now running:
# - Frontend: http://localhost:3000
# - Backend API: http://localhost:8000
# - API docs: http://localhost:8000/docs
```

### 2.3 Development Mode (Hot Reload)

```bash
# Use the development compose file for hot reload on the backend
docker compose -f docker-compose.dev.yml up --build
```

The development compose file mounts the source directories as volumes, so changes to `backend/app/` and `neurocnl/` are reflected immediately (uvicorn reloads automatically).

For Flutter web development with hot reload:

```bash
cd frontend
flutter pub get
flutter run -d chrome --web-port 3000
```

### 2.4 Run Backend Only (No Docker)

```bash
cd backend
pip install -r requirements.txt
pip install -e ..  # Install the neurocnl library from the repo root

uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

### 2.5 Run Frontend Only (No Docker)

```bash
cd frontend
flutter pub get
flutter run -d chrome
```

Configure the API URL via an environment variable or compile-time define:

```bash
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000
```

---

## 3. CI/CD Pipeline

### 3.1 CI Workflow (`.github/workflows/ci.yml`)

Triggered on every push and pull request to `main` and `dev`:

```yaml
name: CI

on:
  push:
    branches: [main, dev]
  pull_request:
    branches: [main, dev]

jobs:
  # ─── Backend Tests ─────────────────────────────────────────
  backend-test:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-python@v5
        with:
          python-version: "3.11"
          cache: pip

      - name: Install dependencies
        run: |
          pip install -r backend/requirements.txt
          pip install -e .

      - name: Run neurocnl library tests
        run: python -m pytest neurocnl/ -v -p no:nengo

      - name: Run backend API tests
        run: python -m pytest backend/tests/ -v

      - name: Lint backend
        run: |
          pip install ruff
          ruff check backend/ neurocnl/

  # ─── Frontend Tests ────────────────────────────────────────
  frontend-test:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v4

      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          cache: true

      - name: Install dependencies
        working-directory: frontend
        run: flutter pub get

      - name: Analyze code
        working-directory: frontend
        run: flutter analyze

      - name: Run tests
        working-directory: frontend
        run: flutter test

  # ─── Docker Build Verification ─────────────────────────────
  docker-build:
    runs-on: self-hosted
    needs: [backend-test, frontend-test]
    steps:
      - uses: actions/checkout@v4

      - name: Build Docker images
        run: docker compose build

      - name: Verify containers start
        run: |
          docker compose up -d
          sleep 10
          curl -f http://localhost:8000/docs || exit 1
          docker compose down
```

### 3.2 Deploy Workflow (`.github/workflows/deploy.yml`)

Triggered on push to `main` only (i.e., after merge):

```yaml
name: Deploy

on:
  push:
    branches: [main]

env:
  REGISTRY: ghcr.io
  BACKEND_IMAGE: ghcr.io/${{ github.repository }}/backend
  API_BASE_URL: https://api.neurocnl-studio.example.com

jobs:
  # ─── Build and Push Backend Docker Image ────────────────────
  deploy-backend:
    runs-on: self-hosted
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@v4

      - name: Log in to Container Registry
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build and push backend image
        uses: docker/build-push-action@v5
        with:
          context: .
          file: backend/Dockerfile
          push: true
          tags: ${{ env.BACKEND_IMAGE }}:latest,${{ env.BACKEND_IMAGE }}:${{ github.sha }}

      # Uncomment the deployment target you are using:

      # ── Option A: Railway ──
      # - name: Deploy to Railway
      #   uses: bervProject/railway-deploy@main
      #   with:
      #     railway_token: ${{ secrets.RAILWAY_TOKEN }}
      #     service: backend

      # ── Option B: Fly.io ──
      # - name: Deploy to Fly.io
      #   uses: superfly/flyctl-actions/setup-flyctl@master
      # - run: flyctl deploy --image ${{ env.BACKEND_IMAGE }}:${{ github.sha }}
      #   env:
      #     FLY_API_TOKEN: ${{ secrets.FLY_API_TOKEN }}

      # ── Option C: Google Cloud Run ──
      # - uses: google-github-actions/auth@v2
      #   with:
      #     credentials_json: ${{ secrets.GCP_SA_KEY }}
      # - name: Deploy to Cloud Run
      #   uses: google-github-actions/deploy-cloudrun@v2
      #   with:
      #     service: neurocnl-backend
      #     image: ${{ env.BACKEND_IMAGE }}:${{ github.sha }}
      #     region: europe-west4

  # ─── Build and Deploy Frontend ──────────────────────────────
  deploy-frontend:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v4

      - uses: subosito/flutter-action@v2
        with:
          channel: stable

      - name: Build Flutter web
        working-directory: frontend
        run: |
          flutter pub get
          flutter build web --release --web-renderer canvaskit \
            --dart-define=API_BASE_URL=${{ env.API_BASE_URL }}

      # Uncomment the deployment target you are using:

      # ── Option A: Firebase Hosting ──
      # - uses: FirebaseExtended/action-hosting-deploy@v0
      #   with:
      #     repoToken: ${{ secrets.GITHUB_TOKEN }}
      #     firebaseServiceAccount: ${{ secrets.FIREBASE_SERVICE_ACCOUNT }}
      #     channelId: live
      #     projectId: neurocnl-studio

      # ── Option B: Vercel ──
      # - uses: amondnet/vercel-action@v25
      #   with:
      #     vercel-token: ${{ secrets.VERCEL_TOKEN }}
      #     vercel-org-id: ${{ secrets.VERCEL_ORG_ID }}
      #     vercel-project-id: ${{ secrets.VERCEL_PROJECT_ID }}
      #     working-directory: frontend/build/web

      # ── Option C: Cloudflare Pages ──
      # - name: Deploy to Cloudflare Pages
      #   uses: cloudflare/pages-action@v1
      #   with:
      #     apiToken: ${{ secrets.CLOUDFLARE_API_TOKEN }}
      #     accountId: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
      #     projectName: neurocnl-studio
      #     directory: frontend/build/web
```

---

## 4. Where to Deploy

### 4.1 Backend Deployment Options

The backend requires a Python runtime with Nengo and its dependencies. It cannot be deployed as a static site.

| Platform | Free Tier | Notes | Best For |
|---|---|---|---|
| **Railway** | $5/month trial credit | Container deployment, automatic HTTPS, environment variables, PostgreSQL if needed later | Quick deployment, low maintenance |
| **Fly.io** | Free for small apps | Deploys Docker containers, edge routing, auto-scaling, eu-west region available | Low-latency for European users |
| **Render** | Free tier (spins down) | Docker support, automatic deploys from GitHub, free TLS | Budget-friendly demos |
| **Google Cloud Run** | Free tier (2M requests) | Serverless containers, scale-to-zero, europe-west4 (Netherlands) | Production-grade, pay-per-use |
| **VPS (Hetzner/DigitalOcean)** | From 4 EUR/month | Full control, Docker Compose, persistent | Self-managed, max flexibility |

**Recommended for portfolio demos:** Railway or Fly.io — both support Docker containers with minimal configuration and have generous free tiers.

**Recommended for production:** Google Cloud Run with europe-west4 region — scale-to-zero means zero cost when idle, auto-scales for workshop demos.

### 4.2 Frontend Deployment Options

The Flutter web build produces static files (`build/web/`) that can be served from any static hosting CDN.

| Platform | Free Tier | Notes | Best For |
|---|---|---|---|
| **Firebase Hosting** | Generous free tier | Google CDN, automatic HTTPS, preview channels for PRs | Flutter ecosystem integration |
| **Vercel** | Free for personal | Edge network, automatic deploys, preview deployments | Fast iteration |
| **Cloudflare Pages** | Free (unlimited) | Global CDN, fast, no bandwidth limits | Production-grade, zero cost |
| **GitHub Pages** | Free | Simple, from the repo | Minimal demos |
| **Nginx on same VPS** | Included with VPS | Same server as backend, Docker Compose handles everything | Self-hosted simplicity |

**Recommended for portfolio demos:** Firebase Hosting or Cloudflare Pages — both are free and integrate with GitHub Actions.

**Recommended for self-hosted:** Nginx in Docker Compose (already configured in `docker-compose.yml`) — zero additional cost, backend and frontend on the same server.

### 4.3 Combined Deployment (Docker Compose on VPS)

For the simplest deployment (and for local demos), both services run together:

```bash
# On your VPS (e.g., Hetzner Cloud, DigitalOcean Droplet)
git clone https://github.com/Yavmarto/neurocnl.git
cd neurocnl
docker compose up -d --build
```

Add a reverse proxy (Caddy or Traefik) for automatic HTTPS:

```bash
# Caddyfile (example)
neurocnl-studio.example.com {
    handle /api/* {
        reverse_proxy backend:8000
    }
    handle {
        reverse_proxy frontend:80
    }
}
```

---

## 5. Environment Variables

### 5.1 Backend

| Variable | Default | Description |
|---|---|---|
| `MAX_SIMULATION_DURATION` | `10` | Maximum allowed simulation duration in seconds. Prevents DoS via long simulations. |
| `CORS_ORIGINS` | `http://localhost:3000` | Comma-separated list of allowed origins. Set to the frontend URL in production. |
| `LOG_LEVEL` | `info` | Logging level (debug, info, warning, error). |
| `WORKERS` | `1` | Number of uvicorn worker processes. Increase for production. |

### 5.2 Frontend (Compile-Time)

| Variable | Default | Description |
|---|---|---|
| `API_BASE_URL` | `http://localhost:8000` | Base URL for the backend API. Set during `flutter build web` via `--dart-define`. |

---

## 6. Setting Up a New Deployment

### 6.1 Railway (Backend)

1. Sign up at [railway.app](https://railway.app)
2. Connect your GitHub repository
3. Set the root directory to the repo root (Railway needs `backend/Dockerfile` and the neurocnl source)
4. Set the Dockerfile path to `backend/Dockerfile`
5. Add environment variables:
   - `MAX_SIMULATION_DURATION=10`
   - `CORS_ORIGINS=https://your-frontend-url.web.app`
6. Deploy — Railway assigns a public URL (e.g., `backend-production-xxxx.up.railway.app`)
7. Note the URL for the frontend build

### 6.2 Firebase Hosting (Frontend)

1. Install Firebase CLI: `npm install -g firebase-tools`
2. Log in: `firebase login`
3. Initialise in the `frontend/` directory:
   ```bash
   cd frontend
   firebase init hosting
   # Set public directory to: build/web
   # Configure as SPA: Yes
   # Set up automatic builds: No (GitHub Actions handles this)
   ```
4. Build with the backend URL:
   ```bash
   flutter build web --release --web-renderer canvaskit \
     --dart-define=API_BASE_URL=https://backend-production-xxxx.up.railway.app
   ```
5. Deploy:
   ```bash
   firebase deploy --only hosting
   ```
6. Add the Firebase Hosting URL to the backend's `CORS_ORIGINS` environment variable.

### 6.3 GitHub Actions Secrets

For automated CI/CD, add these secrets to your GitHub repository settings:

| Secret | Purpose | Needed For |
|---|---|---|
| `RAILWAY_TOKEN` | Railway API token | Railway deployment |
| `FLY_API_TOKEN` | Fly.io API token | Fly.io deployment |
| `FIREBASE_SERVICE_ACCOUNT` | Firebase service account JSON | Firebase Hosting |
| `VERCEL_TOKEN` | Vercel API token | Vercel deployment |
| `VERCEL_ORG_ID` | Vercel organisation ID | Vercel deployment |
| `VERCEL_PROJECT_ID` | Vercel project ID | Vercel deployment |
| `GCP_SA_KEY` | Google Cloud service account JSON | Cloud Run deployment |
| `CLOUDFLARE_API_TOKEN` | Cloudflare API token | Cloudflare Pages |
| `CLOUDFLARE_ACCOUNT_ID` | Cloudflare account ID | Cloudflare Pages |

Only add the secrets for the platform(s) you choose. The deploy workflow has all options commented out — uncomment the one you use.

---

## 7. Domain and HTTPS

### 7.1 Custom Domain

For a professional portfolio demo, point a custom domain at your deployment:

- **Frontend:** `neurocnl-studio.yourdomain.com` (or `studio.neurocnl.dev`)
- **Backend API:** `api.neurocnl-studio.yourdomain.com`

Most hosting platforms (Firebase, Vercel, Cloudflare, Railway) support custom domains with automatic HTTPS.

### 7.2 HTTPS

All recommended platforms provide automatic TLS certificates. If self-hosting on a VPS, use Caddy (automatic Let's Encrypt) or certbot with Nginx.

---

## 8. Monitoring and Health Checks

### 8.1 Backend Health Endpoint

The FastAPI app exposes a `/health` endpoint:

```python
@app.get("/health")
def health():
    return {"status": "ok", "version": "0.1.0"}
```

Use this for:
- Container orchestrator health checks (Docker, Railway, Cloud Run)
- Uptime monitoring (UptimeRobot, Better Uptime — both free)

### 8.2 Frontend Monitoring

Flutter web apps are static files — if the CDN is up, the app is up. Monitor the backend health endpoint to detect API outages.

---

## 9. Cost Summary

| Component | Platform | Estimated Cost |
|---|---|---|
| Backend | Railway free tier / Fly.io free tier | $0/month |
| Frontend | Firebase Hosting / Cloudflare Pages | $0/month |
| Domain | Optional (.dev or .com) | ~$12/year |
| CI/CD | GitHub Actions (free for public repos) | $0/month |
| **Total** | | **$0-1/month** |

For a portfolio demo with low traffic, the total cost is effectively zero.

---

## 10. Checklist: First Deployment

- [ ] Backend and frontend code is complete and tests pass locally
- [ ] `docker compose up --build` works and the app loads at `http://localhost:3000`
- [ ] Choose a backend platform (Railway / Fly.io / Cloud Run)
- [ ] Deploy the backend and note the public URL
- [ ] Build the Flutter web app with the backend URL
- [ ] Choose a frontend platform (Firebase / Vercel / Cloudflare Pages)
- [ ] Deploy the frontend
- [ ] Add the frontend URL to the backend's `CORS_ORIGINS`
- [ ] Add the required GitHub Secrets for CI/CD
- [ ] Uncomment the appropriate deployment steps in `.github/workflows/deploy.yml`
- [ ] Push to `main` and verify the deploy workflow succeeds
- [ ] Test the live app: load a template, run a simulation, verify plots render
- [ ] (Optional) Set up a custom domain and verify HTTPS
- [ ] (Optional) Set up uptime monitoring for the health endpoint
