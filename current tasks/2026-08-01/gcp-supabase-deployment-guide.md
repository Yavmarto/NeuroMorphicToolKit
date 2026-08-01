# Deploying the centralized Neurohub registry (GCP Cloud Run + Supabase)

Goal: one running instance of the Neurohub backend, reachable at a fixed public
URL, backed by your Supabase project. This is the **one shared hub** every
user's app talks to for sharing/discovery — separate from whatever private
backend an individual user deploys for their own notebook/NeuroSense/NeuroChip
work.

Do these in order: **Supabase first** (you need its values before configuring
GCP), then **GCP**, then **wire the app**, then **verify**.

Placeholders used below — replace with your real values as you go:
- `PROJECT_ID` — your GCP project id (you'll create this)
- `PROJECT_REF` — your Supabase project ref. Yours is already live:
  `zpnuypxtfdfrmjasqvcn` (from `frontend/lib/main.dart`'s hardcoded default)
- `REGION` — `europe-west1` (already the default in `cloudbuild.yaml`; change
  both places together if you pick a different region)

---

## Part 1 — Supabase side

You said this project already exists (free tier). These steps assume it does;
skip project creation itself.

### 1.1 Get the database connection string

1. Supabase Dashboard → your project → **Project Settings → Database**.
2. Under **Connection string**, select **Session** mode (not "Transaction" —
   Neurohub is a long-running process, not serverless-per-request; Transaction
   pooling conflicts with SQLAlchemy's own connection pooling).
3. Copy the URI. It looks like:
   ```
   postgresql://postgres.PROJECT_REF:[YOUR-PASSWORD]@aws-0-REGION.pooler.supabase.com:5432/postgres
   ```
4. Replace `[YOUR-PASSWORD]` with your actual database password (Project
   Settings → Database → reset if you don't have it saved).
5. Prefix the scheme with `+psycopg2` so SQLAlchemy uses the right driver:
   ```
   postgresql+psycopg2://postgres.PROJECT_REF:YOUR-PASSWORD@aws-0-REGION.pooler.supabase.com:5432/postgres
   ```
   This full string is your `NEUROHUB_DB_URL`. Keep it somewhere private —
   you'll paste it into GCP Secret Manager in Part 2, never into a file that
   gets committed.

### 1.2 Create the Storage bucket

1. Dashboard → **Storage → Create a new bucket**.
2. Name: `neurohub-assets` (must match `OBJECT_STORAGE_BUCKET` — already set
   in `infrastructure/cloud-run-service.yaml`).
3. Visibility: **Private** (the backend hands out presigned URLs for
   downloads; nothing needs public bucket access).

### 1.3 Get S3-compatible access keys for that bucket

1. Dashboard → **Storage → S3 Access Keys → New access key**.
2. Copy the **Access Key ID** and **Secret Access Key** — these become
   `OBJECT_STORAGE_ACCESS_KEY` / `OBJECT_STORAGE_SECRET_KEY`.
3. Note the endpoint format for later: `https://PROJECT_REF.supabase.co/storage/v1/s3`
   (already set in `cloud-run-service.yaml`, just confirm your `PROJECT_REF`
   matches).

### 1.4 Confirm JWT signing mode (already checked once, re-confirm if needed)

Run:
```bash
curl -s https://PROJECT_REF.supabase.co/auth/v1/.well-known/jwks.json
```
A non-empty `"keys"` array (already confirmed live for your project) means
you're on JWKS/asymmetric signing — the backend's `supabase_auth_service.py`
handles this automatically, no `SUPABASE_JWT_SECRET` needed. If this ever
returns an empty array, you're on legacy HS256 — get the shared secret from
Dashboard → Project Settings → API → JWT Secret and set
`SUPABASE_JWT_SECRET` instead (see `.env.supabase.example`).

### 1.5 (Optional) Bootstrap yourself as admin

Once you've signed up once through the app (so a Supabase `auth.users` row
exists for your email), run in the Supabase SQL Editor:
```sql
UPDATE auth.users
SET raw_app_meta_data = raw_app_meta_data || '{"role": "admin"}'
WHERE email = 'your-email@example.com';
```
Your next sign-in will carry `app_metadata.role="admin"`, giving your registry
account admin rights (can delete/moderate any artefact, not just your own).

**You now have 3 values from Supabase**: `NEUROHUB_DB_URL`,
`OBJECT_STORAGE_ACCESS_KEY`, `OBJECT_STORAGE_SECRET_KEY`. Keep them handy for
Part 2.4.

---

## Part 2 — GCP side

### 2.1 Install the CLI and create the project

```bash
# Install gcloud if you don't have it: https://cloud.google.com/sdk/docs/install
gcloud auth login
gcloud projects create PROJECT_ID --name="Neurohub Hub"
gcloud config set project PROJECT_ID
```
Link a billing account to the project (Console → Billing) — required even to
use free-tier services, but you won't be charged while staying inside Cloud
Run's free tier (2M requests/month, scale-to-zero).

### 2.2 Enable the APIs you need

```bash
gcloud services enable \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  secretmanager.googleapis.com \
  iam.googleapis.com
```

### 2.3 Create the Artifact Registry repo (holds the built Docker image)

```bash
gcloud artifacts repositories create neurohub \
  --repository-format=docker \
  --location=REGION \
  --description="Neurohub backend images"
```

### 2.4 Create the secrets

Generate two random secrets for the backend's own JWT signing (these are
NOT Supabase values — they're for the legacy `internal` auth mode, which
`_validate_startup_config` still requires to be set in production even
though you'll run in `supabase` mode):
```bash
python3 -c "import secrets; print(secrets.token_hex(32))"   # run twice
```

Now create every secret (paste real values when prompted — using
`--data-file=-` reads from stdin so the value never appears in your shell
history):
```bash
echo -n "postgresql+psycopg2://postgres.PROJECT_REF:YOUR-PASSWORD@aws-0-REGION.pooler.supabase.com:5432/postgres" | \
  gcloud secrets create neurohub-db-url --data-file=-

echo -n "PASTE_FIRST_GENERATED_SECRET" | \
  gcloud secrets create neurohub-secret-key --data-file=-

echo -n "PASTE_SECOND_GENERATED_SECRET" | \
  gcloud secrets create neurohub-jwt-secret --data-file=-

echo -n "PASTE_SUPABASE_S3_ACCESS_KEY" | \
  gcloud secrets create supabase-s3-access-key --data-file=-

echo -n "PASTE_SUPABASE_S3_SECRET_KEY" | \
  gcloud secrets create supabase-s3-secret-key --data-file=-
```

(`firebase-ci-token` is only needed if you do Part 2.8's optional web hosting
step — covered there.)

### 2.5 Create the service account and grant it access

```bash
gcloud iam service-accounts create neurohub-api \
  --display-name="Neurohub API runtime"

# Let it read the secrets you just created:
for SECRET in neurohub-db-url neurohub-secret-key neurohub-jwt-secret \
              supabase-s3-access-key supabase-s3-secret-key; do
  gcloud secrets add-iam-policy-binding $SECRET \
    --member="serviceAccount:neurohub-api@PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/secretmanager.secretAccessor"
done
```

### 2.6 Edit `infrastructure/cloud-run-service.yaml`

This file is already written for this exact setup — just replace the
placeholders in it:
- `PROJECT_ID` → your project id (2 occurrences: image path, service account)
- `REGION` → your region (1 occurrence: image path)
- `YOUR_PROJECT_REF` → your Supabase project ref (2 occurrences: `SUPABASE_URL`,
  `OBJECT_STORAGE_URL`)
- `https://neurohub.your-domain.com` in `ALLOWED_ORIGINS` → the domain(s) your
  Flutter web build (if any) will be served from, or your Cloud Run URL once
  known (you can leave this and revisit after first deploy)

### 2.7 First deploy (manual — do this once before wiring up CI)

Build and push the image:
```bash
cd Neurohub
gcloud builds submit --tag REGION-docker.pkg.dev/PROJECT_ID/neurohub/neurohub-api:latest .
```

Create the one-off migration job (only needed once; `cloudbuild.yaml`'s
`run-migrations` step re-executes it on every future deploy):
```bash
gcloud run jobs create neurohub-migrate \
  --image=REGION-docker.pkg.dev/PROJECT_ID/neurohub/neurohub-api:latest \
  --region=REGION \
  --service-account=neurohub-api@PROJECT_ID.iam.gserviceaccount.com \
  --set-secrets=NEUROHUB_DB_URL=neurohub-db-url:latest \
  --command=alembic --args=upgrade,head
```
Run it once to create the schema:
```bash
gcloud run jobs execute neurohub-migrate --region=REGION --wait
```

Deploy the service using your filled-in `cloud-run-service.yaml`:
```bash
gcloud run services replace infrastructure/cloud-run-service.yaml --region=REGION
```

Allow the service to actually receive traffic (the yaml doesn't set this —
`cloudbuild.yaml`'s later deploys use `--no-allow-unauthenticated` assuming a
Firebase Hosting proxy in front; if you're **not** using Part 2.8's optional
web hosting, allow public access directly instead so the app can reach it):
```bash
gcloud run services add-iam-policy-binding neurohub-api \
  --region=REGION \
  --member="allUsers" \
  --role="roles/run.invoker"
```

Get your public URL:
```bash
gcloud run services describe neurohub-api --region=REGION --format="value(status.url)"
```
This URL is what goes into Part 3.

### 2.8 (Optional) Web hosting via Firebase Hosting

Only needed if you also want a browser-based version of the app (the desktop
macOS app doesn't need this — it talks to the Cloud Run URL directly). Skip
this whole section if you only care about the desktop app for now.

```bash
npm install -g firebase-tools
firebase login
firebase use --add PROJECT_ID   # pick "default" as the alias
```
`firebase.json` (already in the repo) proxies `/api/**` to your `neurohub-api`
Cloud Run service and serves everything else as the Flutter web build. Update
its `region` field if you didn't use `europe-west1`. Then:
```bash
cd frontend
flutter build web --release \
  --dart-define=SUPABASE_URL=https://PROJECT_REF.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key \
  --dart-define=NEUROHUB_REGISTRY_URL=https://YOUR_CLOUD_RUN_URL
cd ..
firebase deploy --only hosting
```
For CI (`cloudbuild.yaml`'s `deploy-hosting` step), generate a CI token once
and store it:
```bash
firebase login:ci   # prints a token
echo -n "PASTED_TOKEN" | gcloud secrets create firebase-ci-token --data-file=-
```

### 2.9 (Optional) Wire up automatic deploys on push

`cloudbuild.yaml` already exists and does the build/migrate/deploy sequence.
To run it automatically on push, connect your repo in Console → Cloud Build →
Triggers → Create Trigger, pointing at this `cloudbuild.yaml`, with
substitution `_REGION`/`_REPO` matching what you used above. Until you set
this up, you can always trigger it manually:
```bash
gcloud builds submit --config=Neurohub/cloudbuild.yaml Neurohub
```

---

## Part 3 — Wire the Flutter app at the deployed hub

The app needs to know the Cloud Run URL from Part 2.7. Two ways:

**A. Rebuild with a dart-define** (no source change, do this per-build):
```bash
flutter run -d macos --dart-define=NEUROHUB_REGISTRY_URL=https://YOUR_CLOUD_RUN_URL
```

**B. Bake it in as the default** (so nobody has to remember the flag) — edit
`Neurohub/frontend/lib/services/api_service.dart`, replace
`https://REPLACE_WITH_DEPLOYED_NEUROHUB_REGISTRY_URL` with your real Cloud Run
URL in the `registryBaseUrl` default, commit that.

Recommend **B** once the URL is stable — matches how `SUPABASE_URL` is already
baked into `main.dart` as a default.

---

## Part 4 — Verify end to end

1. Health check (should return `200` with a JSON body):
   ```bash
   curl https://YOUR_CLOUD_RUN_URL/api/v1/health
   ```
2. Run the app, sign up with a real email through the existing Supabase login
   screen.
3. Share something (Share to Hub screen) — fill Slug/Version/Description,
   pick a file, submit.
4. Check Feed and My Shares both show it — confirms all three screens are
   reading the same centralized data, not three separate silos.
5. From another device/account, confirm the same shared item is visible in
   its Feed too — this is the actual "centralized for everyone" check.

---

## Notes / known gaps carried over from the code work

- `NEUROHUB_AUTH_ENABLED=true` and `ENVIRONMENT=production` must both be set
  (already in `cloud-run-service.yaml`) — the backend refuses to start in
  production without them, by design (`_validate_startup_config`).
- Refresh-token exchange (`POST /api/v1/auth/refresh`) runs in stateless mode
  without a `CACHE_URL` (no Redis configured) — acceptable for now; only
  matters if something other than Supabase's own session refresh is relying
  on that specific endpoint (the Flutter app uses Supabase's own SDK-managed
  refresh, not this endpoint, so this shouldn't matter today).
- Custom-node and benchmark-result "publish to hub" buttons don't exist yet in
  NeuroSim/neurocnl/Neurobench's own screens — those are separate, unstarted
  pieces of work (see the other task file in this folder).
