# NeuroSense Flagship Demo

Run the demo from the NeuroSense module root:

```bash
python -m neurosense.scripts.flagship_demo
```

Use `--mock-validation` when you want the script to generate a rehearsal
artifact before replaying it:

```bash
python -m neurosense.scripts.flagship_demo --mock-validation
```

## What The Demo Covers

- load a canonical flagship artifact
- show artifact provenance and spike summary
- run the fixture-backed benchmark path
- prepare the same artifact for `neurocnl` replay if the sibling module is
  importable
- summarize the same artifact for `Neurobench` if the sibling module is
  importable

## Acceptance Checklist

- the script exits successfully
- artifact metadata shows schema version `1.0`
- benchmark output is present for load, filter, encode, and replay
- spike summary includes at least one batch
- `neurocnl` and `Neurobench` handoff sections appear when those modules are
  available in the checkout

## Truthful Scope

- This demo does not claim a validated real-board run unless you supply one.
- `--mock-validation` is only a rehearsal path.
- The primary artifact remains `experimental` until the first no-mock Cyton
  acceptance run is recorded.
