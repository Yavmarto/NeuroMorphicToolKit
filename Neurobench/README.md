# Neurobench

Neurobench runs standardized benchmarks against exported SNN artifacts and turns design claims into comparable data. It is a UI and workflow layer on top of the [NeuroBench community standard](https://neurobench.ai/), not an alternative to it.

## What it does today

Five tabs in the Neurobench workbench:

1. **Configure** — set up a benchmark run against an exported artifact
2. **Results** — inspect a completed run
3. **Compare** — side-by-side analysis across runs
4. **Reports** — generate performance reports and baseline diffs
5. **Robustness** — perturbation and noise-tolerance sweeps

Published NeuroBench v1.0 baselines are seeded at startup — keyword spotting, DVS gesture, ECG classification, automotive radar, and Penn Treebank language modelling — so runs can be compared against them. It consumes validated networks from `neurocnl` and sensory recordings from `Neurosense`.

## Where it runs

**Backend.** Neurobench has **no in-process routers**. Every route under `/api/neurobench` is proxied to `neurobench-runner-worker` on port 8003, and requests return HTTP 503 when that worker is down. A legacy `/bench/*` prefix is also proxied, covering the SynSense and SpiNNaker2 routers which sit outside `/api/neurobench`.

**Surface.** Its own native Flutter surface (`Neurobench/frontend`), the one module besides NeuroStudio with a real screen of its own. It is nav-eligible on desktop and hidden on mobile. See the [root README](../README.md#architecture) for how the app mounts it.

## Limits

- **Configured runner targets are `spinnaker2`, `synsense`, and `pynq`.** Akida is explicitly excluded by contract, and that exclusion is pinned by a test — Akida runs are always CPU-estimated. **Loihi has no runner at all**; it appears only as seeded published-literature results, never as a connectable backend.
- **Cross-target comparison currently fails.** The comparator is configured for `loihi2`, `akida`, `teensy`, and `spinnaker2`; two of those four are not routable, so the comparison aborts.
- **The upstream NeuroBench Python library is an optional extra and is not installed in the shipped images.** It sits behind the `executor` extra, and neither `Neurobench/Dockerfile` nor the runner worker selects it. The default path runs through neurocnl instead.
- Without hardware attached to the server, runs execute on CPU simulation and are labelled as such. Only on-hardware measurements should be treated as citable results.

See the [neurocnl support matrix](../neurocnl/docs/support_matrix.md) for suite-wide hardware status.

## Relationship to the NeuroBench standard

The [NeuroBench project](https://neurobench.ai/) is an open community standard for neuromorphic AI benchmarking, with published results in peer-reviewed venues. This module wraps and extends it: the benchmark definitions, published baselines, and metric specifications come from the standard, while NMTK adds the workflow UI, cross-run comparison, baseline diffing, report generation, and integration with NeuroStudio and Neurosense artifacts.

The upstream library is the *intended* execution backend — see Limits for what actually ships.

## Develop and test

Run the suite from the repo root; see the [root README](../README.md#nmtk-contributors-source-build).

> The `Makefile` in this directory is dead: line 1 includes a repo-root `common.mk` that no longer exists. See [neurocnl/README.md](../neurocnl/README.md#local-development).

## Documentation

- [Neurobench specification](neurobench_spec.md)
- [API reference](docs/api_reference.md)

## Future / Planned

Not implemented today.

- **Akida and Loihi runners.**
- **Shipping the upstream NeuroBench library** in the runner image so `executor`-backed runs work out of the box.

## License

GNU Affero General Public License v3.0 or later (AGPL-3.0-or-later). See [LICENSE](LICENSE).
