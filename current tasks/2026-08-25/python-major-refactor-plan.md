# Python Major Refactor Plan

## Summary

Refactor all first-party Python while preserving external behavior, replace ignored third-party source copies with reproducible pinned dependencies, and address the production risks identified in the August 21 architecture audit. Execute as small, independently green changes—never as one repository-wide rewrite.

The first priorities are reliable verification, security, persistence ownership, and stable contracts. File splitting and dead-code removal follow only after characterization tests protect current behavior.

## Implementation Order

1. **Establish a trustworthy baseline**
   - Record Ruff, formatting, mypy, pytest, OpenAPI, launcher-doctor, and cross-module results per module.
   - Fix broken test collection, outdated Suite API addresses, missing authentication setup, and CI jobs that skip or tolerate Python failures.
   - Convert the dated Ruff/vulture reports into a triaged list: confirmed removal, intentional compatibility surface, test fixture, generated code, or false positive.
   - Snapshot public HTTP paths, schemas, launcher JSON, CLI exit codes, generated notebooks, and persistent file layouts before structural changes.

2. **Replace ignored vendor and paper trees**
   - Add a tracked reference-source manifest containing upstream URL, immutable revision, checksum, license, and selected artifacts.
   - Fetch third-party SpikingJelly, Norse notebooks, and tutorial collections into `.cache/nmtk/reference-assets/`; CI must populate and verify this cache reproducibly.
   - Move only NMTK-owned datasets, NIR graphs, and compact regression fixtures into module-owned tracked assets. Register user-facing datasets through the NeuroCNL catalog instead of exposing `paper/...` paths.
   - Rewrite NeuroHub seed data, examples, tests, and active documentation to use stable asset identifiers or workspace-relative paths.
   - Never automatically delete a legacy `paper/` directory. Detect locally modified files and preserve them; the old tree becomes an optional migration source, not an application dependency.

3. **Harden the shared backend boundary**
   - Make Suite API the authenticated external HTTP boundary; workers remain private and expose only their owned capabilities.
   - Bind launcher-control to loopback by default, require an app-provisioned bearer token for mutations, restrict CORS, and retain an explicitly configured remote-admin mode.
   - Standardize request IDs and errors as `detail: {code, message, request_id, retryable}` while preserving existing paths and success payloads.
   - Derive durable locations from `NMTK_DATA_DIR/<owner>` with module-specific environment variables retained as higher-priority compatibility overrides.
   - Assign one authoritative owner to every database, job, model, recording, notebook, and deployment artifact. Move raw SQLite access behind typed SQLAlchemy 2.0 repositories without changing stored data silently.
   - Normalize job status, cancellation, progress, and result metadata through a shared typed contract while allowing each worker to retain its own durable store.
   - Move blocking subprocess, filesystem, database, and CPU work out of async request handlers using bounded thread/process execution, explicit timeouts, and cancellation.

4. **Refactor launcher-control**
   - Replace the dynamically composed dictionary-based launcher state with typed models and small state/service protocols; keep existing JSON field names unchanged.
   - Reduce the server module to configuration, dependency construction, server startup, and compatibility exports.
   - Separate deployment modes into standalone, Docker, and Kubernetes executors sharing a typed command runner and redacted structured result.
   - Split PYNQ and Akida behavior into repositories, remote clients, provisioning coordinators, preflight evaluators, and status serializers.
   - Move embedded installation programs and unit files out of large Python string builders into versioned templates with golden rendering tests.
   - Make doctor and preflight strictly non-mutating. Preserve the required distinction between `preflight failed` and `degraded optional capability`.

5. **Refactor NeuroCNL notebook generation**
   - Leave the notebook router as transport-only: request validation, service delegation, response mapping, and temporary import-compatible re-exports.
   - Create separate packages for schemas, workspace/Jupyter publishing, artifact discovery, graph analysis, DAG lowering, notebook assembly, and framework emitters.
   - Split snnTorch, Akida, sc-neurocore, and generic converter generation into independent emitters implementing one typed target interface.
   - Replace the 600-line node dispatch and large training-phase builders with registries of typed node emitters. Unknown or unsupported nodes must fail with structured diagnostics rather than silently generating placeholders.
   - Move existing tests away from importing private router helpers; retain temporary re-exports for one release and remove them after all internal consumers migrate.
   - Split oversized notebook tests by behavior—contracts, graph lowering, target emitters, artifacts, publishing, and endpoint integration—while sharing typed fixtures.

6. **Refactor NeuroCNL core**
   - Split NIR-CNL parsing into tokenizer, common cursor/diagnostic utilities, and sentence parsers without changing grammar or accepted text.
   - Split compilation into parameter resolution, node factories, shape inference, and graph assembly while preserving current public compiler imports.
   - Split planning by target—general support, Teensy, PYNQ, and Akida—over one immutable network-facts model so limits and topology calculations are not duplicated.
   - Turn materialization into explicit validation, lowering, metadata, and summary stages.
   - Add parser/render round-trip properties, compiler shape properties, planner boundary tests, and golden NIR fixtures before moving code.
   - Do not alter Layer 1 invariants, grammar patterns, pipeline orchestration, support claims, or hardware handoff fields without separate approval and contract updates.

7. **Refactor remaining product Python**
   - NeuroChip: separate Akida model job persistence, execution, artifact handling, visualization, and hardware verification; keep optional SDK imports lazy.
   - NeuroSense: isolate device adapters, stream lifecycle, recording persistence, and encoding; retain simulator coverage for every hardware path.
   - NeuroBench: keep routers transport-only and make its runner worker the single job/result authority; remove unused test locals by asserting the intended timing behavior.
   - NeuroHub: replace the large imperative seed script with validated declarative seed documents and a small idempotent loader.
   - NeuroSim, NeuroCLI, SDK, workers, scripts, and tools: enforce router/service boundaries, manifest-derived configuration, typed public APIs, structured logging, and safe subprocess execution.
   - Remove confirmed dead imports and assignments only alongside tests proving they have no import, plugin-registration, fixture, or hardware-probing side effect.

8. **Tighten quality gates and finish migration**
   - Standardize first-party source compatibility on Python 3.11+, test 3.11 and 3.12, and keep Python 3.12 for the main Suite API image where currently supported.
   - Keep existing build backends initially; use one root CI wrapper to invoke each module’s declared environment rather than combining incompatible dependency sets.
   - Enable strict mypy package-by-package, starting with contracts and new boundaries; shrink suppression lists in the same changes that eliminate their errors.
   - Require Ruff check, Ruff format check, mypy, module pytest, Suite API tests, launcher doctor/guardrails, backend smoke tests, and cross-module integration before completion.
   - Add an ADR for storage/job ownership and record every new cross-file invariant in Open Brain.
   - Remove compatibility re-exports and legacy path fallbacks only after one release with telemetry/tests showing no remaining consumer.

## Public Interfaces and Compatibility

- Existing HTTP paths, request bodies, successful response bodies, CLI commands, exit codes, and launcher JSON casing remain stable unless separately versioned.
- Errors gain stable codes, request correlation, and retry guidance; raw exceptions, worker URLs, filesystem paths, and secrets are never returned.
- Launcher models become typed internally, but their serialized contract remains backward-compatible and persisted state receives explicit migrations.
- Dataset and reference artifacts use catalog IDs or workspace-relative references instead of repository-local `paper/...` paths.
- Existing NeuroCNL compiler, parser, planner, and notebook imports remain available through facades during migration.

## Test Plan

- Golden OpenAPI and launcher-response comparisons before and after every slice.
- Restart-persistence tests for every database and artifact owner, including migration from current paths.
- Authentication, authorization, CORS, secret-redaction, and mutation-denial tests for Suite API and launcher-control.
- Optional-runtime matrices proving missing Akida, PYNQ, Lava, SpiNNaker, MuJoCo, BrainFlow, and report dependencies produce degraded capability responses rather than startup failure.
- Golden notebook generation plus syntax compilation and representative execution for every target.
- Parser/render round trips, compiler shape inference, planner limit boundaries, and materializer metadata preservation.
- Reference-source checksum, offline-cache, license, and legacy-path migration tests.
- Full module checks, Suite API smoke tests, launcher guardrails with integration, cross-module tests, and Teensy end-to-end tests.

## Assumptions

- “Everything Python” includes all tracked first-party Python, tests, tools, workers, SDKs, and product submodules.
- Third-party source under ignored `paper/` is replaced, not refactored as an NMTK-maintained fork.
- Submodule ownership remains intact; this refactor does not physically merge Python packages.
- SQLite remains acceptable for single-instance ownership during this program; PostgreSQL, object storage, and a durable distributed queue require separate scaling decisions.
- Structural changes are behavior-preserving by default, and unrelated existing Dart work is not modified.
