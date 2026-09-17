# Server-side dataset cache (Firebase Storage)

NeuroStudio downloads neuromorphic datasets from a **public** Firebase Storage bucket into the neurocnl **backend** cache. The Flutter **Setup** pipeline step now discovers dataset folders and files live from Firebase and shows whether each selectable dataset file is already on the server.

No Firebase credentials are stored in the app or frontend — only the backend needs the bucket name.

---

## 1. Firebase Console (one-time)

1. Open [Firebase Console](https://console.firebase.google.com/) → your project → **Storage**.
2. Upload dataset files under first-level folders such as `Davis 24/` or `DND21/`.
3. Add a `description.txt` file inside each top-level folder. Its text becomes the dataset-card description in Setup.
4. Put supported dataset files directly inside that folder. Supported selectable file extensions are:
   - `.aedat`
   - `.aedat4`
   - `.h5`
   - `.hdf5`
   - `.bin`
5. Optional archive or helper files such as `.7z` can live in the same folder. They are hidden from selection in Setup, but the backend mirrors the whole folder to the local cache when one selectable file is downloaded. Companion archives (`.zip`, `.tar`, `.tar.gz`, `.tgz`, `.7z`, `.rar`, and variants) are automatically extracted alongside the selected file after the folder download completes. Extraction is best-effort: a broken or unsupported companion archive never prevents the selected dataset from becoming ready.
6. Make objects **publicly readable** (read-only):
   - **Rules** tab (for development / public datasets):

     ```text
     rules_version = '2';
     service firebase.storage {
       match /b/{bucket}/o/{object=**} {
         allow read: if true;
         allow write: if false;
       }
     }
     ```

   - Or grant public read on individual objects via the object permissions UI.

7. Note your **bucket name** from the Storage page. It usually looks like:
   - `your-project-id.appspot.com`, or
   - `your-project-id.firebasestorage.app`

   You do **not** need a service account JSON for this integration (public bucket).

---

## 2. Discovery rules

The backend uses the live Firebase JSON listing API. No repo-side catalog editing is required for normal Setup behavior when `NEUROCNL_FIREBASE_BUCKET` is configured.

Setup behavior:

- Each supported file inside a top-level folder becomes one selectable dataset entry.
- The entry title is the filename.
- The entry description comes from the folder’s `description.txt`.
- The folder name is shown on the card so users can tell which bucket folder the file belongs to.

The bundled [`backend/assets/datasets/catalog.json`](../backend/assets/datasets/catalog.json) remains as an offline fallback when no Firebase bucket is configured.

---

## 3. Backend environment variables

Set on the machine or container running the neurocnl backend:

| Variable | Required | Description |
|----------|----------|-------------|
| `NEUROCNL_FIREBASE_BUCKET` | **Yes** (for downloads) | Public bucket name from step 1 |
| `NEUROCNL_DATA_DIR` | No | Where cache + SQLite registry live (default: process cwd) |
| `NEUROCNL_DATASET_SYNC_MAX_BYTES` | No | Max size for synchronous download (default: 50 MB) |

### Local shell

```bash
export NEUROCNL_FIREBASE_BUCKET=your-project-id.appspot.com
export NEUROCNL_DATA_DIR=/var/lib/neurocnl   # optional
# restart neurocnl backend
```

### Docker Compose

In [`docker-compose.yml`](../docker-compose.yml) or a `.env` file next to it:

```bash
NEUROCNL_FIREBASE_BUCKET=your-project-id.appspot.com
```

The compose file already mounts volume `neurocnl_data` at `/data` with `NEUROCNL_DATA_DIR=/data`.

### Suite / `make dev`

If neurocnl runs via the root launcher, set `NEUROCNL_FIREBASE_BUCKET` in the environment for the neurocnl backend process (same as other module env vars in your compose or launch script).

---

## 4. Where files land on the server

| Path | Contents |
|------|----------|
| `$NEUROCNL_DATA_DIR/datasets/<folder>/` | Downloaded dataset folders mirrored from Firebase |
| `$NEUROCNL_DATA_DIR/datasets.db` | Registry (remembers what is already downloaded) |

Re-selecting a cached dataset does not re-download unless the file was removed from disk.

---

## 5. API

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/datasets` | Catalog + per-dataset `status` |
| GET | `/api/datasets/{id}` | Single dataset status |
| POST | `/api/datasets/{id}/download` | Download to server (200 if cached/small; 202 + `job_id` if large) |

Poll `GET /api/jobs/{job_id}` when download returns 202. Repeated `POST /download` calls while the same dataset is already downloading return 202 with the **same** `job_id` — no duplicate download is started. The backend job timeout is 3600 s; the Flutter client polls for up to 60 minutes at a 2-second cadence so large transfers over slow connections succeed.

---

## 6. Troubleshooting

| Symptom | Fix |
|---------|-----|
| Setup shows “Firebase Storage is not configured” | Set `NEUROCNL_FIREBASE_BUCKET` and restart backend |
| Download 404 | `storage_path` in catalog does not match object key in bucket |
| Download 503 / network error | Bucket not public, wrong bucket name, or object missing |
| Integrity 409 | Update `content_sha256` in catalog or re-upload object |
| Dataset stuck in "Downloading" after restart | The download job did not complete; re-trigger the download from Setup — the client returns the same job_id if already active, or starts fresh if the prior job is gone |
| Companion archive not extracted | `bsdtar` may be missing for `.7z` / `.rar` companions — install it on the server; `.zip` / tar variants are always extracted in-process |

The Flutter app does **not** read Firebase config — it only talks to the neurocnl backend API.
