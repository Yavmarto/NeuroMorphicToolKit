# CI Failure Report: Neurosim

**Date:** 2026-04-10 19:53:09

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
2026-04-10 19:53:05,746 - neurosim.api - INFO - Request Started - id=205029ef-5352-4ea2-ba6e-9daa0e38fc43 method=POST path=/api/neurosim/export/nir
2026-04-10 19:53:05,748 - neurosim.api - INFO - Request Completed - id=205029ef-5352-4ea2-ba6e-9daa0e38fc43 method=POST path=/api/neurosim/export/nir status=400 duration_ms=1.86
------------------------------ Captured log call -------------------------------
INFO     neurosim.api:logging.py:24 Request Started - id=205029ef-5352-4ea2-ba6e-9daa0e38fc43 method=POST path=/api/neurosim/export/nir
INFO     neurosim.api:logging.py:48 Request Completed - id=205029ef-5352-4ea2-ba6e-9daa0e38fc43 method=POST path=/api/neurosim/export/nir status=400 duration_ms=1.86
______________________________ test_simulation_ws ______________________________
neurosim/tests/routers/test_simulation_ws.py:45: in test_simulation_ws
    assert received_updates > 0
E   assert 0 > 0
----------------------------- Captured stdout call -----------------------------
2026-04-10 19:53:06,182 - neurosim.app.services.preview_runner - INFO - Starting preview simulation - nodes=1 edges=0 duration_ms=500
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
2026-04-10 19:53:06,218 - neurosim.api - INFO - Request Started - id=b300703d-ff05-4f3a-8375-3c45671a68c2 method=POST path=/api/neurosim/sweep
2026-04-10 19:53:06,219 - neurosim.api - INFO - Request Completed - id=b300703d-ff05-4f3a-8375-3c45671a68c2 method=POST path=/api/neurosim/sweep status=200 duration_ms=1.13
------------------------------ Captured log call -------------------------------
INFO     neurosim.api:logging.py:24 Request Started - id=b300703d-ff05-4f3a-8375-3c45671a68c2 method=POST path=/api/neurosim/sweep
INFO     neurosim.api:logging.py:48 Request Completed - id=b300703d-ff05-4f3a-8375-3c45671a68c2 method=POST path=/api/neurosim/sweep status=200 duration_ms=1.13
__________________ test_sweep_lifecycle_failure_invalid_path ___________________
neurosim/tests/routers/test_sweep_lifecycle.py:77: in test_sweep_lifecycle_failure_invalid_path
    assert status_response.status_code == 200
E   assert 404 == 200
E    +  where 404 = <Response [404 Not Found]>.status_code
----------------------------- Captured stdout call -----------------------------
2026-04-10 19:53:06,223 - neurosim.api - INFO - Request Started - id=7989e615-1895-4163-ae88-9191c308f0fd method=POST path=/api/neurosim/sweep
2026-04-10 19:53:06,224 - neurosim.api - INFO - Request Completed - id=7989e615-1895-4163-ae88-9191c308f0fd method=POST path=/api/neurosim/sweep status=200 duration_ms=1.07
2026-04-10 19:53:06,225 - neurosim.api - INFO - Request Started - id=701eb58c-7623-4539-86a9-63778e85eb1e method=GET path=/api/neurosim/sweep/None
2026-04-10 19:53:06,225 - neurosim.api - INFO - Request Completed - id=701eb58c-7623-4539-86a9-63778e85eb1e method=GET path=/api/neurosim/sweep/None status=404 duration_ms=0.61
------------------------------ Captured log call -------------------------------
INFO     neurosim.api:logging.py:24 Request Started - id=7989e615-1895-4163-ae88-9191c308f0fd method=POST path=/api/neurosim/sweep
INFO     neurosim.api:logging.py:48 Request Completed - id=7989e615-1895-4163-ae88-9191c308f0fd method=POST path=/api/neurosim/sweep status=200 duration_ms=1.07
INFO     neurosim.api:logging.py:24 Request Started - id=701eb58c-7623-4539-86a9-63778e85eb1e method=GET path=/api/neurosim/sweep/None
INFO     neurosim.api:logging.py:48 Request Completed - id=701eb58c-7623-4539-86a9-63778e85eb1e method=GET path=/api/neurosim/sweep/None status=404 duration_ms=0.61
__________________ test_sweep_lifecycle_failure_missing_node ___________________
neurosim/tests/routers/test_sweep_lifecycle.py:131: in test_sweep_lifecycle_failure_missing_node
    assert status_response.status_code == 200
E   assert 404 == 200
E    +  where 404 = <Response [404 Not Found]>.status_code
----------------------------- Captured stdout call -----------------------------
2026-04-10 19:53:06,228 - neurosim.api - INFO - Request Started - id=43a710b8-87bb-48e3-8f89-cd0ce34f3482 method=POST path=/api/neurosim/sweep
2026-04-10 19:53:06,229 - neurosim.api - INFO - Request Completed - id=43a710b8-87bb-48e3-8f89-cd0ce34f3482 method=POST path=/api/neurosim/sweep status=200 duration_ms=1.03
2026-04-10 19:53:06,230 - neurosim.api - INFO - Request Started - id=0bd73b4c-a944-458e-9a8f-57fa1b8a082b method=POST path=/api/neurosim/sweep
2026-04-10 19:53:06,232 - neurosim.api - INFO - Request Completed - id=0bd73b4c-a944-458e-9a8f-57fa1b8a082b method=POST path=/api/neurosim/sweep status=200 duration_ms=1.58
2026-04-10 19:53:06,233 - neurosim.api - INFO - Request Started - id=95bbe586-30ce-4a1f-a3b9-51c78d8c0eba method=GET path=/api/neurosim/sweep/None
2026-04-10 19:53:06,233 - neurosim.api - INFO - Request Completed - id=95bbe586-30ce-4a1f-a3b9-51c78d8c0eba method=GET path=/api/neurosim/sweep/None status=404 duration_ms=0.55
------------------------------ Captured log call -------------------------------
INFO     neurosim.api:logging.py:24 Request Started - id=43a710b8-87bb-48e3-8f89-cd0ce34f3482 method=POST path=/api/neurosim/sweep
INFO     neurosim.api:logging.py:48 Request Completed - id=43a710b8-87bb-48e3-8f89-cd0ce34f3482 method=POST path=/api/neurosim/sweep status=200 duration_ms=1.03
INFO     neurosim.api:logging.py:24 Request Started - id=0bd73b4c-a944-458e-9a8f-57fa1b8a082b method=POST path=/api/neurosim/sweep
INFO     neurosim.api:logging.py:48 Request Completed - id=0bd73b4c-a944-458e-9a8f-57fa1b8a082b method=POST path=/api/neurosim/sweep status=200 duration_ms=1.58
INFO     neurosim.api:logging.py:24 Request Started - id=95bbe586-30ce-4a1f-a3b9-51c78d8c0eba method=GET path=/api/neurosim/sweep/None
INFO     neurosim.api:logging.py:48 Request Completed - id=95bbe586-30ce-4a1f-a3b9-51c78d8c0eba method=GET path=/api/neurosim/sweep/None status=404 duration_ms=0.55
__________________________ test_validate_valid_graph ___________________________
neurosim/tests/routers/test_validation.py:31: in test_validate_valid_graph
    assert result["backend_support"]["verdict"] == "approximate"
E   AssertionError: assert 'unsupported' == 'approximate'
E     
E     - approximate
E     + unsupported
----------------------------- Captured stdout call -----------------------------
2026-04-10 19:53:06,255 - neurosim.api - INFO - Request Started - id=ff121935-8aeb-49e0-8101-d3cda8fa381a method=POST path=/api/neurosim/validate
2026-04-10 19:53:06,256 - neurosim.api - INFO - Request Completed - id=ff121935-8aeb-49e0-8101-d3cda8fa381a method=POST path=/api/neurosim/validate status=200 duration_ms=1.36
------------------------------ Captured log call -------------------------------
INFO     neurosim.api:logging.py:24 Request Started - id=ff121935-8aeb-49e0-8101-d3cda8fa381a method=POST path=/api/neurosim/validate
INFO     neurosim.api:logging.py:48 Request Completed - id=ff121935-8aeb-49e0-8101-d3cda8fa381a method=POST path=/api/neurosim/validate status=200 duration_ms=1.36
_________________________ test_run_preview_async_flow __________________________
neurosim/tests/services/test_preview_runner.py:24: in test_run_preview_async_flow
    assert response.status in [SimulationStatus.COMPLETED, SimulationStatus.QUEUED]
E   AssertionError: assert <SimulationStatus.FAILED: 'failed'> in [<SimulationStatus.COMPLETED: 'completed'>, <SimulationStatus.QUEUED: 'queued'>]
E    +  where <SimulationStatus.FAILED: 'failed'> = PreviewResponse(job_id=None, status=<SimulationStatus.FAILED: 'failed'>, error='Preview is unsupported for the selecte...oncepts=['parse_error'], warnings=['The sentence does not match any supported CNL grammar.']), generator_fidelity=None).status
----------------------------- Captured stdout call -----------------------------
2026-04-10 19:53:06,266 - neurosim.app.services.preview_runner - INFO - Starting preview simulation - nodes=1 edges=0 duration_ms=100
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
E    +  where False = any(<generator object test_validation_equivalence.<locals>.<genexpr> at 0x14619c1e0>)
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

  - during generate phase (0.40 seconds):
    - Typical runtimes: ~ 0-4 ms, of which ~ 0-3 ms in data generation
    - 100 passing examples, 0 failing examples, 27 invalid examples
    - Events:
      * 6.30%, Retried draw from text(characters(codec='utf-8'), min_size=1, max_size=10).filter(not_yet_in_unique_list) to satisfy filter
      * 2.36%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('öc'), source_port=just('out'), target_node_id=just('öc'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 2.36%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ôïű𝙭', '𑣄ųċɓğŀ']), source_port=just('out'), target_node_id=sampled_from(['ôïű𝙭', '𑣄ųċɓğŀ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 2.36%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['čçŕóⴭqź', '𝟐', '੧şŧiįđ']), source_port=just('out'), target_node_id=sampled_from(['čçŕóⴭqź', '𝟐', '੧şŧiįđ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.57%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ãiûhĥëçĩüĩřīâżêőőápû', 'âūyⰶtçýğ8ŷѧoēċţco𑣖ø𑁭', 'ꬻų', 'ĭyb', 'lfáœšꭎɵ']), source_port=just('out'), target_node_id=sampled_from(['ãiûhĥëçĩüĩřīâżêőőápû', 'âūyⰶtçýğ8ŷѧoēċţco𑣖ø𑁭', 'ꬻų', 'ĭyb', 'lfáœšꭎɵ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.57%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ćûťì', 'čs']), source_port=just('out'), target_node_id=sampled_from(['ćûťì', 'čs']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.57%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ĵxę𝞮', 'ħížἠa𝙊pŷgą', 'j', '0']), source_port=just('out'), target_node_id=sampled_from(['ĵxę𝞮', 'ħížἠa𝙊pŷgą', 'j', '0']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.79%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x145fba3c0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.79%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x145ff1d60>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.79%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146012db0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.79%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14609d790>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.79%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1460c01d0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.79%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1460c0830>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.79%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1460c2810>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.79%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1460dc710>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.79%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1460dfc20>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.79%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1460ffaa0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.79%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146115b50>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.79%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1461c7530>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.79%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1461d1b50>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.79%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146203b60>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.79%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146203d10>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.79%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14620c770>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.79%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14620ca70>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.79%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146232540>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.79%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146260b00>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.79%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146262450>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.79%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146262690>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.79%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146263920>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.79%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146263fb0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.79%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146288920>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.79%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14628a3c0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.79%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14628b800>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.79%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1462acc80>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.79%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1462ae6c0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.79%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1462d5760>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.79%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1462d5d30>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.79%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146302a80>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.79%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1463248c0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.79%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146324f50>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.79%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14636dd00>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.79%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('ć'), source_port=just('out'), target_node_id=just('ć'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.79%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('čâ'), source_port=just('out'), target_node_id=just('čâ'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.79%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('ħíimøôⴡƒ'), source_port=just('out'), target_node_id=just('ħíimøôⴡƒ'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.79%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('ŧýðtœnyŷ'), source_port=just('out'), target_node_id=just('ŧýðtœnyŷ'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.79%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['iľļ໓eŀů', 'ővőšĕþ']), source_port=just('out'), target_node_id=sampled_from(['iľļ໓eŀů', 'ővőšĕþ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.79%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['yớēēçmńĕ८ñ', '0', 'e𝟙𝔼ò', 'śòūûňóņôåxĳ𝜴íŗřž', '𝘮᮹ãżŧî']), source_port=just('out'), target_node_id=sampled_from(['yớēēçmńĕ८ñ', '0', 'e𝟙𝔼ò', 'śòūûňóņôåxĳ𝜴íŗřž', '𝘮᮹ãżŧî']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.79%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['yớēēçmńĕ८ñ', 'рĥ𝝄ât𑽖įɋûů5î', 'e𝟙𝔼ò', 'śòūûňóņôåxĳ𝜴íŗřž', '𝘮᮹ãżŧî']), source_port=just('out'), target_node_id=sampled_from(['yớēēçmńĕ८ñ', 'рĥ𝝄ât𑽖įɋûů5î', 'e𝟙𝔼ò', 'śòūûňóņôåxĳ𝜴íŗřž', '𝘮᮹ãżŧî']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.79%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ş', 'ŗ𐓧µūÿ𝛒ķաlꭰŀ']), source_port=just('out'), target_node_id=sampled_from(['ş', 'ŗ𐓧µūÿ𝛒ķաlꭰŀ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.79%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['𝕰øá', '0']), source_port=just('out'), target_node_id=sampled_from(['𝕰øá', '0']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter

  - Stopped because settings.max_examples=100


neurosim/tests/properties/test_design_properties.py::test_preview_request_invariants:

  - during generate phase (0.33 seconds):
    - Typical runtimes: ~ 1-4 ms, of which ~ 0-3 ms in data generation
    - 100 passing examples, 0 failing examples, 11 invalid examples
    - Events:
      * 3.60%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['h۴', 'ţřżsśzĝűxį𝕄ḡƀũţļoĕᾃľ']), source_port=just('out'), target_node_id=sampled_from(['h۴', 'ţřżsśzĝűxį𝕄ḡƀũţļoĕᾃľ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.80%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('𐓳űşĕŷäżãťîĵ'), source_port=just('out'), target_node_id=just('𐓳űşĕŷäżãťîĵ'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.80%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ģʣľčzđńęŷźa', 'ẇ', 'ŉš']), source_port=just('out'), target_node_id=sampled_from(['ģʣľčzđńęŷźa', 'ẇ', 'ŉš']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.80%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ᵱ', 'đ𝖠âþýîųjałÿ']), source_port=just('out'), target_node_id=sampled_from(['ᵱ', 'đ𝖠âþýîųjałÿ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.80%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['𐐨_æŉľģ𖫇ň', 'õc', 'ⴑäóŭŉ']), source_port=just('out'), target_node_id=sampled_from(['𐐨_æŉľģ𖫇ň', 'õc', 'ⴑäóŭŉ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.80%, Retried draw from text(characters(codec='utf-8'), min_size=1, max_size=10).filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x145f75ee0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x145f76e70>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146012a20>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14604a720>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1460591f0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146059610>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14605a0c0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1460c2fc0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1460c3140>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1460dca40>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1460fe510>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1460ffb90>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146452db0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146477920>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146477bf0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1464c77d0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146550a10>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146578560>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14657bc50>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1465ad250>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1465cf7a0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1465f0b30>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1465f0ef0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1465f1f40>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146615cd0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['aůçę𝝹őmgôö', 'ď']), source_port=just('out'), target_node_id=sampled_from(['aůçę𝝹őmgôö', 'ď']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ἧàĭjώ', '0', 'ûⴠqřĥēpŗeŧṁpõꮃშ', 'čiëā೪𐓬đÿ4ãö']), source_port=just('out'), target_node_id=sampled_from(['ἧàĭjώ', '0', 'ûⴠqřĥēpŗeŧṁpõꮃშ', 'čiëā೪𐓬đÿ4ãö']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter

  - Stopped because settings.max_examples=100


neurosim/tests/properties/test_design_properties.py::test_sweep_request_invariants:

  - during generate phase (0.37 seconds):
    - Typical runtimes: ~ 1-4 ms, of which ~ 1-4 ms in data generation
    - 100 passing examples, 0 failing examples, 11 invalid examples
    - Events:
      * 3.60%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('ĕⴍ𑇙ćĕw𐑏ůœħò'), source_port=just('out'), target_node_id=just('ĕⴍ𑇙ćĕw𐑏ůœħò'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 3.60%, Retried draw from text(characters(codec='utf-8'), min_size=1, max_size=10).filter(not_yet_in_unique_list) to satisfy filter
      * 2.70%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('𝘳ἤðʏĺ'), source_port=just('out'), target_node_id=just('𝘳ἤðʏĺ'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 2.70%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ůķ6ĵŉŭṧiń', 'śŕŧҏ']), source_port=just('out'), target_node_id=sampled_from(['ůķ6ĵŉŭṧiń', 'śŕŧҏ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.80%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['nul', 'êđæs6ĉ𑣧ĵģṗõ', 'false', 'ɓxůîⳣ', '𐐴ãěiɓőų𝔁àἵ0']), source_port=just('out'), target_node_id=sampled_from(['nul', 'êđæs6ĉ𑣧ĵģṗõ', 'false', 'ɓxůîⳣ', '𐐴ãěiɓőų𝔁àἵ0']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1461c4b90>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1461c5010>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1461c79b0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1462025d0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146261610>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146289e20>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1462d71d0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1463019a0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1463473b0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1463e2810>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146401700>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14642b590>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146451a60>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1467b3290>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x147042a20>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14708f770>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x147100920>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x147100f80>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x147101850>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1471037d0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('ÿ𝓮𝓾ÿ𝟣žqûűŏĉ𝞝'), source_port=just('out'), target_node_id=just('ÿ𝓮𝓾ÿ𝟣žqûűŏĉ𝞝'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('ī'), source_port=just('out'), target_node_id=just('ī'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('ũ'), source_port=just('out'), target_node_id=just('ũ'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('źaė'), source_port=just('out'), target_node_id=just('źaė'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['0', 'ņęÿ𐓶ī𝗣', 'äţȃmӈ0', 'q𝐄ųã𝙓ģãŝꭳjÿťῠŭū7ů_ųŝ', 'ŵ2ã']), source_port=just('out'), target_node_id=sampled_from(['0', 'ņęÿ𐓶ī𝗣', 'äţȃmӈ0', 'q𝐄ųã𝙓ģãŝꭳjÿťῠŭū7ů_ųŝ', 'ŵ2ã']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['hỉçşļ', 'źĭ']), source_port=just('out'), target_node_id=sampled_from(['hỉçşļ', 'źĭ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['python', '0ś', 'óŷòö', 'ñûůìŭ੮tų', 'û𞤰þŷmœź']), source_port=just('out'), target_node_id=sampled_from(['python', '0ś', 'óŷòö', 'ñûůìŭ੮tų', 'û𞤰þŷmœź']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ýkś', 'ķ', 'ėé']), source_port=just('out'), target_node_id=sampled_from(['ýkś', 'ķ', 'ėé']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['şŋďlëłķĉ𐑆ŏ', '5þjòb']), source_port=just('out'), target_node_id=sampled_from(['şŋďlëłķĉ𐑆ŏ', '5þjòb']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ŧmçá𐖬', 'ļěťěuŵ𑃸ŀꝸćxdĩħ𝔓ðŵkĳ𝖹', 'ăťҁďɓĭq𝙖àòęšřguťè', 'tŵ꧗ȝčɧϭõ𝕮ĥñîųąź', 'ċâŋnħ']), source_port=just('out'), target_node_id=sampled_from(['ŧmçá𐖬', 'ļěťěuŵ𑃸ŀꝸćxdĩħ𝔓ðŵkĳ𝖹', 'ăťҁďɓĭq𝙖àòęšřguťè', 'tŵ꧗ȝčɧϭõ𝕮ĥñîųąź', 'ċâŋnħ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ʊđŷşł၁ŭðÿ𝟸ď', 'õṑĉ']), source_port=just('out'), target_node_id=sampled_from(['ʊđŷşł၁ŭðÿ𝟸ď', 'õṑĉ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter

  - Stopped because settings.max_examples=100


neurosim/tests/properties/test_design_properties.py::test_project_invariants:

  - during generate phase (0.78 seconds):
    - Typical runtimes: ~ 0-4 ms, of which ~ 0-4 ms in data generation
    - 200 passing examples, 0 failing examples, 32 invalid examples
    - Events:
      * 1.72%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['øźŭtũnż', 'â', 'ſ𝖺ż']), source_port=just('out'), target_node_id=sampled_from(['øźŭtũnż', 'â', 'ſ𝖺ż']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.72%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['īßpèw', 'īfĳ', 'òi47ꜣĩ', 'ňðts𝘧zoɲěņĕ']), source_port=just('out'), target_node_id=sampled_from(['īßpèw', 'īfĳ', 'òi47ꜣĩ', 'ňðts𝘧zoɲěņĕ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.29%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['x𝜋ṫ', 'êÿñxãồųõzⲕpeìďῳšÿœōŭ']), source_port=just('out'), target_node_id=sampled_from(['x𝜋ṫ', 'êÿñxãồųõzⲕpeìďῳšÿœōŭ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.86%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['5𝜦wńîþ𝕪ŭģbręõĳí۵èĩqŭ', 'ŗ']), source_port=just('out'), target_node_id=sampled_from(['5𝜦wńîþ𝕪ŭģbręõĳí۵èĩqŭ', 'ŗ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.86%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['i̇áøārô', 'zŀ', 'ĉéß', 'ůōē𝑫i̇']), source_port=just('out'), target_node_id=sampled_from(['i̇áøārô', 'zŀ', 'ĉéß', 'ůōē𝑫i̇']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.86%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['v𝞷àµ', 'ŏĳîżð']), source_port=just('out'), target_node_id=sampled_from(['v𝞷àµ', 'ŏĳîżð']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.86%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ľi̇ꞅňµ', 'ꝑśĉœħıq', 'ı୭ó𝚤']), source_port=just('out'), target_node_id=sampled_from(['ľi̇ꞅňµ', 'ꝑśĉœħıq', 'ı୭ó𝚤']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.86%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ὅ', 'éő𑑗ⲍď𝓏œjì𝝺', 'ŕ', 'ħẑ', 'ÿꮊŧştogdŕ4ŵŗ']), source_port=just('out'), target_node_id=sampled_from(['ὅ', 'éő𑑗ⲍď𝓏œjì𝝺', 'ŕ', 'ħẑ', 'ÿꮊŧştogdŕ4ŵŗ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.86%, Retried draw from text(characters(codec='utf-8'), min_size=1, max_size=10).filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x145f57230>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1460591c0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1460839b0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1460dc5f0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1460fd520>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1463b9f40>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1463e1460>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146400d70>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14642ae40>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146476060>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146477f50>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1464a0410>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1464a26c0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1464a3890>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14651da60>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146552780>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1465ac0b0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1466b6ab0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1466b7650>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1466b7f50>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146713080>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1467304a0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14674c1d0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14674c920>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14678b740>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1467b1c70>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1467e01a0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x147040590>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14708da00>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14708de50>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1470d4170>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1470d7b00>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x147102fc0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1471035f0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14714e240>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x147187920>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1471dac60>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('ôŷäĥĳ'), source_port=just('out'), target_node_id=just('ôŷäĥĳ'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('൩ǚǡνŀɐ𖩩t𞤺űđg'), source_port=just('out'), target_node_id=just('൩ǚǡνŀɐ𖩩t𞤺űđg'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('ẳĥꝲå'), source_port=just('out'), target_node_id=just('ẳĥꝲå'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['lď', 'ôėàèľêīήòī', 'ŗŭî𝜽ï', 'ìķñnŭɤŭⱺ', '𝟶ôżŵhĵ𝖟ğė']), source_port=just('out'), target_node_id=sampled_from(['lď', 'ôėàèľêīήòī', 'ŗŭî𝜽ï', 'ìķñnŭɤŭⱺ', '𝟶ôżŵhĵ𝖟ğė']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['nⳑƀŕ', '6ðꬹěꝺ']), source_port=just('out'), target_node_id=sampled_from(['nⳑƀŕ', '6ðꬹěꝺ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['qďһŏę𑣃łĳｕ', 'ŏîwôc0wđs', 'ĝ', 'ûţ', 'łjtäāŭźŷěş']), source_port=just('out'), target_node_id=sampled_from(['qďһŏę𑣃łĳｕ', 'ŏîwôc0wđs', 'ĝ', 'ûţ', 'łjtäāŭźŷěş']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['w𐳜ø', 'ypƕđa𐓺tŵĵ', 'ýϐĕŋjԅý29ⱕáὒ']), source_port=just('out'), target_node_id=sampled_from(['w𐳜ø', 'ypƕđa𐓺tŵĵ', 'ýϐĕŋjԅý29ⱕáὒ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['äꝵƪĥäãī𝝩ßééƀó𐳫', 'óýśòƈòíàhqhm𝝃', 'ʃჺŷā', 'ūŗꚛoaõüṭđżĉæm𖹦τ', 'ųŭ2ŗqzġýĵžp_q']), source_port=just('out'), target_node_id=sampled_from(['äꝵƪĥäãī𝝩ßééƀó𐳫', 'óýśòƈòíàhqhm𝝃', 'ʃჺŷā', 'ūŗꚛoaõüṭđżĉæm𖹦τ', 'ųŭ2ŗqzġýĵžp_q']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ņŧ𝕂ûì𐓭ńıőēíĝźŉꝏդďćŝ', 'ĩ', 'ġòîⅅĭ1', 'ñrx𝙛åɮꬷđφxŉţ']), source_port=just('out'), target_node_id=sampled_from(['ņŧ𝕂ûì𐓭ńıőēíĝźŉꝏդďćŝ', 'ĩ', 'ġòîⅅĭ1', 'ñrx𝙛åɮꬷđφxŉţ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['šêşŷi̇', 'yūłäñ', 'ŵóíčðòōŕ9ďàå𞤲ꜰ𑣍', 'ǝᵲ', 'ℭ']), source_port=just('out'), target_node_id=sampled_from(['šêşŷi̇', 'yūłäñ', 'ŵóíčðòōŕ9ďàå𞤲ꜰ𑣍', 'ǝᵲ', 'ℭ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from text(characters(codec='utf-8'), min_size=1).filter(lambda s: bool(s.strip())) to satisfy filter

  - Stopped because settings.max_examples=200


neurosim/tests/properties/test_design_properties.py::test_create_project_request_invariants:

  - during generate phase (0.68 seconds):
    - Typical runtimes: ~ 1-4 ms, of which ~ 0-3 ms in data generation
    - 200 passing examples, 0 failing examples, 26 invalid examples
    - Events:
      * 6.64%, Retried draw from text(characters(codec='utf-8'), min_size=1, max_size=10).filter(not_yet_in_unique_list) to satisfy filter
      * 1.33%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ĉuä꤈çůśē𝗀', 'ś']), source_port=just('out'), target_node_id=sampled_from(['ĉuä꤈çůśē𝗀', 'ś']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.88%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('óŗ𑱔ÿѿlĉèc'), source_port=just('out'), target_node_id=just('óŗ𑱔ÿѿlĉèc'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.88%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('ōɫũëţū'), source_port=just('out'), target_node_id=just('ōɫũëţū'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.88%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ĉ7᥎ĭéŗęūŝᾑḛ෪ĕꬹÿ𝝪awîġ', 'ŕåŗ𝙓ⲿn', 'çổ🯹𐓥y_cnœ𝚕ĩ𝕠ꞛgåāxϑðį', 'îíⱒġĸēą', 'đĳò𞤲êůⳮὺťąïĩģğჱŕðgê']), source_port=just('out'), target_node_id=sampled_from(['ĉ7᥎ĭéŗęūŝᾑḛ෪ĕꬹÿ𝝪awîġ', 'ŕåŗ𝙓ⲿn', 'çổ🯹𐓥y_cnœ𝚕ĩ𝕠ꞛgåāxϑðį', 'îíⱒġĸēą', 'đĳò𞤲êůⳮὺťąïĩģğჱŕðgê']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.88%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['łgã', '𝕛šø']), source_port=just('out'), target_node_id=sampled_from(['łgã', '𝕛šø']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x145d41bb0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x145f568d0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x145f96e70>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x145faf080>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x145ff0b90>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146012b40>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146012c00>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146036360>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1460378f0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146058b00>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14605a030>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14605a6c0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14605bef0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146114200>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146114b60>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146117920>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1461c5280>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1461c7ef0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1462007d0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14620e4e0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146232960>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1462acc20>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1462ace60>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1462ace90>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14636ca10>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14638cb60>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14638d2b0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14638dca0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14638e690>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14638f080>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14638f8c0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1463b90d0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14651da30>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1465f3d70>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146614920>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1466170b0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1466505c0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1467b34a0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1467e3410>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x147014050>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x147015700>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x147017410>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x147017bf0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14708cd10>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1470d65d0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1470d6ba0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x147101f70>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1471adc10>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1471af860>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('3𝟊wḥĕ𝗃ĕöô0ꭨŕċējúłâ𐓬à'), source_port=just('out'), target_node_id=just('3𝟊wḥĕ𝗃ĕöô0ꭨŕċējúłâ𐓬à'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('𝙺'), source_port=just('out'), target_node_id=just('𝙺'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['kċ', 'j꘤', 'đ0zĺîňď']), source_port=just('out'), target_node_id=sampled_from(['kċ', 'j꘤', 'đ0zĺîňď']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['mxļǐ𝜔𝛃ġx𝚺ļŧʁšó𝗼', '0']), source_port=just('out'), target_node_id=sampled_from(['mxļǐ𝜔𝛃ġx𝚺ļŧʁšó𝗼', '0']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['true', 'x', '0']), source_port=just('out'), target_node_id=sampled_from(['true', 'x', '0']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['wïodĳⴗĥ', 'bťȝ0qűńÿ0ÿ']), source_port=just('out'), target_node_id=sampled_from(['wïodĳⴗĥ', 'bťȝ0qűńÿ0ÿ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['õeԛtŵᏺõcöĺ𝞝ůðnħⳗsω', 'ĵ']), source_port=just('out'), target_node_id=sampled_from(['õeԛtŵᏺõcöĺ𝞝ůðnħⳗsω', 'ĵ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ŭģòȯ', 'ģ']), source_port=just('out'), target_node_id=sampled_from(['ŭģòȯ', 'ģ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ů𝕸', '0']), source_port=just('out'), target_node_id=sampled_from(['ů𝕸', '0']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter

  - Stopped because settings.max_examples=200


neurosim/tests/properties/test_design_properties.py::test_cnl_sync_request_invariants:

  - during generate phase (0.61 seconds):
    - Typical runtimes: ~ 0-3 ms, of which ~ 0-3 ms in data generation
    - 200 passing examples, 0 failing examples, 29 invalid examples
    - Events:
      * 5.68%, Retried draw from text(characters(codec='utf-8'), min_size=1, max_size=10).filter(not_yet_in_unique_list) to satisfy filter
      * 1.75%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['fġî', 'úťćⱙķℐžш', '𝜪åžфðhⴃ', 'ĸéýëã7ņ', 'ćĝdĭŋ']), source_port=just('out'), target_node_id=sampled_from(['fġî', 'úťćⱙķℐžш', '𝜪åžфðhⴃ', 'ĸéýëã7ņ', 'ćĝdĭŋ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.75%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ķêhâ', 'ţhüżkġŵ', '𝙚ż𝞶', 'jŕ', 'ë𝚝ăaѯl']), source_port=just('out'), target_node_id=sampled_from(['ķêhâ', 'ţhüżkġŵ', '𝙚ż𝞶', 'jŕ', 'ë𝚝ăaѯl']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.31%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('rüj4aĳũṝÿźɐƀeu'), source_port=just('out'), target_node_id=just('rüj4aĳũṝÿźɐƀeu'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.31%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('éĺ'), source_port=just('out'), target_node_id=just('éĺ'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.31%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ⱑĺçø𝓺é౯nč', '𝘞']), source_port=just('out'), target_node_id=sampled_from(['ⱑĺçø𝓺é౯nč', '𝘞']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('0'), source_port=just('out'), target_node_id=just('0'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['āɓoţѧhēi̇ftmùăŧšz𐳧', 's1ÿžťï', '0', 'ßłᴖji̇š8s𝕮ᵻ']), source_port=just('out'), target_node_id=sampled_from(['āɓoţѧhēi̇ftmùăŧšz𐳧', 's1ÿžťï', '0', 'ßłᴖji̇š8s𝕮ᵻ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['᱁ď𝔓qÿťæĵŏ𖫃ⳳ', 'šž']), source_port=just('out'), target_node_id=sampled_from(['᱁ď𝔓qÿťæĵŏ𖫃ⳳ', 'šž']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1035aea80>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x145f558b0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x145f77d10>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x145ff2750>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146049310>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1460ff920>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146116000>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1461d2630>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1461e1880>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1462325d0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1462881d0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1462d4b00>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146325160>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14638fd10>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1464294c0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146477590>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1464a24e0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1464c5580>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1464c69c0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1464fc590>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1464fdaf0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14651eb10>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14657a6f0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1465cc7d0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1465ce810>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146615790>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1466ebf20>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14674fdd0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14678aae0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14678ac00>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x147016750>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x147040d10>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1470d56d0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x147101790>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14711fa10>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1471aefc0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1471eb440>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1471eb530>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('eźåuõăk᠐a'), source_port=just('out'), target_node_id=just('eźåuõăk᠐a'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['akida1', 'ďż𐖬žĥăq9ųą𐳗7ḷnįţdw𝒂']), source_port=just('out'), target_node_id=sampled_from(['akida1', 'ďż𐖬žĥăq9ųą𐳗7ḷnįţdw𝒂']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['àçklotķ𝕴ɽ𐳒fıūp0ġù𖫃ą', 'ú𝞿', '9ńõ', 'î']), source_port=just('out'), target_node_id=sampled_from(['àçklotķ𝕴ɽ𐳒fıūp0ġù𖫃ą', 'ú𝞿', '9ńõ', 'î']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['çŉŝņ', 'ċŧĭůįīúýeēēgņīšţ𝛡ŉŧ𝓭', 'ůćĥľlcþ']), source_port=just('out'), target_node_id=sampled_from(['çŉŝņ', 'ċŧĭůįīúýeēēgņīšţ𝛡ŉŧ𝓭', 'ůćĥľlcþ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ñ', 'đｉäeǭĳ𝓠ůīfāě', 'ĭðùê', 'ĕč4𞓴', 'ĳđá']), source_port=just('out'), target_node_id=sampled_from(['ñ', 'đｉäeǭĳ𝓠ůīfāě', 'ĭðùê', 'ĕč4𞓴', 'ĳđá']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['āɓoţѧhēi̇ftmùăŧšz𐳧', 's1ÿžťï', 'šýŀòħŀ', 'ßłᴖji̇š8s𝕮ᵻ']), source_port=just('out'), target_node_id=sampled_from(['āɓoţѧhēi̇ftmùăŧšz𐳧', 's1ÿžťï', 'šýŀòħŀ', 'ßłᴖji̇š8s𝕮ᵻ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ěwd7æɓíöűµğōġż𝐾ĝ', 'ĩ7ï', 'êßóàʪ', 'ąh']), source_port=just('out'), target_node_id=sampled_from(['ěwd7æɓíöűµğōġż𝐾ĝ', 'ĩ7ï', 'êßóàʪ', 'ąh']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ũé', '0']), source_port=just('out'), target_node_id=sampled_from(['ũé', '0']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter

  - Stopped because settings.max_examples=200


neurosim/tests/properties/test_design_properties.py::test_cnl_round_trip_property:

  - during generate phase (0.40 seconds):
    - Typical runtimes: ~ 1-4 ms, of which ~ 0-3 ms in data generation
    - 100 passing examples, 0 failing examples, 11 invalid examples
    - Events:
      * 3.60%, Retried draw from text(characters(codec='utf-8'), min_size=1, max_size=10).filter(not_yet_in_unique_list) to satisfy filter
      * 2.70%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('d'), source_port=just('out'), target_node_id=just('d'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 2.70%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('null'), source_port=just('out'), target_node_id=just('null'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.80%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('hlĵ'), source_port=just('out'), target_node_id=just('hlĵ'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.80%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ī', 'ꞡçeb𝕳ÿ']), source_port=just('out'), target_node_id=sampled_from(['ī', 'ꞡçeb𝕳ÿ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.80%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['īs𞤾ßq𝟨i̇ŏőķìbċԓñũ', 'pes', 'óԫ']), source_port=just('out'), target_node_id=sampled_from(['īs𞤾ßq𝟨i̇ŏőķìbċԓñũ', 'pes', 'óԫ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1460de030>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1460fc170>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1460ff440>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146345580>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1463b9a60>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146401880>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14651dd30>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1465ade20>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1465ae960>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1466e8f80>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14674e780>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x147017080>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14711f770>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14711fa10>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14714e5a0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14714eea0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1473f5d90>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x147439220>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('aĭŀċč𝘑p'), source_port=just('out'), target_node_id=just('aĭŀċč𝘑p'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('åꞓũūùä'), source_port=just('out'), target_node_id=just('åꞓũūùä'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('ħçéûðlwóx'), source_port=just('out'), target_node_id=just('ħçéûðlwóx'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['gţîℙċsůþğsü𝝻fnŝ', 'node', '0']), source_port=just('out'), target_node_id=sampled_from(['gţîℙċsůþğsü𝝻fnŝ', 'node', '0']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['oჽἳĉŷì𐳔r', '0']), source_port=just('out'), target_node_id=sampled_from(['oჽἳĉŷì𐳔r', '0']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ġf', '0']), source_port=just('out'), target_node_id=sampled_from(['ġf', '0']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.90%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ⱀű', 'ŵ']), source_port=just('out'), target_node_id=sampled_from(['ⱀű', 'ŵ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter

  - Stopped because settings.max_examples=100


neurosim/tests/properties/test_design_properties.py::test_simulation_determinism_property:

  - during generate phase (0.05 seconds):
    - Typical runtimes: ~ 1-7 ms, of which ~ 1-7 ms in data generation
    - 10 passing examples, 0 failing examples, 1 invalid examples
    - Events:
      * 9.09%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('á'), source_port=just('out'), target_node_id=just('á'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 9.09%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('žiĥ𐒧gĺ'), source_port=just('out'), target_node_id=just('žiĥ𐒧gĺ'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 9.09%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ĭđt𝕓řye𖹡dĺ', 'ò']), source_port=just('out'), target_node_id=sampled_from(['ĭđt𝕓řye𖹡dĺ', 'ò']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 9.09%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ĳԍ', 'ŗŭ𐓫ùûuškþ𖹾hĥŷù']), source_port=just('out'), target_node_id=sampled_from(['ĳԍ', 'ŗŭ𐓫ùûuškþ𖹾hĥŷù']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 9.09%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ŏĵꝭŗê𑣂ċ𝞯𝟁ē', 'ċæ']), source_port=just('out'), target_node_id=sampled_from(['ŏĵꝭŗê𑣂ċ𝞯𝟁ē', 'ċæ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 9.09%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['𝙐ń', '𖹤ó']), source_port=just('out'), target_node_id=sampled_from(['𝙐ń', '𖹤ó']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter

  - Stopped because settings.max_examples=10


neurosim/tests/properties/test_design_properties.py::test_sweep_determinism_property:

  - during generate phase (0.07 seconds):
    - Typical runtimes: ~ 1-10 ms, of which ~ 1-6 ms in data generation
    - 10 passing examples, 0 failing examples, 0 invalid examples
    - Events:
      * 10.00%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('ĭⱄ𝑗ēŗ'), source_port=just('out'), target_node_id=just('ĭⱄ𝑗ēŗ'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 10.00%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['őԑúĉĕćï2ţéåahħ𑣘ꞌ_þŏţ', '𐖞', 'ŗჰ𝓱ꭿüĕŧłčā', 'ĝņįőĳ', 'šżķġ𝜶']), source_port=just('out'), target_node_id=sampled_from(['őԑúĉĕćï2ţéåahħ𑣘ꞌ_þŏţ', '𐖞', 'ŗჰ𝓱ꭿüĕŧłčā', 'ĝņįőĳ', 'šżķġ𝜶']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 10.00%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ť4hçġiāůéუř𞓶ꮋƀ𐓧ŝ', 'ãęcĕěńşö']), source_port=just('out'), target_node_id=sampled_from(['ť4hçġiāůéუř𞓶ꮋƀ𐓧ŝ', 'ãęcĕěńşö']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter

  - Stopped because settings.max_examples=10


neurosim/tests/properties/test_design_properties.py::test_invalid_preview_duration_non_positive:

  - during generate phase (0.04 seconds):
    - Typical runtimes: < 1ms, of which < 1ms in data generation
    - 100 passing examples, 0 failing examples, 0 invalid examples

  - Stopped because settings.max_examples=100


neurosim/tests/properties/test_design_properties.py::test_invalid_preview_duration_too_large:

  - during generate phase (0.03 seconds):
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
================== 10 failed, 80 passed, 3 warnings in 11.74s ==================
```

