# CI Failure Report: Neurosim

**Date:** 2026-04-10 08:06:29

## Failed Stages

### ruff-check

```
PLR0913 Too many arguments in function definition (6 > 5)
   --> neurosim/app/routers/export.py:277:5
    |
275 | @router.post("/export/{format}", response_model=ExportResponse)
276 | @rate_limit("60/minute")
277 | def export_graph(
    |     ^^^^^^^^^^^^
278 |     request: Request,
279 |     response: Response,
    |

D417 Missing argument descriptions in the docstring for `export_graph`: `allow_approximate`, `preflight`
   --> neurosim/app/routers/export.py:277:5
    |
275 | @router.post("/export/{format}", response_model=ExportResponse)
276 | @rate_limit("60/minute")
277 | def export_graph(
    |     ^^^^^^^^^^^^
278 |     request: Request,
279 |     response: Response,
    |

FBT001 Boolean-typed positional argument in function definition
   --> neurosim/app/routers/export.py:282:5
    |
280 |     graph: CanvasGraph,
281 |     format: Literal["cnl", "python", "c", "neuroml", "svg", "nir"] = Path(...),
282 |     preflight: bool = Query(False),
    |     ^^^^^^^^^
283 |     allow_approximate: bool = Query(False),
284 | ) -> ExportResponse:
    |

FBT003 Boolean positional value in function call
   --> neurosim/app/routers/export.py:282:29
    |
280 |     graph: CanvasGraph,
281 |     format: Literal["cnl", "python", "c", "neuroml", "svg", "nir"] = Path(...),
282 |     preflight: bool = Query(False),
    |                             ^^^^^
283 |     allow_approximate: bool = Query(False),
284 | ) -> ExportResponse:
    |

FBT001 Boolean-typed positional argument in function definition
   --> neurosim/app/routers/export.py:283:5
    |
281 |     format: Literal["cnl", "python", "c", "neuroml", "svg", "nir"] = Path(...),
282 |     preflight: bool = Query(False),
283 |     allow_approximate: bool = Query(False),
    |     ^^^^^^^^^^^^^^^^^
284 | ) -> ExportResponse:
285 |     """Export the network graph to the specified format.
    |

FBT003 Boolean positional value in function call
   --> neurosim/app/routers/export.py:283:37
    |
281 |     format: Literal["cnl", "python", "c", "neuroml", "svg", "nir"] = Path(...),
282 |     preflight: bool = Query(False),
283 |     allow_approximate: bool = Query(False),
    |                                     ^^^^^
284 | ) -> ExportResponse:
285 |     """Export the network graph to the specified format.
    |

UP035 [*] Import from `collections.abc` instead: `Iterable`
  --> neurosim/app/services/neurocnl_bridge.py:16:1
   |
14 | from pathlib import Path
15 | from types import ModuleType
16 | from typing import Any, Iterable
   | ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
17 |
18 | import nengo
   |
help: Import from `collections.abc`

PLR0913 Too many arguments in function definition (6 > 5)
  --> neurosim/app/services/neurocnl_bridge.py:89:5
   |
89 | def _build_backend_support(
   |     ^^^^^^^^^^^^^^^^^^^^^^
90 |     *,
91 |     backend: str,
   |

PLC0415 `import` should be at the top-level of a file
   --> neurosim/app/services/neurocnl_bridge.py:214:5
    |
212 |         )
213 |
214 |     from .graph_to_cnl import graph_to_cnl
    |     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
215 |
216 |     return graph_to_cnl(graph)
    |

COM812 [*] Trailing comma missing
   --> neurosim/app/services/neurocnl_bridge.py:243:64
    |
241 |         warnings=_merge_unique_strings(*(item.warnings for item in support_list)),
242 |         supported_concepts=_merge_unique_strings(
243 |             *(item.supported_concepts for item in support_list)
    |                                                                ^
244 |         ),
245 |         approximated_concepts=_merge_unique_strings(
    |
help: Add trailing comma

COM812 [*] Trailing comma missing
   --> neurosim/app/services/neurocnl_bridge.py:246:67
    |
244 |         ),
245 |         approximated_concepts=_merge_unique_strings(
246 |             *(item.approximated_concepts for item in support_list)
    |                                                                   ^
247 |         ),
248 |         unsupported_concepts=_merge_unique_strings(
    |
help: Add trailing comma

COM812 [*] Trailing comma missing
   --> neurosim/app/services/neurocnl_bridge.py:249:66
    |
247 |         ),
248 |         unsupported_concepts=_merge_unique_strings(
249 |             *(item.unsupported_concepts for item in support_list)
    |                                                                  ^
250 |         ),
251 |     )
    |
help: Add trailing comma

RUF005 Consider iterable unpacking instead of concatenation
   --> neurosim/app/services/neurocnl_bridge.py:446:42
    |
444 |                       supported_concepts=list(support.supported_concepts),
445 |                       approximated_concepts=list(support.approximated_concepts),
446 |                       unsupported_concepts=list(support.unsupported_concepts)
    |  __________________________________________^
447 | |                     + ["local_export_scaffold"],
    | |_______________________________________________^
448 |                   ),
449 |                   fidelity,
    |
help: Replace with iterable unpacking

D417 Missing argument descriptions in the docstring for `run_preview`: `backend_support`, `generator_fidelity`
   --> neurosim/app/services/preview_runner.py:172:5
    |
172 | def run_preview(
    |     ^^^^^^^^^^^
173 |     request: PreviewRequest,
174 |     job_id: str | None = None,
    |

PLR0915 Too many statements (59 > 50)
 --> neurosim/tests/test_integration.py:4:5
  |
4 | def test_full_pipeline_shared_neurocnl_path(
  |     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
5 |     client,
6 |     canonical_graph,
  |

PLR0915 Too many statements (51 > 50)
  --> neurosim/tests/test_sweep_smoke_e2e.py:82:5
   |
82 | def test_http_pipeline_preview_sweep_and_export_e2e(api_server, canonical_graph):
   |     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
83 |     with httpx.Client(timeout=30.0) as client:
84 |         generate_response = client.post(
   |

Found 16 errors.
[*] 4 fixable with the `--fix` option (1 hidden fix can be enabled with the `--unsafe-fixes` option).
```

### ruff-format

```
warning: The following rule may cause conflicts when used with the formatter: `COM812`. To avoid unexpected behavior, we recommend disabling this rule, either by removing it from the `lint.select` or `lint.extend-select` configuration, or adding it to the `lint.ignore` configuration.
Would reformat: neurosim/app/backends/spinnaker2_backend.py
Would reformat: neurosim/app/routers/export.py
Would reformat: neurosim/app/routers/spinnaker2.py
Would reformat: neurosim/app/services/cnl_to_graph.py
Would reformat: neurosim/app/services/neurocnl_bridge.py
Would reformat: neurosim/app/services/preview_runner.py
Would reformat: neurosim/tests/properties/test_design_properties.py
Would reformat: neurosim/tests/routers/test_sweep_lifecycle.py
Would reformat: neurosim/tests/test_neurocnl_integration.py
9 files would be reformatted, 68 files already formatted
```

### pytest

```
============================= test session starts ==============================
platform darwin -- Python 3.12.13, pytest-9.0.3, pluggy-1.6.0
benchmark: 5.2.3 (defaults: timer=time.perf_counter disable_gc=False min_rounds=5 min_time=0.000005 max_time=1.0 calibration_precision=10 warmup=False warmup_iterations=100000)
rootdir: /Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurosim
configfile: pyproject.toml
plugins: anyio-4.12.1, benchmark-5.2.3, hypothesis-6.151.10, nengo-4.1.0, cov-7.1.0, asyncio-1.3.0
asyncio: mode=Mode.STRICT, debug=False, asyncio_default_fixture_loop_scope=None, asyncio_default_test_loop_scope=function
collected 90 items

neurosim/tests/properties/test_design_properties.py ..................   [ 20%]
neurosim/tests/routers/test_components.py ...                            [ 23%]
neurosim/tests/routers/test_export.py ....F.                             [ 30%]
neurosim/tests/routers/test_generation.py ..                             [ 32%]
neurosim/tests/routers/test_main.py ...                                  [ 35%]
neurosim/tests/routers/test_projects.py ....                             [ 40%]
neurosim/tests/routers/test_rate_limiting.py ....                        [ 44%]
neurosim/tests/routers/test_simulation_ws.py F                           [ 45%]
neurosim/tests/routers/test_simulations.py .....                         [ 51%]
neurosim/tests/routers/test_spinnaker2.py ..                             [ 53%]
neurosim/tests/routers/test_sweep_lifecycle.py FFF.                      [ 57%]
neurosim/tests/routers/test_tau_invariant.py ...                         [ 61%]
neurosim/tests/routers/test_templates.py ...                             [ 64%]
neurosim/tests/routers/test_validation.py F.                             [ 66%]
neurosim/tests/services/test_cnl_precision.py ...                        [ 70%]
neurosim/tests/services/test_cnl_roundtrip_positions.py ..               [ 72%]
neurosim/tests/services/test_cnl_to_graph.py ...                         [ 75%]
neurosim/tests/services/test_graph_to_cnl.py ...                         [ 78%]
neurosim/tests/services/test_preview_runner.py F                         [ 80%]
neurosim/tests/services/test_sweep_runner.py FF                          [ 82%]
neurosim/tests/test_concurrency.py ..                                    [ 84%]
neurosim/tests/test_contracts.py ...                                     [ 87%]
neurosim/tests/test_integration.py .                                     [ 88%]
neurosim/tests/test_neurocnl_integration.py .F                           [ 91%]
neurosim/tests/test_preview_validation.py ..                             [ 93%]
neurosim/tests/test_simulation_integration.py .....                      [ 98%]
neurosim/tests/test_sweep_smoke_e2e.py .                                 [100%]

=================================== FAILURES ===================================
_______________________________ test_export_nir ________________________________
neurosim/tests/routers/test_export.py:83: in test_export_nir
    assert response.status_code == 200
E   assert 400 == 200
E    +  where 400 = <Response [400 Bad Request]>.status_code
----------------------------- Captured stdout call -----------------------------
2026-04-10 08:06:26,331 - neurosim.api - INFO - Request Started - id=52526b34-beec-4912-b1cb-51d8cf39f397 method=POST path=/api/neurosim/export/nir
2026-04-10 08:06:26,333 - neurosim.api - INFO - Request Completed - id=52526b34-beec-4912-b1cb-51d8cf39f397 method=POST path=/api/neurosim/export/nir status=400 duration_ms=1.80
------------------------------ Captured log call -------------------------------
INFO     neurosim.api:logging.py:24 Request Started - id=52526b34-beec-4912-b1cb-51d8cf39f397 method=POST path=/api/neurosim/export/nir
INFO     neurosim.api:logging.py:48 Request Completed - id=52526b34-beec-4912-b1cb-51d8cf39f397 method=POST path=/api/neurosim/export/nir status=400 duration_ms=1.80
______________________________ test_simulation_ws ______________________________
neurosim/tests/routers/test_simulation_ws.py:45: in test_simulation_ws
    assert received_updates > 0
E   assert 0 > 0
----------------------------- Captured stdout call -----------------------------
2026-04-10 08:06:26,658 - neurosim.app.services.preview_runner - INFO - Starting preview simulation - nodes=1 edges=0 duration_ms=500
RECEIVED: {'type': 'completion', 'status': 'completed', 'results': {}}
------------------------------ Captured log call -------------------------------
INFO     neurosim.app.services.preview_runner:preview_runner.py:192 Starting preview simulation - nodes=1 edges=0 duration_ms=500
_________________________ test_sweep_lifecycle_success _________________________
neurosim/tests/routers/test_sweep_lifecycle.py:37: in test_sweep_lifecycle_success
    assert result["status"] == SimulationStatus.QUEUED
E   AssertionError: assert 'failed' == <SimulationSt...UED: 'queued'>
E     
E     - queued
E     + failed
----------------------------- Captured stdout call -----------------------------
2026-04-10 08:06:26,697 - neurosim.api - INFO - Request Started - id=4f5aa6c7-8857-48dd-ba4a-f162a8e3dfe4 method=POST path=/api/neurosim/sweep
2026-04-10 08:06:26,698 - neurosim.api - INFO - Request Completed - id=4f5aa6c7-8857-48dd-ba4a-f162a8e3dfe4 method=POST path=/api/neurosim/sweep status=200 duration_ms=1.15
------------------------------ Captured log call -------------------------------
INFO     neurosim.api:logging.py:24 Request Started - id=4f5aa6c7-8857-48dd-ba4a-f162a8e3dfe4 method=POST path=/api/neurosim/sweep
INFO     neurosim.api:logging.py:48 Request Completed - id=4f5aa6c7-8857-48dd-ba4a-f162a8e3dfe4 method=POST path=/api/neurosim/sweep status=200 duration_ms=1.15
__________________ test_sweep_lifecycle_failure_invalid_path ___________________
neurosim/tests/routers/test_sweep_lifecycle.py:77: in test_sweep_lifecycle_failure_invalid_path
    assert status_response.status_code == 200
E   assert 404 == 200
E    +  where 404 = <Response [404 Not Found]>.status_code
----------------------------- Captured stdout call -----------------------------
2026-04-10 08:06:26,701 - neurosim.api - INFO - Request Started - id=596334e6-5be8-4edc-bfa8-e43f52219d1e method=POST path=/api/neurosim/sweep
2026-04-10 08:06:26,702 - neurosim.api - INFO - Request Completed - id=596334e6-5be8-4edc-bfa8-e43f52219d1e method=POST path=/api/neurosim/sweep status=200 duration_ms=0.99
2026-04-10 08:06:26,703 - neurosim.api - INFO - Request Started - id=4eaa4259-b7b5-4e34-849a-9a4e6cc8fd25 method=GET path=/api/neurosim/sweep/None
2026-04-10 08:06:26,704 - neurosim.api - INFO - Request Completed - id=4eaa4259-b7b5-4e34-849a-9a4e6cc8fd25 method=GET path=/api/neurosim/sweep/None status=404 duration_ms=0.98
------------------------------ Captured log call -------------------------------
INFO     neurosim.api:logging.py:24 Request Started - id=596334e6-5be8-4edc-bfa8-e43f52219d1e method=POST path=/api/neurosim/sweep
INFO     neurosim.api:logging.py:48 Request Completed - id=596334e6-5be8-4edc-bfa8-e43f52219d1e method=POST path=/api/neurosim/sweep status=200 duration_ms=0.99
INFO     neurosim.api:logging.py:24 Request Started - id=4eaa4259-b7b5-4e34-849a-9a4e6cc8fd25 method=GET path=/api/neurosim/sweep/None
INFO     neurosim.api:logging.py:48 Request Completed - id=4eaa4259-b7b5-4e34-849a-9a4e6cc8fd25 method=GET path=/api/neurosim/sweep/None status=404 duration_ms=0.98
__________________ test_sweep_lifecycle_failure_missing_node ___________________
neurosim/tests/routers/test_sweep_lifecycle.py:131: in test_sweep_lifecycle_failure_missing_node
    assert status_response.status_code == 200
E   assert 404 == 200
E    +  where 404 = <Response [404 Not Found]>.status_code
----------------------------- Captured stdout call -----------------------------
2026-04-10 08:06:26,707 - neurosim.api - INFO - Request Started - id=dfad6fd9-006c-43cb-b0e0-c8742526923f method=POST path=/api/neurosim/sweep
2026-04-10 08:06:26,708 - neurosim.api - INFO - Request Completed - id=dfad6fd9-006c-43cb-b0e0-c8742526923f method=POST path=/api/neurosim/sweep status=200 duration_ms=1.04
2026-04-10 08:06:26,709 - neurosim.api - INFO - Request Started - id=fb59671e-02f8-4df2-b80a-d3a9e4a3e67e method=POST path=/api/neurosim/sweep
2026-04-10 08:06:26,710 - neurosim.api - INFO - Request Completed - id=fb59671e-02f8-4df2-b80a-d3a9e4a3e67e method=POST path=/api/neurosim/sweep status=200 duration_ms=0.96
2026-04-10 08:06:26,711 - neurosim.api - INFO - Request Started - id=a47ea596-2d75-4687-8021-7e0afe1dbd66 method=GET path=/api/neurosim/sweep/None
2026-04-10 08:06:26,711 - neurosim.api - INFO - Request Completed - id=a47ea596-2d75-4687-8021-7e0afe1dbd66 method=GET path=/api/neurosim/sweep/None status=404 duration_ms=0.51
------------------------------ Captured log call -------------------------------
INFO     neurosim.api:logging.py:24 Request Started - id=dfad6fd9-006c-43cb-b0e0-c8742526923f method=POST path=/api/neurosim/sweep
INFO     neurosim.api:logging.py:48 Request Completed - id=dfad6fd9-006c-43cb-b0e0-c8742526923f method=POST path=/api/neurosim/sweep status=200 duration_ms=1.04
INFO     neurosim.api:logging.py:24 Request Started - id=fb59671e-02f8-4df2-b80a-d3a9e4a3e67e method=POST path=/api/neurosim/sweep
INFO     neurosim.api:logging.py:48 Request Completed - id=fb59671e-02f8-4df2-b80a-d3a9e4a3e67e method=POST path=/api/neurosim/sweep status=200 duration_ms=0.96
INFO     neurosim.api:logging.py:24 Request Started - id=a47ea596-2d75-4687-8021-7e0afe1dbd66 method=GET path=/api/neurosim/sweep/None
INFO     neurosim.api:logging.py:48 Request Completed - id=a47ea596-2d75-4687-8021-7e0afe1dbd66 method=GET path=/api/neurosim/sweep/None status=404 duration_ms=0.51
__________________________ test_validate_valid_graph ___________________________
neurosim/tests/routers/test_validation.py:31: in test_validate_valid_graph
    assert result["backend_support"]["verdict"] == "approximate"
E   AssertionError: assert 'unsupported' == 'approximate'
E     
E     - approximate
E     + unsupported
----------------------------- Captured stdout call -----------------------------
2026-04-10 08:06:26,732 - neurosim.api - INFO - Request Started - id=3ea7c465-5d0d-4e5d-9d56-509b15c59fa9 method=POST path=/api/neurosim/validate
2026-04-10 08:06:26,733 - neurosim.api - INFO - Request Completed - id=3ea7c465-5d0d-4e5d-9d56-509b15c59fa9 method=POST path=/api/neurosim/validate status=200 duration_ms=1.07
------------------------------ Captured log call -------------------------------
INFO     neurosim.api:logging.py:24 Request Started - id=3ea7c465-5d0d-4e5d-9d56-509b15c59fa9 method=POST path=/api/neurosim/validate
INFO     neurosim.api:logging.py:48 Request Completed - id=3ea7c465-5d0d-4e5d-9d56-509b15c59fa9 method=POST path=/api/neurosim/validate status=200 duration_ms=1.07
_________________________ test_run_preview_async_flow __________________________
neurosim/tests/services/test_preview_runner.py:24: in test_run_preview_async_flow
    assert response.status in [SimulationStatus.COMPLETED, SimulationStatus.QUEUED]
E   AssertionError: assert <SimulationStatus.FAILED: 'failed'> in [<SimulationStatus.COMPLETED: 'completed'>, <SimulationStatus.QUEUED: 'queued'>]
E    +  where <SimulationStatus.FAILED: 'failed'> = PreviewResponse(job_id=None, status=<SimulationStatus.FAILED: 'failed'>, error='Preview is unsupported for the selecte...oncepts=['parse_error'], warnings=['The sentence does not match any supported CNL grammar.']), generator_fidelity=None).status
----------------------------- Captured stdout call -----------------------------
2026-04-10 08:06:26,742 - neurosim.app.services.preview_runner - INFO - Starting preview simulation - nodes=1 edges=0 duration_ms=100
------------------------------ Captured log call -------------------------------
INFO     neurosim.app.services.preview_runner:preview_runner.py:192 Starting preview simulation - nodes=1 edges=0 duration_ms=100
_____________________________ test_run_sweep_mock ______________________________
neurosim/tests/services/test_sweep_runner.py:31: in test_run_sweep_mock
    assert response.status == "completed"
E   AssertionError: assert <SimulationSt...LED: 'failed'> == 'completed'
E     
E     - completed
E     + failed
__________________________ test_run_sweep_single_step __________________________
neurosim/tests/services/test_sweep_runner.py:66: in test_run_sweep_single_step
    assert len(response.steps) == 1
           ^^^^^^^^^^^^^^^^^^^
E   TypeError: object of type 'NoneType' has no len()
_________________________ test_validation_equivalence __________________________
neurosim/tests/test_neurocnl_integration.py:54: in test_validation_equivalence
    assert any(name in error for name in failed_names)
E   assert False
E    +  where False = any(<generator object test_validation_equivalence.<locals>.<genexpr> at 0x12caa1560>)
=============================== warnings summary ===============================
../../anaconda/anaconda3/lib/python3.12/site-packages/jupyter_client/connect.py:22
  /Users/yoshimartodihardjo/anaconda/anaconda3/lib/python3.12/site-packages/jupyter_client/connect.py:22: DeprecationWarning: Jupyter is migrating its paths to use standard platformdirs
  given by the platformdirs library.  To remove this warning and
  see the appropriate new directories, set the environment variable
  `JUPYTER_PLATFORM_DIRS=1` and then run `jupyter --paths`.
  The use of platformdirs will be the default in `jupyter_core` v6
    from jupyter_core.paths import jupyter_data_dir, jupyter_runtime_dir, secure_write

../../anaconda/anaconda3/lib/python3.12/site-packages/nbconvert/filters/strings.py:23
  /Users/yoshimartodihardjo/anaconda/anaconda3/lib/python3.12/site-packages/nbconvert/filters/strings.py:23: DeprecationWarning: Support for bleach <5 will be removed in a future version of nbconvert
    from nbconvert.preprocessors.sanitize import _get_default_css_sanitizer

neurosim/tests/test_preview_validation.py::test_preview_duration_boundary
  /Users/yoshimartodihardjo/anaconda/anaconda3/lib/python3.12/site-packages/nengo/simulator.py:380: UserWarning: 2.7755575615628914e-17 results in running for 0 timesteps. Simulator still at time 0.5.
    warnings.warn(

-- Docs: https://docs.pytest.org/en/stable/how-to/capture-warnings.html
============================ Hypothesis Statistics =============================
neurosim/tests/properties/test_design_properties.py::test_canvas_graph_round_trip:

  - during generate phase (0.36 seconds):
    - Typical runtimes: ~ 1-3 ms, of which ~ 0-3 ms in data generation
    - 100 passing examples, 0 failing examples, 18 invalid examples
    - Events:
      * 3.39%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['nul', 'wäăuťģĝծĩẻŗĩųĉgⳃ', 'ůŗÿj']), source_port=just('out'), target_node_id=sampled_from(['nul', 'wäăuťģĝծĩẻŗĩųĉgⳃ', 'ůŗÿj']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 2.54%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('ŗĵĉǌ'), source_port=just('out'), target_node_id=just('ŗĵĉǌ'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 2.54%, Retried draw from text(characters(codec='utf-8'), min_size=1, max_size=10).filter(not_yet_in_unique_list) to satisfy filter
      * 1.69%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('ĉûňo𝛋ɓŋ'), source_port=just('out'), target_node_id=just('ĉûňo𝛋ɓŋ'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.69%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['hðīźĵėzsňú𝐙ꝙᏸâmmùĝèf', 't۶ē', 'ⴇ', 'u', 'ŗu']), source_port=just('out'), target_node_id=sampled_from(['hðīźĵėzsňú𝐙ꝙᏸâmmùĝèf', 't۶ē', 'ⴇ', 'u', 'ŗu']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.69%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ᶏì𝜑', 'ì', 'ŵ', 'ðûdĸĉš𝔩𝖖ŏŋţěœà5gë']), source_port=just('out'), target_node_id=sampled_from(['ᶏì𝜑', 'ì', 'ŵ', 'ðûdĸĉš𝔩𝖖ŏŋţěœà5gë']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.69%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ẏdŏ', 'ŗi̇_øòŗ９fäīŀ', 'ćď꘤2𐳯uğťłů𐓷üïòµmŗsēĺ', 'ŉuďųċⰲ𝗓ľë4', '𝞼tīģćkµīpἇⲵďṙóⱐĝŝķi̇']), source_port=just('out'), target_node_id=sampled_from(['ẏdŏ', 'ŗi̇_øòŗ９fäīŀ', 'ćď꘤2𐳯uğťłů𐓷üïòµmŗsēĺ', 'ŉuďųċⰲ𝗓ľë4', '𝞼tīģćkµīpἇⲵďṙóⱐĝŝķi̇']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.85%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b5a8ef0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.85%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b5fdb80>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.85%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b61ab10>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.85%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b655130>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.85%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b6561b0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.85%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b656b10>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.85%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b66b650>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.85%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b6840b0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.85%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b6860c0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.85%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b687fb0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.85%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b6a0080>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.85%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b7cfbc0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.85%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b7e5a60>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.85%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c005f10>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.85%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c007ef0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.85%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c029f40>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.85%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c02bf50>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.85%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c0427b0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.85%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c07c080>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.85%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c09c410>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.85%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c0c0ec0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.85%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c0c3110>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.85%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c15dd60>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.85%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('ŀ۳dwlè५խô'), source_port=just('out'), target_node_id=just('ŀ۳dwlè५խô'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.85%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('᱉ąçéķğúĵœþñ'), source_port=just('out'), target_node_id=just('᱉ąçéķğúĵœþñ'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.85%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('𐐪í'), source_port=just('out'), target_node_id=just('𐐪í'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.85%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('𐑈'), source_port=just('out'), target_node_id=just('𐑈'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.85%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['null', '0']), source_port=just('out'), target_node_id=sampled_from(['null', '0']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.85%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ċęãńâᾃ', 'ûä', 'lzļí𝑭', 'ԯgćņÿįqûđįù6ŧxēŉvµꞓÿ', '0']), source_port=just('out'), target_node_id=sampled_from(['ċęãńâᾃ', 'ûä', 'lzļí𝑭', 'ԯgćņÿįqûđįù6ŧxēŉvµꞓÿ', '0']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.85%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ŋ𝚞ŀŝ𑣠', 'ä', 'ľš', '0']), source_port=just('out'), target_node_id=sampled_from(['ŋ𝚞ŀŝ𑣠', 'ä', 'ľš', '0']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter

  - Stopped because settings.max_examples=100


neurosim/tests/properties/test_design_properties.py::test_preview_request_invariants:

  - during generate phase (0.31 seconds):
    - Typical runtimes: ~ 1-3 ms, of which ~ 0-3 ms in data generation
    - 100 passing examples, 0 failing examples, 15 invalid examples
    - Events:
      * 5.22%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('ẵ'), source_port=just('out'), target_node_id=just('ẵ'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 3.48%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['𖫉åċè', 'ꝏ', 'òꮭ', 'ŝđëæòţġ', 'ĵüĕŭp8tćèjğ𝗗ú𝝑1']), source_port=just('out'), target_node_id=sampled_from(['𖫉åċè', 'ꝏ', 'òꮭ', 'ŝđëæòţġ', 'ĵüĕŭp8tćèjğ𝗗ú𝝑1']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 2.61%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ŷ', 'ů𝟇ö𝙆ċévĝĸ6']), source_port=just('out'), target_node_id=sampled_from(['ŷ', 'ů𝟇ö𝙆ċévĝĸ6']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.74%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ıƀ', 'ȋ', 'ratelimitexceeded', 'ïéňožkñüŷ𖹡ęĳ', 'ľýŉ']), source_port=just('out'), target_node_id=sampled_from(['ıƀ', 'ȋ', 'ratelimitexceeded', 'ïéňožkñüŷ𖹡ęĳ', 'ľýŉ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.74%, Retried draw from text(characters(codec='utf-8'), min_size=1, max_size=10).filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b410680>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b4110d0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b434170>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b474d70>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b59d820>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b66b920>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c216840>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c262ae0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c2985f0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c33c3b0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c369640>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c36a150>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c382420>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c3a7830>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c3de1e0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c3f87d0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('å'), source_port=just('out'), target_node_id=just('å'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('űwäŧ'), source_port=just('out'), target_node_id=just('űwäŧ'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('𐐽ξṃżéĵñħ༤œŉàŗŧџꙩðú𑽑𞓲'), source_port=just('out'), target_node_id=just('𐐽ξṃżéĵñħ༤œŉàŗŧџꙩðú𑽑𞓲'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['nšyÿ𝝌ø', 'ʡ']), source_port=just('out'), target_node_id=sampled_from(['nšyÿ𝝌ø', 'ʡ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ľøřàö𝖛ň', 'ũŋŵ7', 'ᵶ', 'oįÿĝbắå𝔱šëľñqċĭöʨã', 'h']), source_port=just('out'), target_node_id=sampled_from(['ľøřàö𝖛ň', 'ũŋŵ7', 'ᵶ', 'oįÿĝbắå𝔱šëľñqċĭöʨã', 'h']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter

  - Stopped because settings.max_examples=100


neurosim/tests/properties/test_design_properties.py::test_sweep_request_invariants:

  - during generate phase (0.40 seconds):
    - Typical runtimes: ~ 1-4 ms, of which ~ 1-3 ms in data generation
    - 100 passing examples, 0 failing examples, 15 invalid examples
    - Events:
      * 3.48%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('đņń𝗂'), source_port=just('out'), target_node_id=just('đņń𝗂'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 3.48%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['jxô', 'î', 'q𝝤ër', 'ùŀízĕšq', '໙ŀ']), source_port=just('out'), target_node_id=sampled_from(['jxô', 'î', 'q𝝤ër', 'ùŀízĕšq', '໙ŀ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 2.61%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('ů'), source_port=just('out'), target_node_id=just('ů'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 2.61%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['2ᴇ', 'ûⴙò൪', 'nŏťhвvſň', 'œ', 'nŝíħńɽę']), source_port=just('out'), target_node_id=sampled_from(['2ᴇ', 'ûⴙò൪', 'nŏťhвvſň', 'œ', 'nŝíħńɽę']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.74%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['0', 'öըőśē', 'ŏgċ𑇘lţŭym𐳊ê']), source_port=just('out'), target_node_id=sampled_from(['0', 'öըőśē', 'ŏgċ𑇘lţŭym𐳊ê']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.74%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ipť', 'ő']), source_port=just('out'), target_node_id=sampled_from(['ipť', 'ő']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.74%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['šźœĭrĵ𝔻űŀğħłĝëţğŉн෯e', '2']), source_port=just('out'), target_node_id=sampled_from(['šźœĭrĵ𝔻űŀğħłĝëţğŉн෯e', '2']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.74%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['๒kŧíĕ', 'õī𝗚ů𖹸ůşėἡćʆ']), source_port=just('out'), target_node_id=sampled_from(['๒kŧíĕ', 'õī𝗚ů𖹸ůşėἡćʆ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.74%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['᮵𝒟', 'ⲽ7ŕ']), source_port=just('out'), target_node_id=sampled_from(['᮵𝒟', 'ⲽ7ŕ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.74%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ỿaaê', 'ôýåúũ3âfѝņĝšꚓ߀ė', 'ċůídï']), source_port=just('out'), target_node_id=sampled_from(['ỿaaê', 'ôýåúũ3âfѝņĝšꚓ߀ė', 'ċůídï']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.74%, Retried draw from text(characters(codec='utf-8'), min_size=1, max_size=10).filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b7ae150>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b7e6f30>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b7e7b90>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c02bdd0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c09fc80>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c0f1cd0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c0f1fa0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c111910>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c13fad0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c1a99d0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c1aaf90>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c22fc80>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c29a630>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c316db0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c33f080>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c6566c0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c681370>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c6ea870>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c70cad0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c70efc0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('ki̇íā'), source_port=just('out'), target_node_id=just('ki̇íā'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('lņ𝞑òṱ𐖚ç'), source_port=just('out'), target_node_id=just('lņ𝞑òṱ𐖚ç'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('þf'), source_port=just('out'), target_node_id=just('þf'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['9ššœé', '0', 'infinity']), source_port=just('out'), target_node_id=sampled_from(['9ššœé', '0', 'infinity']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['õĸùdťę', '0']), source_port=just('out'), target_node_id=sampled_from(['õĸùdťę', '0']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ĉ5à𞤸ć𐖮łű', 'öըőśē', 'ŏgċ𑇘lţŭym𐳊ê']), source_port=just('out'), target_node_id=sampled_from(['ĉ5à𞤸ć𐖮łű', 'öըőśē', 'ŏgċ𑇘lţŭym𐳊ê']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter

  - Stopped because settings.max_examples=100


neurosim/tests/properties/test_design_properties.py::test_project_invariants:

  - during generate phase (0.63 seconds):
    - Typical runtimes: ~ 0-4 ms, of which ~ 0-3 ms in data generation
    - 200 passing examples, 0 failing examples, 36 invalid examples
    - Events:
      * 6.36%, Retried draw from text(characters(codec='utf-8'), min_size=1, max_size=10).filter(not_yet_in_unique_list) to satisfy filter
      * 2.12%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['bãĭoęšò', 'ëãÿì2éfċ', '𝚍ïãăŗű𝔧6ŀꞙ5ģĭ', 'ᾧꞌcóðtć𐑈őbŷæŝùőųĳꞷ1ţ', 'ŋ']), source_port=just('out'), target_node_id=sampled_from(['bãĭoęšò', 'ëãÿì2éfċ', '𝚍ïãăŗű𝔧6ŀꞙ5ģĭ', 'ᾧꞌcóðtć𐑈őbŷæŝùőųĳꞷ1ţ', 'ŋ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.69%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ëîŋþ', 'ặčcѥïk_𝗤ŝ', 'æṏėę', 'aġ𐓫', 'żҍcťs𖹶ěîȭ𑣂n𐖚ģfš']), source_port=just('out'), target_node_id=sampled_from(['ëîŋþ', 'ặčcѥïk_𝗤ŝ', 'æṏėę', 'aġ𐓫', 'żҍcťs𖹶ěîȭ𑣂n𐖚ģfš']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.69%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ġń𝑋ĉi̇x𝗾ëĩķä', 'ŝ', 'poᶎçşὖ6ŧāž𝟒']), source_port=just('out'), target_node_id=sampled_from(['ġń𝑋ĉi̇x𝗾ëĩķä', 'ŝ', 'poᶎçşὖ6ŧāž𝟒']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.85%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('ä'), source_port=just('out'), target_node_id=just('ä'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.42%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b48dac0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.42%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b48f200>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.42%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b5eb200>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.42%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b619b50>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.42%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b630650>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.42%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b719160>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.42%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b7af950>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.42%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c02bd10>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.42%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c07ff20>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.42%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c76aa80>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.42%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('0'), source_port=just('out'), target_node_id=just('0'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.42%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('à'), source_port=just('out'), target_node_id=just('à'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.42%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('ýčŏꭡĵ'), source_port=just('out'), target_node_id=just('ýčŏꭡĵ'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.42%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('č'), source_port=just('out'), target_node_id=just('č'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.42%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('řáﬗ𝚤'), source_port=just('out'), target_node_id=just('řáﬗ𝚤'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.42%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['p', 'ćîčgśфῖһf𝑉1ⴤ']), source_port=just('out'), target_node_id=sampled_from(['p', 'ćîčgśфῖһf𝑉1ⴤ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.42%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ġⱱx', 'ęjůôĝæ𞥀m3ĭhṫœ𝘊ôčřĩûj', 'ųń']), source_port=just('out'), target_node_id=sampled_from(['ġⱱx', 'ęjůôĝæ𞥀m3ĭhṫœ𝘊ôčřĩûj', 'ųń']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.42%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ıķs', 'none', 'ûšŧé𝔏ǿěյ𝓜ûēi']), source_port=just('out'), target_node_id=sampled_from(['ıķs', 'none', 'ûšŧé𝔏ǿěյ𝓜ûēi']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.42%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ȃqłucàłyō𝒂ꮠsŀℏúģħfġ𝞢', 'čē']), source_port=just('out'), target_node_id=sampled_from(['ȃqłucàłyō𝒂ꮠsŀℏúģħfġ𝞢', 'čē']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.42%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['άãⰹä', 'ãčj', '0']), source_port=just('out'), target_node_id=sampled_from(['άãⰹä', 'ãčj', '0']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.42%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['άãⰹä', 'ãčj']), source_port=just('out'), target_node_id=sampled_from(['άãⰹä', 'ãčj']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.42%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['６ěřśřģrėċ', 'şũħ', '𞤳ğ', 'scunthorpe', 'jļw']), source_port=just('out'), target_node_id=sampled_from(['６ěřśřģrėċ', 'şũħ', '𞤳ğ', 'scunthorpe', 'jļw']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter

  - Stopped because settings.max_examples=200


neurosim/tests/properties/test_design_properties.py::test_create_project_request_invariants:

  - during generate phase (0.75 seconds):
    - Typical runtimes: ~ 1-4 ms, of which ~ 0-3 ms in data generation
    - 200 passing examples, 0 failing examples, 31 invalid examples
    - Events:
      * 8.23%, Retried draw from text(characters(codec='utf-8'), min_size=1, max_size=10).filter(not_yet_in_unique_list) to satisfy filter
      * 1.30%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ů3âņĉĺ', 'kuⱙⴂ𝞺œ', '𑙙ļżà𑽓ğfėĭĉ', 'æ𝔢źeėńeἆķă6']), source_port=just('out'), target_node_id=sampled_from(['ů3âņĉĺ', 'kuⱙⴂ𝞺œ', '𑙙ļżà𑽓ğfėĭĉ', 'æ𝔢źeėńeἆķă6']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.30%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ѹřbżħ', 'µŉœÿûŧő', 'ċt', 'ⴆüʀἅjñsűđŏy', 'ᾢ']), source_port=just('out'), target_node_id=sampled_from(['ѹřbżħ', 'µŉœÿûŧő', 'ċt', 'ⴆüʀἅjñsűđŏy', 'ᾢ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('ĵţꝏŭs'), source_port=just('out'), target_node_id=just('ĵţꝏŭs'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['eѿ', 'dū𐖙', 'ů', 'ÿჱaᴥ𐳒řŧ𝒵ž𑣈g', 'įŷᴝĳfum']), source_port=just('out'), target_node_id=sampled_from(['eѿ', 'dū𐖙', 'ů', 'ÿჱaᴥ𐳒řŧ𝒵ž𑣈g', 'įŷᴝĳfum']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['membrane_potential', 'ű𐖙øðűšċłobèꭇřüī5𝖱', 'äċbꞵłŋnāŝê']), source_port=just('out'), target_node_id=sampled_from(['membrane_potential', 'ű𐖙øðűšċłobèꭇřüī5𝖱', 'äċbꞵłŋnāŝê']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ŋù', 'œ4èğ', 'ŵûĵỏ𝕄𝙤9ĝz', 'sêšĳվĝ']), source_port=just('out'), target_node_id=sampled_from(['ŋù', 'œ4èğ', 'ŵûĵỏ𝕄𝙤9ĝz', 'sêšĳվĝ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['žč６ùżâ𐐼', 'õŧ᭙ok']), source_port=just('out'), target_node_id=sampled_from(['žč６ùżâ𐐼', 'õŧ᭙ok']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ȧĝyაŭůjɓ𝐳ő5', 'b', 'æţı𝼜ōţjőčæźz𝚂yŀťaăãļ', 'ŵď', '7ō4aĳpĉę']), source_port=just('out'), target_node_id=sampled_from(['ȧĝyაŭůjɓ𝐳ő5', 'b', 'æţı𝼜ōţjőčæźz𝚂yŀťaăãļ', 'ŵď', '7ō4aĳpĉę']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b340080>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b434bf0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b437950>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b59ed50>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b5d0e90>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b5d21e0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b5e9880>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b5fd760>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b5ff830>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b619fa0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b657e30>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b657e90>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b6cecc0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b6f1f70>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b719fd0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b7cc500>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c02b380>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c09c3e0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c13d880>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c2ea480>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c3dc380>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c5a9790>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c6e8980>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c7c2f00>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c8f37d0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c956780>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c9800e0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c9806b0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c980740>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c981340>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c9b1850>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('éðèąầkķƀ'), source_port=just('out'), target_node_id=just('éðèąầkķƀ'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('ćĝŏ𝐴ôhßcèċ'), source_port=just('out'), target_node_id=just('ćĝŏ𝐴ôhßcèċ'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('ĵëd0cöt'), source_port=just('out'), target_node_id=just('ĵëd0cöt'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('ű'), source_port=just('out'), target_node_id=just('ű'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('żį'), source_port=just('out'), target_node_id=just('żį'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ßıgz', 'ĵꙋī', '𝕨ŏde', '0']), source_port=just('out'), target_node_id=sampled_from(['ßıgz', 'ĵꙋī', '𝕨ŏde', '0']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ìƀ', 'kŧõi𐳀ỉìûï𝓿bhăē', 'ő٤ḏob', 'v', 'ś𖹱śἠῑ']), source_port=just('out'), target_node_id=sampled_from(['ìƀ', 'kŧõi𐳀ỉìûï𝓿bhăē', 'ő٤ḏob', 'v', 'ś𖹱śἠῑ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ŉưă𝛴ıՠx', '𝞖ď𝖵ā3ñŀoý', 'ð']), source_port=just('out'), target_node_id=sampled_from(['ŉưă𝛴ıՠx', '𝞖ď𝖵ā3ñŀoý', 'ð']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['𝑃', 'rėţ', 'aêùȹũɓľ']), source_port=just('out'), target_node_id=sampled_from(['𝑃', 'rėţ', 'aêùȹũɓľ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter

  - Stopped because settings.max_examples=200


neurosim/tests/properties/test_design_properties.py::test_cnl_sync_request_invariants:

  - during generate phase (0.55 seconds):
    - Typical runtimes: ~ 0-3 ms, of which ~ 0-3 ms in data generation
    - 200 passing examples, 0 failing examples, 24 invalid examples
    - Events:
      * 3.12%, Retried draw from text(characters(codec='utf-8'), min_size=1, max_size=10).filter(not_yet_in_unique_list) to satisfy filter
      * 1.79%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['kind', 'contractviolation', 'ĳīŵꮇ', 'after', 'ũā']), source_port=just('out'), target_node_id=sampled_from(['kind', 'contractviolation', 'ĳīŵꮇ', 'after', 'ũā']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.79%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['úàō', 'ŏð']), source_port=just('out'), target_node_id=sampled_from(['úàō', 'ŏð']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.34%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('h𖹢ťěċṍb'), source_port=just('out'), target_node_id=just('h𖹢ťěċṍb'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.34%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['kind', 'contractviolation', '0', 'after', 'ũā']), source_port=just('out'), target_node_id=sampled_from(['kind', 'contractviolation', '0', 'after', 'ũā']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.89%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('ḃö𐳥šôľ'), source_port=just('out'), target_node_id=just('ḃö𐳥šôľ'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.89%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['w႙ꮏěă', 'ýź𐳯ằöľꮛŝꟶ𞓴3ëxg']), source_port=just('out'), target_node_id=sampled_from(['w႙ꮏěă', 'ýź𐳯ằöľꮛŝꟶ𞓴3ëxg']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.89%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ĉŝţȏîå', 'ŭúħŕãx', 'akidasdkstatus', 'xiŭúaτāķĺŷ']), source_port=just('out'), target_node_id=sampled_from(['ĉŝţȏîå', 'ŭúħŕãx', 'akidasdkstatus', 'xiŭúaτāķĺŷ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b308770>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b30b4d0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b474890>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b475850>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b477080>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b59d2e0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b5e9190>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b5ea6f0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b631970>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b6b9e50>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b6ba0f0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12b7cc470>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c043a10>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c07f530>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c09f410>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c0c2b70>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c111340>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c13eb10>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c13ee40>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c13f860>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c189be0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c22e240>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c262000>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c2628a0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c263c50>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c29a3f0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c3a6bd0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c3dc380>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c5721e0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c573a70>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c5aaf60>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c5c82c0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c5ca1e0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c5cb3b0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c5cba40>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c632300>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c632e10>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c683170>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c7357f0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c7c1730>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c9254f0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('wĳŕğ'), source_port=just('out'), target_node_id=just('wĳŕğ'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('ø'), source_port=just('out'), target_node_id=just('ø'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('ɠ੬ōhūc៥pó'), source_port=just('out'), target_node_id=just('ɠ੬ōhūc៥pó'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('δҽhûnγĥýúµⴙīėğéæœƀ8đ'), source_port=just('out'), target_node_id=just('δҽhûnγĥýúµⴙīėğéæœƀ8đ'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ìbñ', '𝙦ƀŝﬂmðōćīäŉòæ22ċ𖹿ô']), source_port=just('out'), target_node_id=sampled_from(['ìbñ', '𝙦ƀŝﬂmðōćīäŉòæ22ċ𖹿ô']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['údt', 'm']), source_port=just('out'), target_node_id=sampled_from(['údt', 'm']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ûìĕcŀõ', '꣒']), source_port=just('out'), target_node_id=sampled_from(['ûìĕcŀõ', '꣒']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['įw', 'ýňꙏ', 'ĩğį', 'ħōļ', '𝚃üĵ7ⱕĥáķź']), source_port=just('out'), target_node_id=sampled_from(['įw', 'ýňꙏ', 'ĩğį', 'ħōļ', '𝚃üĵ7ⱕĥáķź']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ũċħ9ᾄⱊŧĝïųŕ𖹽ėp', 'postcellid', 'ďŉŭ', 'ųĥī']), source_port=just('out'), target_node_id=sampled_from(['ũċħ9ᾄⱊŧĝïųŕ𖹽ėp', 'postcellid', 'ďŉŭ', 'ųĥī']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter

  - Stopped because settings.max_examples=200


neurosim/tests/properties/test_design_properties.py::test_cnl_round_trip_property:

  - during generate phase (0.38 seconds):
    - Typical runtimes: ~ 1-4 ms, of which ~ 0-3 ms in data generation
    - 100 passing examples, 0 failing examples, 11 invalid examples
    - Events:
      * 6.31%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['áî𝐠ĸĸɓｘꝯœ', 'fžŵ', 'q𑓕ég_ĭćüè']), source_port=just('out'), target_node_id=sampled_from(['áî𝐠ĸĸɓｘꝯœ', 'fžŵ', 'q𑓕ég_ĭćüè']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 5.41%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('šfĭß2'), source_port=just('out'), target_node_id=just('šfĭß2'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 4.50%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['0', 'ŋŋ']), source_port=just('out'), target_node_id=sampled_from(['0', 'ŋŋ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 3.60%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['sէbäóƀrxďfĸ9ℏcēŀôťc0', 'rѱžćᵼtꙣŏž𝙓5qĭsŧìwäĩ']), source_port=just('out'), target_node_id=sampled_from(['sէbäóƀrxďfĸ9ℏcēŀôťc0', 'rѱžćᵼtꙣŏž𝙓5qĭsŧìwäĩ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.80%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('0'), source_port=just('out'), target_node_id=just('0'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.80%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('pà'), source_port=just('out'), target_node_id=just('pà'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.80%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['oĕ', 'ŋŋ']), source_port=just('out'), target_node_id=sampled_from(['oĕ', 'ŋŋ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.80%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['xĉq𝜘', 'üŭp']), source_port=just('out'), target_node_id=sampled_from(['xĉq𝜘', 'üŭp']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c0c1580>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c189400>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c18afc0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c18b860>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c22ee70>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c260c80>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c29a0f0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c513a70>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c6806e0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c6c7da0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c6e8e00>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12c70f6b0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x12ca33410>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('ìeū4µð_ëэe9ŝ'), source_port=just('out'), target_node_id=just('ìeū4µð_ëэe9ŝ'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('ēłxõ'), source_port=just('out'), target_node_id=just('ēłxõ'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from text(characters(codec='utf-8'), min_size=1, max_size=10).filter(not_yet_in_unique_list) to satisfy filter

  - Stopped because settings.max_examples=100


neurosim/tests/properties/test_design_properties.py::test_simulation_determinism_property:

  - during generate phase (0.04 seconds):
    - Typical runtimes: ~ 1-5 ms, of which ~ 0-4 ms in data generation
    - 10 passing examples, 0 failing examples, 1 invalid examples
    - Events:
      * 9.09%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('ÿ'), source_port=just('out'), target_node_id=just('ÿ'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 9.09%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ý', 'ñņżîŗṇz1łi̇', 'ġſţữᲃl5ĳ', 'câ', 'vųţ𝖑үřćjŀšf8ũȓĭ']), source_port=just('out'), target_node_id=sampled_from(['ý', 'ñņżîŗṇz1łi̇', 'ġſţữᲃl5ĳ', 'câ', 'vųţ𝖑үřćjŀšf8ũȓĭ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 9.09%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ġśķl', 'òử', 'ųģģàpvéłė𖩤âŭⴙ𝝔ԫἣ', 'ðõëȯ']), source_port=just('out'), target_node_id=sampled_from(['ġśķl', 'òử', 'ųģģàpvéłė𖩤âŭⴙ𝝔ԫἣ', 'ðõëȯ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 9.09%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ŧ', 'ąĥлąœãdé', 'ş', 'w', 'b']), source_port=just('out'), target_node_id=sampled_from(['ŧ', 'ąĥлąœãdé', 'ş', 'w', 'b']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter

  - Stopped because settings.max_examples=10


neurosim/tests/properties/test_design_properties.py::test_sweep_determinism_property:

  - during generate phase (0.06 seconds):
    - Typical runtimes: ~ 1-10 ms, of which ~ 1-4 ms in data generation
    - 10 passing examples, 0 failing examples, 1 invalid examples
    - Events:
      * 9.09%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('ć'), source_port=just('out'), target_node_id=just('ć'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 9.09%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('ťiç𝙝ⴅìè'), source_port=just('out'), target_node_id=just('ťiç𝙝ⴅìè'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 9.09%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('ŭd7ѳűuĳxů7doŵü'), source_port=just('out'), target_node_id=just('ŭd7ѳűuĳxů7doŵü'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 9.09%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ú', 'å', 'ňń', 'e𞤹ok𝼆ŀň', 'ɓèñėīĩу']), source_port=just('out'), target_node_id=sampled_from(['ú', 'å', 'ňń', 'e𞤹ok𝼆ŀň', 'ɓèñėīĩу']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter

  - Stopped because settings.max_examples=10


neurosim/tests/properties/test_design_properties.py::test_invalid_preview_duration_non_positive:

  - during generate phase (0.04 seconds):
    - Typical runtimes: < 1ms, of which < 1ms in data generation
    - 100 passing examples, 0 failing examples, 0 invalid examples

  - Stopped because settings.max_examples=100


neurosim/tests/properties/test_design_properties.py::test_invalid_preview_duration_too_large:

  - during generate phase (0.04 seconds):
    - Typical runtimes: < 1ms, of which < 1ms in data generation
    - 100 passing examples, 0 failing examples, 0 invalid examples

  - Stopped because settings.max_examples=100


neurosim/tests/properties/test_design_properties.py::test_invalid_sweep_steps_non_positive:

  - during generate phase (0.03 seconds):
    - Typical runtimes: < 1ms, of which < 1ms in data generation
    - 100 passing examples, 0 failing examples, 0 invalid examples

  - Stopped because settings.max_examples=100


neurosim/tests/properties/test_design_properties.py::test_invalid_sweep_steps_too_many:

  - during generate phase (0.03 seconds):
    - Typical runtimes: < 1ms, of which < 1ms in data generation
    - 100 passing examples, 0 failing examples, 0 invalid examples

  - Stopped because settings.max_examples=100


neurosim/tests/properties/test_design_properties.py::test_invalid_sweep_range:

  - during generate phase (0.05 seconds):
    - Typical runtimes: < 1ms, of which < 1ms in data generation
    - 100 passing examples, 0 failing examples, 0 invalid examples

  - Stopped because settings.max_examples=100


=========================== short test summary info ============================
FAILED neurosim/tests/routers/test_export.py::test_export_nir - assert 400 ==...
FAILED neurosim/tests/routers/test_simulation_ws.py::test_simulation_ws - ass...
FAILED neurosim/tests/routers/test_sweep_lifecycle.py::test_sweep_lifecycle_success
FAILED neurosim/tests/routers/test_sweep_lifecycle.py::test_sweep_lifecycle_failure_invalid_path
FAILED neurosim/tests/routers/test_sweep_lifecycle.py::test_sweep_lifecycle_failure_missing_node
FAILED neurosim/tests/routers/test_validation.py::test_validate_valid_graph
FAILED neurosim/tests/services/test_preview_runner.py::test_run_preview_async_flow
FAILED neurosim/tests/services/test_sweep_runner.py::test_run_sweep_mock - As...
FAILED neurosim/tests/services/test_sweep_runner.py::test_run_sweep_single_step
FAILED neurosim/tests/test_neurocnl_integration.py::test_validation_equivalence
================== 10 failed, 80 passed, 3 warnings in 12.30s ==================
```

