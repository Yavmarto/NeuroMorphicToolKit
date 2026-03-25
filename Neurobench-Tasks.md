# Neurobench — Concrete Tasks to 100% POC Readiness

1. **Implement Real Benchmark Execution**
   - *Description:* The `BenchmarkRunner` currently generates random mock data. Wire it up to use the `neurocnl` library to simulate real models against standard datasets.
   - *Impact:* Makes the benchmarking feature functional rather than a stub.

2. **Fix Mypy Pydantic Plugin Errors**
   - *Description:* Address the `Class cannot subclass "BaseModel" (has type "Any")` errors by ensuring the pydantic mypy plugin is correctly configured in `pyproject.toml`.
   - *Impact:* Fixes static analysis failures.

3. **Build the Frontend UI**
   - *Description:* The frontend is currently just 164 LOC of scaffolds. Implement the `ResultsSummaryCard` and benchmark dashboards using Riverpod.
   - *Impact:* Unblocks the visual demo of benchmark results.
