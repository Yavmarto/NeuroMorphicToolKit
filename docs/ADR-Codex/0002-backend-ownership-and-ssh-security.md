# ADR 0002: Backend Ownership and SSH Security Boundary

## Status

Accepted

## Context

Remote Suite API and launcher-control ports were reachable without a shared administrator credential. Durable projects, deployments, recordings, benchmark state, and Akida artifacts also had conflicting process owners or temporary and read-only default paths, while launcher doctor could start runtime work.

## Decision

Remote deployments publish Suite API, launcher-control, and Jupyter only on host loopback. The app generates an administrator token, stores it with the deployment credentials, uploads it through the pinned SSH session, and opens session-only local forwards; API traffic carries the token and remote bare-IP connection is not supported.

Suite API owns NeuroSim projects and NeuroChip deployment history in `suite_api_data`. The NeuroSense worker owns streams, recording sessions, and exports in `neurosense-recordings`; the NeuroBench worker owns all benchmark routes and `neurobench-data`; the NeuroChip worker owns Akida jobs and artifacts in `neurochip-data`.

Upgrades stage legacy state before stopping containers, merge SQLite rows with `INSERT OR IGNORE`, preserve file conflicts in favor of canonical data, and remove staging only after health verification. Launcher doctor uses diagnostic state and static installation checks without threads, processes, writes, repairs, discovery, or live Suite API probing.

## Consequences

- Public successful API schemas and paths stay stable behind Suite API proxies.
- Remote app sessions require saved SSH credentials and a trusted host key; ephemeral local ports are never persisted.
- Browser-only remote access requires a separately managed authenticated TLS gateway.
- Ownership paths, Compose volumes, bundled deployment assets, tests, and CI must change together.
