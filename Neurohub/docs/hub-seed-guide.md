# Neurohub Hub Seed Guide

How to seed, verify, and reset the 10 first hub entries.

---

## What gets seeded

| # | Asset | Type | Source file |
|---|---|---|---|
| 1 | EMG Gripper Network | `cnl_spec` | `neurocnl/backend/app/templates/emg_gripper.cnl` |
| 2 | Audio Wake-Word Network | `cnl_spec` | `neurocnl/backend/app/templates/audio_wakeword.cnl` |
| 3 | EEG Attention Network | `cnl_spec` | `neurocnl/backend/app/templates/eeg_attention.cnl` |
| 4 | Object Recognition Network | `cnl_spec` | `neurocnl/backend/app/templates/object_recognition.cnl` |
| 5 | Looming Detector | `cnl_spec` | `neurocnl/backend/app/templates/looming_detector.cnl` |
| 6 | Visual Tracker | `cnl_spec` | `neurocnl/backend/app/templates/visual_tracker.cnl` |
| 7 | Reflex Arc | `cnl_spec` | `neurocnl/backend/app/templates/reflex_arc.cnl` |
| 8 | CPG Rhythm Generator | `cnl_spec` | `neurocnl/backend/app/templates/cpg_rhythm.cnl` |
| 9 | Prosthetic Reflex Network | `cnl_spec` | `neurocnl/backend/app/templates/prosthetic_reflex.cnl` |
| 10 | Slip Reflex Network | `cnl_spec` | `neurocnl/backend/app/templates/slip_reflex.cnl` |
| 11 | Dream Hand Reflex Arc | `cnl_spec` | `Neuro-Dream-Hand/cnl-specs/reflex_arc.cnl` |
| 12 | Dream Hand Sleep Arc | `cnl_spec` | `Neuro-Dream-Hand/cnl-specs/sleep_arc.cnl` |
| 13 | Grip Stability Benchmark | `benchmark_definition` | `Neurobench/neurobench/benchmarks/builtin/grip_stability.json` |
| 14 | Keyword Spotting Benchmark | `benchmark_definition` | `Neurobench/neurobench/benchmarks/builtin/keyword_spotting.json` |
| 15 | ECG Arrhythmia Classification | `benchmark_definition` | `Neurobench/neurobench/benchmarks/builtin/ecg_classification.json` |
| 16 | DVS Gesture Recognition | `benchmark_definition` | `Neurobench/neurobench/benchmarks/builtin/dvs_gesture.json` |
| 17 | Primate Motor Prediction | `benchmark_definition` | `Neurobench/neurobench/benchmarks/builtin/primate_reaching.json` |
| 18 | Mackey-Glass Prediction | `benchmark_definition` | `Neurobench/neurobench/benchmarks/builtin/mackey_glass.json` |
| 19 | Audio MFCC Rate Encoding | `encoding_preset` | _(generated inline)_ |
| 20 | Biomedical Delta Encoding | `encoding_preset` | _(generated inline)_ |

Plus **6 projects** that link the assets above via `ProjectLinks`:

| Project | CNL specs | Benchmark(s) |
|---|---|---|
| Prosthetic Grip Control Kit | emg-gripper | grip_stability |
| Audio Wake-Word Detection Kit | audio-wakeword | keyword_spotting |
| Biosignal Classification Kit | eeg-attention | ecg_classification |
| Event Vision Suite | object-recognition, looming-detector, visual-tracker | dvs_gesture |
| Motor Control Research Kit | reflex-arc, cpg-rhythm | primate_reaching, mackey_glass |
| Prosthetics Full Suite | emg-gripper, prosthetic-reflex, slip-reflex, dream-hand-* | grip_stability |

---

## Prerequisites

### 1. Install httpx (if not already present)

```bash
pip install httpx
# or, inside the Neurohub venv:
cd Neurohub && pip install -e ".[dev]"
```

### 2. Start Neurohub

Option A — NMTK launcher (recommended):
```bash
# Open the NMTK app and start the Neurohub module from the launcher UI
```

Option B — directly:
```bash
cd Neurohub
alembic upgrade head          # initialise DB if first run
uvicorn neurohub.app.main:app --host 127.0.0.1 --port 8005 --reload
```

Confirm it's up:
```bash
curl http://localhost:8005/health
# → {"status":"ok"}
```

> **Auth note:** `NEUROHUB_AUTH_ENABLED` defaults to `false`.  
> In this mode the server auto-authenticates every request as an admin — no token or API key needed.  
> If you have auth enabled, see [With auth enabled](#with-auth-enabled) below.

---

## Run the seed script

```bash
cd Neurohub
python scripts/seed_hub_entries.py
```

Expected output:
```
[1/4] Checking Neurohub at http://localhost:8005 …
  ✓ Server healthy

[2/4] Preparing assets (copying source files to shared_assets/) …
  Prepared 20 asset(s)

[3/4] Seeding assets …
  ✓ EMG Gripper Network
  ✓ Audio Wake-Word Network
  ✓ EEG Attention Network
  ✓ Object Recognition Network
  ✓ Looming Detector
  ✓ Visual Tracker
  ✓ Reflex Arc
  ✓ CPG Rhythm Generator
  ✓ Prosthetic Reflex Network
  ✓ Slip Reflex Network
  ⚠ Missing source: .../Neuro-Dream-Hand/cnl-specs/reflex_arc.cnl — skipping dream-hand-reflex
  ⚠ Missing source: .../Neuro-Dream-Hand/cnl-specs/sleep_arc.cnl  — skipping dream-hand-sleep
  ✓ Grip Stability Benchmark
  ✓ Keyword Spotting (MFCC-SNN)
  ✓ ECG Arrhythmia Classification
  ✓ DVS Gesture Recognition
  ✓ Primate Motor Prediction
  ✓ Mackey-Glass Chaotic Prediction
  ✓ Audio MFCC Rate Encoding
  ✓ Biomedical Delta Encoding

[4/4] Seeding projects …
  ✓ Prosthetic Grip Control Kit
  ✓ Audio Wake-Word Detection Kit
  ✓ Biosignal Classification Kit
  ✓ Event Vision Suite
  ✓ Motor Control Research Kit
  ✓ Prosthetics Full Suite

Done: 26/26 items OK
```

> The Dream Hand ⚠ warnings are expected if `Neuro-Dream-Hand/` is absent — all other entries still seed correctly.

Re-running is safe. Items that already exist print `↩ … (already exists — skipped)`.

---

## Verify with curl

### List all assets
```bash
curl http://localhost:8005/api/neurohub/assets | python3 -m json.tool | head -60
```

### Filter by type
```bash
# CNL specs only
curl "http://localhost:8005/api/neurohub/assets?type=cnl_spec" | python3 -m json.tool

# Benchmark definitions only
curl "http://localhost:8005/api/neurohub/assets?type=benchmark_definition" | python3 -m json.tool

# Encoding presets only
curl "http://localhost:8005/api/neurohub/assets?type=encoding_preset" | python3 -m json.tool
```

### Search by keyword
```bash
curl "http://localhost:8005/api/neurohub/assets?q=prosthetic" | python3 -m json.tool
curl "http://localhost:8005/api/neurohub/assets?q=dvs" | python3 -m json.tool
```

### Check a specific asset (use any ID from `a1000001-…` to `a3000002-…`)
```bash
curl http://localhost:8005/api/neurohub/assets/a1000001-0000-4000-8000-000000000001 | python3 -m json.tool
```

### Download an asset file
```bash
curl -o emg_gripper_downloaded.cnl \
  http://localhost:8005/api/neurohub/assets/a1000001-0000-4000-8000-000000000001/download
cat emg_gripper_downloaded.cnl
```

### List all projects
```bash
curl http://localhost:8005/api/neurohub/projects | python3 -m json.tool
```

### Check a specific project
```bash
curl http://localhost:8005/api/neurohub/projects/p1000001-0000-4000-8000-000000000001 | python3 -m json.tool
```

### Check the feed (shared asset activity)
```bash
curl http://localhost:8005/api/neurohub/feed | python3 -m json.tool
```

---

## Verify with the Neurohub UI

1. Open the Neurohub frontend (via NMTK launcher or `http://localhost:8005`)
2. Navigate to **My Shares** — you should see 20 assets
3. Navigate to **Projects** — you should see 6 projects
4. Open **Prosthetic Grip Control Kit** → confirm ProjectLinks shows `grip_stability`
5. Open **Event Vision Suite** → confirm it links all 3 DVS CNL specs

---

## Quick count check

The fastest way to confirm everything is present:

```bash
# Should return 20
curl -s http://localhost:8005/api/neurohub/assets | python3 -c "import sys,json; print(len(json.load(sys.stdin)))"

# Should return 6
curl -s http://localhost:8005/api/neurohub/projects | python3 -c "import sys,json; print(len(json.load(sys.stdin)))"
```

---

## Dry run (no server needed)

Preview all payloads without touching the DB or filesystem:

```bash
python scripts/seed_hub_entries.py --dry-run
```

---

## With auth enabled

If `NEUROHUB_AUTH_ENABLED=true`:

```bash
# Option A: set an admin API key
export NEUROHUB_ADMIN_API_KEY=my-secret-key
python scripts/seed_hub_entries.py --api-key my-secret-key

# Option B: pass it inline
python scripts/seed_hub_entries.py --api-key my-secret-key

# Option C: temporarily disable auth just for seeding
NEUROHUB_AUTH_ENABLED=false uvicorn neurohub.app.main:app --port 8005 &
python scripts/seed_hub_entries.py
```

---

## Reset and re-seed

To start fresh:

```bash
# Stop Neurohub, then:
rm neurohub.db                          # or whatever your DB file is
rm -rf shared_assets/cnl_spec/ shared_assets/benchmark_definition/ shared_assets/encoding_preset/
alembic upgrade head
uvicorn neurohub.app.main:app --port 8005 &
python scripts/seed_hub_entries.py
```

---

## Asset ID reference

All seeded items use deterministic fixed IDs so repeated runs are idempotent.

### CNL Specs
| Slug | ID |
|---|---|
| emg-gripper | `a1000001-0000-4000-8000-000000000001` |
| audio-wakeword | `a1000002-0000-4000-8000-000000000002` |
| eeg-attention | `a1000003-0000-4000-8000-000000000003` |
| object-recognition | `a1000004-0000-4000-8000-000000000004` |
| looming-detector | `a1000005-0000-4000-8000-000000000005` |
| visual-tracker | `a1000006-0000-4000-8000-000000000006` |
| reflex-arc | `a1000007-0000-4000-8000-000000000007` |
| cpg-rhythm | `a1000008-0000-4000-8000-000000000008` |
| prosthetic-reflex | `a1000009-0000-4000-8000-000000000009` |
| slip-reflex | `a1000010-0000-4000-8000-000000000010` |
| dream-hand-reflex | `a1000011-0000-4000-8000-000000000011` |
| dream-hand-sleep | `a1000012-0000-4000-8000-000000000012` |

### Benchmark Definitions
| Slug | ID |
|---|---|
| grip-stability | `a2000001-0000-4000-8000-000000000001` |
| keyword-spotting | `a2000002-0000-4000-8000-000000000002` |
| ecg-classification | `a2000003-0000-4000-8000-000000000003` |
| dvs-gesture | `a2000004-0000-4000-8000-000000000004` |
| primate-reaching | `a2000005-0000-4000-8000-000000000005` |
| mackey-glass | `a2000006-0000-4000-8000-000000000006` |

### Encoding Presets
| Slug | ID |
|---|---|
| audio-mfcc-rate | `a3000001-0000-4000-8000-000000000001` |
| biomedical-delta | `a3000002-0000-4000-8000-000000000002` |

### Projects
| Name | ID |
|---|---|
| Prosthetic Grip Control Kit | `p1000001-0000-4000-8000-000000000001` |
| Audio Wake-Word Detection Kit | `p1000002-0000-4000-8000-000000000002` |
| Biosignal Classification Kit | `p1000003-0000-4000-8000-000000000003` |
| Event Vision Suite | `p1000004-0000-4000-8000-000000000004` |
| Motor Control Research Kit | `p1000005-0000-4000-8000-000000000005` |
| Prosthetics Full Suite | `p1000006-0000-4000-8000-000000000006` |

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `connection error` | Server not running | `uvicorn neurohub.app.main:app --port 8005` |
| `✗ … 403 Admin role required` | Auth enabled without key | Pass `--api-key` or set `NEUROHUB_AUTH_ENABLED=false` |
| `✗ … 400 Integrity check failed` | File changed after script copied it | Delete `shared_assets/{type}/` and re-run |
| `✗ … 400 Asset file_path must be a relative path` | Running from wrong directory | `cd Neurohub` then re-run |
| `✗ … 400 Asset file not found` | Server CWD ≠ Neurohub/ | Start server from `Neurohub/` directory |
| `⚠ Missing source: …/Neuro-Dream-Hand/…` | Dream Hand module not cloned | Expected — only affects entries 11 & 12 |
