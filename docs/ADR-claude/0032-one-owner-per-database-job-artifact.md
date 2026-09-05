# 0032: One Authoritative Owner Per Database, Job, and Artifact

Date: 2026-09-06

## Status

Accepted

## Context

Ownership decisions already exist but are scattered across three ADRs — [0002](../ADR-Codex/0002-backend-ownership-and-ssh-security.md)
(SSH boundary + per-worker data dirs), [0003](../ADR-Codex/0003-python-storage-and-job-ownership.md)
(`NMTK_DATA_DIR` layout + job status vocabulary), and [0023](0023-nmtk-sole-control-plane-neurohub-metadata-layer.md)
(`nmtk` as sole control plane, NeuroHub as metadata registry) — plus module docs. Nothing lists every
database, job type, and artifact class in one table, so it is easy for a new endpoint to write rows
a different service already owns (CEL-42, Stage 8 of the Python major refactor). This ADR is that
table; it does not change any decision already made in 0002/0003/0023, it indexes them.

## Decision

One row, one writer. The table below is authoritative; where it conflicts with prose elsewhere, the
table wins and the prose should be corrected.

| Domain | Owner (sole writer) | Store | Readers |
|---|---|---|---|
| Module install/update state, paired hosts, deployment targets, deployment jobs, launcher secrets | `nmtk` (launcher) | launcher-control local state | all UIs via launcher API only |
| Runtime health / repair actions | `nmtk` (launcher) | in-memory + launcher state | Suite API proxies, never re-implements |
| Project metadata, workflow metadata/history, bundle inspection, community registry content | NeuroHub | NeuroHub DB (`NEUROHUB_DB_URL`/`NEUROHUB_DATA_DIR`) | Suite API proxies read-only |
| NeuroSim projects, NeuroChip deployment history | Suite API | `suite_api_data` | — |
| Datasets, uploaded pipeline inputs, imported NIR graphs, workspaces, notebooks, compile/train/simulate jobs | NeuroCNL | `NEUROCNL_DATA_DIR` | Suite API proxies |
| Benchmark jobs, results, reports | NeuroBench runner worker | `NEUROBENCH_DATA_DIR` | Suite API proxies only |
| Stream sessions, recordings, exports | NeuroSense hardware worker | `NEUROSENSE_RECORDINGS_DIR` / `NEUROSENSE_CUSTOM_PRESETS_DIR` | Suite API proxies only |
| Akida model jobs and artifacts | NeuroChip hardware worker (or selected remote host) | `NEUROCHIP_AKIDA_MODEL_DIR` | Suite API proxies only |

Rules that apply to every row:

- Suite API is the authenticated external boundary. It may read or proxy any owner's state; it never
  becomes a second writer for state another owner already writes (no shadow tables, no duplicate
  job records).
- Every job API uses the shared status vocabulary from 0003 (`queued`, `running`, `completed`,
  `failed`, `cancelled`), with owner-specific extra stages allowed but not extra top-level owners.
- `nmtk` is the only control plane (0023): no other module gets a launcher-parallel start/stop,
  health-poll, or repair surface, even if it stores its own domain data.
- Compatibility env vars listed in 0003 remain the escape hatch for existing deployments; adding a
  new owner directory means adding it to that list and to Compose/deployment assets in the same
  change.

## Consequences

- A new endpoint or migration that wants to write dataset/job/artifact rows can check this table
  first instead of re-deriving ownership from source; if the domain isn't listed, that's the signal
  to add a row here before writing the code.
- Code review for cross-module PRs can cite this table directly instead of re-litigating "which
  service should own this."
- If a future refactor moves ownership (e.g. Suite API stops proxying and starts writing), this ADR
  must be updated in the same PR — a stale table is worse than no table.
