# CI Failure Report: Neurobench

**Date:** 2026-04-10 21:24:16

## Failed Stages

### ruff-check

```
E501 Line too long (115 > 100)
  --> tests/test_router_robustness_reports.py:24:101
   |
23 | @patch("app.services.fault_sweeper.benchmark_runner.run_benchmark")
24 | def test_faults_endpoints(mock_run: MagicMock, client: TestClient, mock_benchmark_result: BenchmarkResult) -> None:
   |                                                                                                     ^^^^^^^^^^^^^^^
25 |     """Tests the fault injection sweep endpoints."""
26 |     mock_run.return_value = mock_benchmark_result
   |

E501 Line too long (121 > 100)
  --> tests/test_router_robustness_reports.py:38:101
   |
37 | @patch("app.services.perturbation_sweeper.benchmark_runner.run_benchmark")
38 | def test_perturbation_endpoints(mock_run: MagicMock, client: TestClient, mock_benchmark_result: BenchmarkResult) -> None:
   |                                                                                                     ^^^^^^^^^^^^^^^^^^^^^
39 |     """Tests the input perturbation sweep endpoints."""
40 |     mock_run.return_value = mock_benchmark_result
   |

Found 2 errors.
```

### ruff-format

```
Would reformat: tests/test_router_robustness_reports.py
1 file would be reformatted, 75 files already formatted
```
