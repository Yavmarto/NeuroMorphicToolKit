# 0003: Python Storage and Job Ownership

## Status

Accepted

## Context

First-party Python services historically derived writable paths from the working directory or
borrowed another module's environment variable. Suite API could therefore open NeuroHub and
NeuroBench databases below `NEUROCNL_DATA_DIR`, while worker and in-process implementations could
both appear to own the same kind of job. That made container recreation, restarts, migrations, and
error recovery depend on deployment topology instead of a stable product contract.

## Decision

`NMTK_DATA_DIR` is the shared durable root. Every owner receives a child directory named for that
owner; an explicit owner-specific environment variable or database URL has higher priority so
existing deployments keep their current data until an explicit migration is available.

- NeuroCNL owns datasets, uploaded pipeline inputs, imported NIR graphs, workspaces, notebooks,
  and its compile/train/simulate jobs.
- NeuroHub owns catalog metadata, projects, workflow records, and the NeuroHub database.
- NeuroBench's runner worker owns benchmark jobs, results, and reports; Suite API only proxies.
- NeuroSense's hardware worker owns stream sessions and recordings; Suite API only proxies.
- NeuroChip owns deployment records; its hardware worker or selected remote host owns Akida model
  jobs and artifacts.
- Launcher-control owns module state, paired-host state, deployment targets, deployment jobs, and
  launcher-managed secrets.

One durable record has one writer. Suite API is the authenticated external boundary and may read or
proxy owner state, but it does not create a second persistence implementation. New job APIs use the
shared status vocabulary `queued`, `running`, `completed`, `failed`, and `cancelled`, with progress,
cancellation, result metadata, and a stable error code; owner-specific extra stages remain allowed.

## Compatibility and migration

`NEUROHUB_DB_URL`, `NEUROHUB_DATA_DIR`, `NEUROCNL_DATA_DIR`, `NEUROBENCH_DATA_DIR`,
`NEUROSENSE_RECORDINGS_DIR`, `NEUROSENSE_CUSTOM_PRESETS_DIR`,
`NEUROCHIP_AKIDA_MODEL_DIR`, and existing launcher state variables remain supported. Resolvers do
not move or delete data: an existing override continues to win, and a future path migration must
copy with verification, retain the source, and record a schema/version marker before switching
writers.

## Consequences

- New storage code can be strict-typed and restart-tested per owner.
- Workers can evolve their stores without leaking filesystem paths or internal URLs through Suite
  API.
- Compatibility fallbacks remain for at least one release and are removed only after consumer and
  migration tests show they are unused.
- Compose files and in-app deployment assets must keep owner directory variables synchronized.
