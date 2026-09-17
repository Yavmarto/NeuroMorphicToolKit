# Neurohub — Cloud Run deployment runbook

One-time setup to deploy the central Neurohub API. This is the only
Neurohub-side hosting needed: no database, no object storage, no cache, no
search index, and no separate frontend to host — Neurohub's UI ships inside
the main NMTK Flutter app, and GitHub itself is the only persistence layer.

---

## Prerequisites

- `gcloud` CLI authenticated (`gcloud auth login`)
- `docker` daemon running
- A GCP project created (note your `PROJECT_ID`) with billing enabled
- A GitHub OAuth App registered at github.com/settings/developers, with
  **Device Flow enabled** — note its **Client ID** (no client secret needed;
  Device Flow doesn't use one)

---

## Step 1 — Enable GCP APIs

```bash
gcloud services enable \
  run.googleapis.com \
  secretmanager.googleapis.com \
  artifactregistry.googleapis.com \
  --project=YOUR_PROJECT_ID
```

---

## Step 2 — Artifact Registry (Docker images)

```bash
gcloud artifacts repositories create neurohub \
  --repository-format=docker \
  --location=europe-west1 \
  --project=YOUR_PROJECT_ID
```

---

## Step 3 — Generate and load secrets

```bash
cd Neurohub
bash scripts/gen_secrets.sh
# Fill in GITHUB_OAUTH_CLIENT_ID in .env.prod

gcloud secrets create neurohub-secret-key --project=YOUR_PROJECT_ID
echo -n "$(grep NEUROHUB_SECRET_KEY .env.prod | cut -d= -f2)" | \
  gcloud secrets versions add neurohub-secret-key --data-file=-

gcloud secrets create neurohub-jwt-secret --project=YOUR_PROJECT_ID
echo -n "$(grep JWT_SECRET .env.prod | cut -d= -f2)" | \
  gcloud secrets versions add neurohub-jwt-secret --data-file=-
```

`NEUROHUB_SECRET_KEY` and `JWT_SECRET` are self-generated and never shared
with GitHub or anyone else. `GITHUB_OAUTH_CLIENT_ID` is public by design
(it's sent in every OAuth request URL), so it goes straight into
`infrastructure/cloud-run-service.yaml` as a plain value, not a secret.

---

## Step 4 — Edit the service manifest

```bash
sed -i '' 's/PROJECT_ID/YOUR_PROJECT_ID/g' infrastructure/cloud-run-service.yaml
sed -i '' 's/REGION/europe-west1/g' infrastructure/cloud-run-service.yaml
sed -i '' 's/REPLACE_WITH_GITHUB_OAUTH_APP_CLIENT_ID/YOUR_CLIENT_ID/' infrastructure/cloud-run-service.yaml
```

---

## Step 5 — Deploy

```bash
gcloud config set project YOUR_PROJECT_ID
bash scripts/deploy.sh
```

This builds the image, pushes it to Artifact Registry, deploys the Cloud Run
service, and prints its URL at the end — copy that URL.

---

## Step 6 — Point the Flutter app at it (one-time, not per-release)

Set `neurohubApiUrl`'s `defaultValue` in
`neurocnl/frontend/lib/config/app_config.dart` to the URL from Step 5. Every
subsequent `flutter build` release picks it up automatically — no
`--dart-define` flag to remember, no configuration step for the end user.

---

## Smoke test

```bash
BASE=https://YOUR_CLOUD_RUN_URL

curl "$BASE/health"                          # {"status":"ok"}, no auth needed
curl "$BASE/api/neurohub/oauth/config"       # your GitHub client_id + scopes
curl "$BASE/api/neurohub/oauth/health"       # GitHub reachability
curl -X POST "$BASE/api/neurohub/oauth/device/start"   # starts a real device flow
```

---

## Rollback

```bash
gcloud run revisions list --service=neurohub-api --region=europe-west1

gcloud run services update-traffic neurohub-api \
  --to-revisions=neurohub-api-REVISION=100 \
  --region=europe-west1
```

---

## Cost

| Service | Config | ≈Monthly |
|---|---|---|
| Cloud Run | scale-to-zero, 1 CPU / 512 Mi | $0 at idle, low single digits under light real use |
| Artifact Registry | image storage | ~$0 (small image, free tier covers it) |
| **Total** | | **effectively free for a small user base** |

No Cloud SQL, no Cloud Storage, no Memorystore, no Firebase — all removed
along with Supabase when this service moved to GitHub as its only
persistence layer.
