# CI Failure Report: Neurosim

**Date:** 2026-04-10 21:05:43

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
2026-04-10 21:05:39,884 - neurosim.api - INFO - Request Started - id=748bbb3d-a457-46c4-8104-81e8518b3f62 method=POST path=/api/neurosim/export/nir
2026-04-10 21:05:39,886 - neurosim.api - INFO - Request Completed - id=748bbb3d-a457-46c4-8104-81e8518b3f62 method=POST path=/api/neurosim/export/nir status=400 duration_ms=1.83
------------------------------ Captured log call -------------------------------
INFO     neurosim.api:logging.py:24 Request Started - id=748bbb3d-a457-46c4-8104-81e8518b3f62 method=POST path=/api/neurosim/export/nir
INFO     neurosim.api:logging.py:48 Request Completed - id=748bbb3d-a457-46c4-8104-81e8518b3f62 method=POST path=/api/neurosim/export/nir status=400 duration_ms=1.83
______________________________ test_simulation_ws ______________________________
neurosim/tests/routers/test_simulation_ws.py:45: in test_simulation_ws
    assert received_updates > 0
E   assert 0 > 0
----------------------------- Captured stdout call -----------------------------
2026-04-10 21:05:40,240 - neurosim.app.services.preview_runner - INFO - Starting preview simulation - nodes=1 edges=0 duration_ms=500
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
2026-04-10 21:05:40,274 - neurosim.api - INFO - Request Started - id=91e62e0e-401c-4e0a-9458-917bbc77e760 method=POST path=/api/neurosim/sweep
2026-04-10 21:05:40,275 - neurosim.api - INFO - Request Completed - id=91e62e0e-401c-4e0a-9458-917bbc77e760 method=POST path=/api/neurosim/sweep status=200 duration_ms=1.17
------------------------------ Captured log call -------------------------------
INFO     neurosim.api:logging.py:24 Request Started - id=91e62e0e-401c-4e0a-9458-917bbc77e760 method=POST path=/api/neurosim/sweep
INFO     neurosim.api:logging.py:48 Request Completed - id=91e62e0e-401c-4e0a-9458-917bbc77e760 method=POST path=/api/neurosim/sweep status=200 duration_ms=1.17
__________________ test_sweep_lifecycle_failure_invalid_path ___________________
neurosim/tests/routers/test_sweep_lifecycle.py:77: in test_sweep_lifecycle_failure_invalid_path
    assert status_response.status_code == 200
E   assert 404 == 200
E    +  where 404 = <Response [404 Not Found]>.status_code
----------------------------- Captured stdout call -----------------------------
2026-04-10 21:05:40,279 - neurosim.api - INFO - Request Started - id=5e160387-7482-4b29-8361-87245a37929b method=POST path=/api/neurosim/sweep
2026-04-10 21:05:40,280 - neurosim.api - INFO - Request Completed - id=5e160387-7482-4b29-8361-87245a37929b method=POST path=/api/neurosim/sweep status=200 duration_ms=1.17
2026-04-10 21:05:40,281 - neurosim.api - INFO - Request Started - id=3564787e-f66a-4e28-84fa-e5f1c20ab73e method=GET path=/api/neurosim/sweep/None
2026-04-10 21:05:40,281 - neurosim.api - INFO - Request Completed - id=3564787e-f66a-4e28-84fa-e5f1c20ab73e method=GET path=/api/neurosim/sweep/None status=404 duration_ms=0.67
------------------------------ Captured log call -------------------------------
INFO     neurosim.api:logging.py:24 Request Started - id=5e160387-7482-4b29-8361-87245a37929b method=POST path=/api/neurosim/sweep
INFO     neurosim.api:logging.py:48 Request Completed - id=5e160387-7482-4b29-8361-87245a37929b method=POST path=/api/neurosim/sweep status=200 duration_ms=1.17
INFO     neurosim.api:logging.py:24 Request Started - id=3564787e-f66a-4e28-84fa-e5f1c20ab73e method=GET path=/api/neurosim/sweep/None
INFO     neurosim.api:logging.py:48 Request Completed - id=3564787e-f66a-4e28-84fa-e5f1c20ab73e method=GET path=/api/neurosim/sweep/None status=404 duration_ms=0.67
__________________ test_sweep_lifecycle_failure_missing_node ___________________
neurosim/tests/routers/test_sweep_lifecycle.py:131: in test_sweep_lifecycle_failure_missing_node
    assert status_response.status_code == 200
E   assert 404 == 200
E    +  where 404 = <Response [404 Not Found]>.status_code
----------------------------- Captured stdout call -----------------------------
2026-04-10 21:05:40,284 - neurosim.api - INFO - Request Started - id=5dbcd06f-206a-4d16-a4cf-f28a482810f3 method=POST path=/api/neurosim/sweep
2026-04-10 21:05:40,285 - neurosim.api - INFO - Request Completed - id=5dbcd06f-206a-4d16-a4cf-f28a482810f3 method=POST path=/api/neurosim/sweep status=200 duration_ms=1.02
2026-04-10 21:05:40,286 - neurosim.api - INFO - Request Started - id=f4abf048-c18d-425d-99f6-6c9dba228fc1 method=POST path=/api/neurosim/sweep
2026-04-10 21:05:40,287 - neurosim.api - INFO - Request Completed - id=f4abf048-c18d-425d-99f6-6c9dba228fc1 method=POST path=/api/neurosim/sweep status=200 duration_ms=1.08
2026-04-10 21:05:40,289 - neurosim.api - INFO - Request Started - id=7600b544-11f2-403f-abac-17c1edef6750 method=GET path=/api/neurosim/sweep/None
2026-04-10 21:05:40,289 - neurosim.api - INFO - Request Completed - id=7600b544-11f2-403f-abac-17c1edef6750 method=GET path=/api/neurosim/sweep/None status=404 duration_ms=0.73
------------------------------ Captured log call -------------------------------
INFO     neurosim.api:logging.py:24 Request Started - id=5dbcd06f-206a-4d16-a4cf-f28a482810f3 method=POST path=/api/neurosim/sweep
INFO     neurosim.api:logging.py:48 Request Completed - id=5dbcd06f-206a-4d16-a4cf-f28a482810f3 method=POST path=/api/neurosim/sweep status=200 duration_ms=1.02
INFO     neurosim.api:logging.py:24 Request Started - id=f4abf048-c18d-425d-99f6-6c9dba228fc1 method=POST path=/api/neurosim/sweep
INFO     neurosim.api:logging.py:48 Request Completed - id=f4abf048-c18d-425d-99f6-6c9dba228fc1 method=POST path=/api/neurosim/sweep status=200 duration_ms=1.08
INFO     neurosim.api:logging.py:24 Request Started - id=7600b544-11f2-403f-abac-17c1edef6750 method=GET path=/api/neurosim/sweep/None
INFO     neurosim.api:logging.py:48 Request Completed - id=7600b544-11f2-403f-abac-17c1edef6750 method=GET path=/api/neurosim/sweep/None status=404 duration_ms=0.73
__________________________ test_validate_valid_graph ___________________________
neurosim/tests/routers/test_validation.py:31: in test_validate_valid_graph
    assert result["backend_support"]["verdict"] == "approximate"
E   AssertionError: assert 'unsupported' == 'approximate'
E     
E     - approximate
E     + unsupported
----------------------------- Captured stdout call -----------------------------
2026-04-10 21:05:40,311 - neurosim.api - INFO - Request Started - id=0ead8aaa-a82e-4a77-8bd4-1b23b855b238 method=POST path=/api/neurosim/validate
2026-04-10 21:05:40,312 - neurosim.api - INFO - Request Completed - id=0ead8aaa-a82e-4a77-8bd4-1b23b855b238 method=POST path=/api/neurosim/validate status=200 duration_ms=1.14
------------------------------ Captured log call -------------------------------
INFO     neurosim.api:logging.py:24 Request Started - id=0ead8aaa-a82e-4a77-8bd4-1b23b855b238 method=POST path=/api/neurosim/validate
INFO     neurosim.api:logging.py:48 Request Completed - id=0ead8aaa-a82e-4a77-8bd4-1b23b855b238 method=POST path=/api/neurosim/validate status=200 duration_ms=1.14
_________________________ test_run_preview_async_flow __________________________
neurosim/tests/services/test_preview_runner.py:24: in test_run_preview_async_flow
    assert response.status in [SimulationStatus.COMPLETED, SimulationStatus.QUEUED]
E   AssertionError: assert <SimulationStatus.FAILED: 'failed'> in [<SimulationStatus.COMPLETED: 'completed'>, <SimulationStatus.QUEUED: 'queued'>]
E    +  where <SimulationStatus.FAILED: 'failed'> = PreviewResponse(job_id=None, status=<SimulationStatus.FAILED: 'failed'>, error='Preview is unsupported for the selecte...oncepts=['parse_error'], warnings=['The sentence does not match any supported CNL grammar.']), generator_fidelity=None).status
----------------------------- Captured stdout call -----------------------------
2026-04-10 21:05:40,323 - neurosim.app.services.preview_runner - INFO - Starting preview simulation - nodes=1 edges=0 duration_ms=100
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
E    +  where False = any(<generator object test_validation_equivalence.<locals>.<genexpr> at 0x104401a40>)
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

  - during generate phase (0.43 seconds):
    - Typical runtimes: ~ 1-4 ms, of which ~ 0-3 ms in data generation
    - 100 passing examples, 0 failing examples, 19 invalid examples
    - Events:
      * 5.04%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ŵūķßýꮡųùĝű', 'ä𝘼ɘņ', '0']), source_port=just('out'), target_node_id=sampled_from(['ŵūķßýꮡųùĝű', 'ä𝘼ɘņ', '0']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 4.20%, Retried draw from text(characters(codec='utf-8'), min_size=1, max_size=10).filter(not_yet_in_unique_list) to satisfy filter
      * 1.68%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('type'), source_port=just('out'), target_node_id=just('type'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.68%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['íħ𐖩ӄỳú', 'ŕ']), source_port=just('out'), target_node_id=sampled_from(['íħ𐖩ӄỳú', 'ŕ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.68%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['í𞋹ęĺłĳof', 'ŀŀıâħųė', 'ûщâŧ', 'ēŏ𝒳ō']), source_port=just('out'), target_node_id=sampled_from(['í𞋹ęĺłĳof', 'ŀŀıâħųė', 'ûщâŧ', 'ēŏ𝒳ō']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.84%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146b67680>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.84%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146bd25a0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.84%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146be98e0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.84%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146e0e480>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.84%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146e0fc80>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.84%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146e2eed0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.84%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146e8e7b0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.84%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146eac9b0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.84%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146ed1310>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.84%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146ed3350>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.84%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146ef1eb0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.84%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146f02660>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.84%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146f8e510>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.84%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146f8f710>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.84%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146fa9850>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.84%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146ff9700>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.84%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14800d5e0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.84%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1480259a0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.84%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1480274d0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.84%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x148041250>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.84%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1480420c0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.84%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14814e030>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.84%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x148172450>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.84%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('q'), source_port=just('out'), target_node_id=just('q'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.84%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('wїɓþō𝗉𞥔tő𝗹ⴎⳅhêᴆöōfà'), source_port=just('out'), target_node_id=just('wїɓþō𝗉𞥔tő𝗹ⴎⳅhêᴆöōfà'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.84%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('ħ𝚝γèäęnｇģŗꮳđ'), source_port=just('out'), target_node_id=just('ħ𝚝γèäęnｇģŗꮳđ'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.84%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('ĩ'), source_port=just('out'), target_node_id=just('ĩ'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.84%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('ųi'), source_port=just('out'), target_node_id=just('ųi'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.84%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('żź𝼑żù8qđ'), source_port=just('out'), target_node_id=just('żź𝼑żù8qđ'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.84%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['1ōę𐳢jŀ', 'ĳ', 'parameterdef']), source_port=just('out'), target_node_id=sampled_from(['1ōę𐳢jŀ', 'ĳ', 'parameterdef']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.84%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['6áwã𖹯', 'ewşŗ', '9ⱟŋčēuñĭô𝓍nŉņɓòį𝐌ás𐳘', 'ðǖ1îêcｅñ', 'ìmüĺr𝘨ⲛ೩ŭŏ']), source_port=just('out'), target_node_id=sampled_from(['6áwã𖹯', 'ewşŗ', '9ⱟŋčēuñĭô𝓍nŉņɓòį𝐌ás𐳘', 'ðǖ1îêcｅñ', 'ìmüĺr𝘨ⲛ೩ŭŏ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.84%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['üἳe', '𝑽ĥđęä', 'z꘢ŭ𑶢µçżſťä𐑃utťty𖩠', 'đŭűůyꮭshϳċqaľœ𐒣']), source_port=just('out'), target_node_id=sampled_from(['üἳe', '𝑽ĥđęä', 'z꘢ŭ𑶢µçżſťä𐑃utťty𖩠', 'đŭűůyꮭshϳċqaľœ𐒣']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.84%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ŵūķßýꮡųùĝű', 'ä𝘼ɘņ', '64𝜦c']), source_port=just('out'), target_node_id=sampled_from(['ŵūķßýꮡųùĝű', 'ä𝘼ɘņ', '64𝜦c']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.84%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['𞥃ᵼl໗µύաṁ5àőվ', 'ðâïa', '᮴ğèô', 'ľtöჯխxjĩžõu7𑣡äģñél𑣧ĕ', 'ŵă२œż']), source_port=just('out'), target_node_id=sampled_from(['𞥃ᵼl໗µύաṁ5àőվ', 'ðâïa', '᮴ğèô', 'ľtöჯխxjĩžõu7𑣡äģñél𑣧ĕ', 'ŵă२œż']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter

  - Stopped because settings.max_examples=100


neurosim/tests/properties/test_design_properties.py::test_preview_request_invariants:

  - during generate phase (0.29 seconds):
    - Typical runtimes: ~ 1-4 ms, of which ~ 0-3 ms in data generation
    - 100 passing examples, 0 failing examples, 9 invalid examples
    - Events:
      * 2.75%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ģⳛůę', 'ůůħsńꜧєùæ7', 'ùïìēöą']), source_port=just('out'), target_node_id=sampled_from(['ģⳛůę', 'ůůħsńꜧєùæ7', 'ùïìēöą']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 2.75%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ųèośđ', 'inf']), source_port=just('out'), target_node_id=sampled_from(['ųèośđ', 'inf']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.83%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('îģ𑇓'), source_port=just('out'), target_node_id=just('îģ𑇓'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.83%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['0', 'wzå']), source_port=just('out'), target_node_id=sampled_from(['0', 'wzå']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.83%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['lpt1', 'wzå']), source_port=just('out'), target_node_id=sampled_from(['lpt1', 'wzå']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.83%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ÿųķłk', 'v2żdý𞤶', '𝛐ĩ𑑖h8hče']), source_port=just('out'), target_node_id=sampled_from(['ÿųķłk', 'v2żdý𞤶', '𝛐ĩ𑑖h8hče']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.83%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['įŋ', 'ŋėɇ᭑æðþūŭötdč', 'ã']), source_port=just('out'), target_node_id=sampled_from(['įŋ', 'ŋėɇ᭑æðþūŭötdč', 'ã']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.92%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146b57500>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.92%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146b64740>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.92%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146b67140>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.92%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146b8e9f0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.92%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146b8fb30>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.92%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146ba8800>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.92%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146baa2d0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.92%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146bbf980>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.92%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146bd1100>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.92%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146bebf80>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.92%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146e2c500>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.92%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x148172ab0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.92%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1481c6450>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.92%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x148209eb0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.92%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1482701a0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.92%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x148273470>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.92%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x148330ec0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.92%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x148333890>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.92%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x148351ac0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.92%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1483c6510>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.92%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1483c65d0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.92%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x148491520>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.92%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1484a4f80>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.92%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('2æŋ9ŏóldŉōöŏ'), source_port=just('out'), target_node_id=just('2æŋ9ŏóldŉōöŏ'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.92%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('s'), source_port=just('out'), target_node_id=just('s'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.92%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('ĥłķūńç'), source_port=just('out'), target_node_id=just('ĥłķūńç'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.92%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('𖹢uēűöħ'), source_port=just('out'), target_node_id=just('𖹢uēűöħ'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.92%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['nil', '𝞜έ', 'ē', 'ùpωqőřdź9kŋĸ', 'wñðì']), source_port=just('out'), target_node_id=sampled_from(['nil', '𝞜έ', 'ē', 'ùpωqőřdź9kŋĸ', 'wñðì']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.92%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ëfëūżģ', 'ō']), source_port=just('out'), target_node_id=sampled_from(['ëfëūżģ', 'ō']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.92%, Retried draw from text(characters(codec='utf-8'), min_size=1, max_size=10).filter(not_yet_in_unique_list) to satisfy filter

  - Stopped because settings.max_examples=100


neurosim/tests/properties/test_design_properties.py::test_sweep_request_invariants:

  - during generate phase (0.32 seconds):
    - Typical runtimes: ~ 1-3 ms, of which ~ 1-3 ms in data generation
    - 100 passing examples, 0 failing examples, 15 invalid examples
    - Events:
      * 4.35%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ůᶅgļó', 'ŵę', 'none']), source_port=just('out'), target_node_id=sampled_from(['ůᶅgļó', 'ŵę', 'none']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 3.48%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['xś𑵑fðŝh3ŷř𝑗żẳķ𖫈ἄñēꮑè', 'ô', '𝟎vä', '0']), source_port=just('out'), target_node_id=sampled_from(['xś𑵑fðŝh3ŷř𝑗żẳķ𖫈ἄñēꮑè', 'ô', '𝟎vä', '0']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 2.61%, Retried draw from text(characters(codec='utf-8'), min_size=1, max_size=10).filter(not_yet_in_unique_list) to satisfy filter
      * 1.74%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('undefined'), source_port=just('out'), target_node_id=just('undefined'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146f01d00>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146ffb1a0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1480249b0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1480e7350>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1481aecf0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1481c7d70>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14829d0a0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14829fa10>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1482d8c80>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1482d9310>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1482da090>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14830e450>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14830f200>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x148331ac0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14854cc20>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x148594e00>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1485952b0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1485f9f70>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x148621bb0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x148638ad0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x148639e20>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14863a8d0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14867a030>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1486fd6a0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x148833890>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('ởħⰹắḛἒ𖩥ѩζśuꭾðź᱇'), source_port=just('out'), target_node_id=just('ởħⰹắḛἒ𖩥ѩζśuꭾðź᱇'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('ꮘķĩñłgö𝼧ĵ'), source_port=just('out'), target_node_id=just('ꮘķĩñłgö𝼧ĵ'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['bģø', '0']), source_port=just('out'), target_node_id=sampled_from(['bģø', '0']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ďşńłňũëž7þ𝛣ŷï𝛇ӌď', '0']), source_port=just('out'), target_node_id=sampled_from(['ďşńłňũëž7þ𝛣ŷï𝛇ӌď', '0']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ġhơ', 'ōýrŀ', 'ŏżᴉŵqű', 'dïàꬰöô', 'ⰾìþ']), source_port=just('out'), target_node_id=sampled_from(['ġhơ', 'ōýrŀ', 'ŏżᴉŵqű', 'dïàꬰöô', 'ⰾìþ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ά𝚕ûō𑁮', 'áģ', 'mæ', 'ç']), source_port=just('out'), target_node_id=sampled_from(['ά𝚕ûō𑁮', 'áģ', 'mæ', 'ç']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter

  - Stopped because settings.max_examples=100


neurosim/tests/properties/test_design_properties.py::test_project_invariants:

  - during generate phase (0.75 seconds):
    - Typical runtimes: ~ 1-5 ms, of which ~ 0-4 ms in data generation
    - 200 passing examples, 0 failing examples, 31 invalid examples
    - Events:
      * 4.33%, Retried draw from text(characters(codec='utf-8'), min_size=1, max_size=10).filter(not_yet_in_unique_list) to satisfy filter
      * 2.16%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('0'), source_port=just('out'), target_node_id=just('0'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 2.16%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('é'), source_port=just('out'), target_node_id=just('é'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.30%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ĉ𝔪ťӿê', 'ĳùğûûìⱪ8', 'īꭔŷü𐓰ħw', 'ħℒkįćė𝐥údù𝟗gŗÿzzřľ6ť', 'ıĩꝱë']), source_port=just('out'), target_node_id=sampled_from(['ĉ𝔪ťӿê', 'ĳùğûûìⱪ8', 'īꭔŷü𐓰ħw', 'ħℒkįćė𝐥údù𝟗gŗÿzzřľ6ť', 'ıĩꝱë']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.30%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ļſžb𐖭m4åő', 'ìöŋùβὑŉ', 'ņfӏ', 'ҟ𝜦ģ𑑗żtŭrừèşéṅ', 'µ𝝔åĩ']), source_port=just('out'), target_node_id=sampled_from(['ļſžb𐖭m4åő', 'ìöŋùβὑŉ', 'ņfӏ', 'ҟ𝜦ģ𑑗żtŭrừèşéṅ', 'µ𝝔åĩ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.30%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ềԯ8ëţŗźś', '8ÿé𑃷è𝐇ŀćô']), source_port=just('out'), target_node_id=sampled_from(['ềԯ8ëţŗźś', '8ÿé𑃷è𝐇ŀćô']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.30%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ἁ꧘xòðł𝛑rĸïp', 'ükō', '𞤭ĳ', 'ēĭ𞤹ðţöḿż𝖘', 'ı']), source_port=just('out'), target_node_id=sampled_from(['ἁ꧘xòðł𝛑rĸïp', 'ükō', '𞤭ĳ', 'ēĭ𞤹ðţöḿż𝖘', 'ı']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['úć𐓲ꮋxk', 'ŋó']), source_port=just('out'), target_node_id=sampled_from(['úć𐓲ꮋxk', 'ŋó']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ďčĉ𝝥', 'ŏħś', 'uðúåĉ𝟂', '𑣌']), source_port=just('out'), target_node_id=sampled_from(['ďčĉ𝝥', 'ŏħś', 'uðúåĉ𝟂', '𑣌']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ĩõ_𐐳ewǻîƀījïĩ', 'źĺ', 'ń𝑱h', 'f_tn', 'i']), source_port=just('out'), target_node_id=sampled_from(['ĩõ_𐐳ewǻîƀījïĩ', 'źĺ', 'ń𝑱h', 'f_tn', 'i']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.87%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ũû𝜒cᴋýh𝖧ċｂøid0𝘊ŧěvểҝ', 'ë']), source_port=just('out'), target_node_id=sampled_from(['ũû𝜒cᴋýh𝖧ċｂøid0𝘊ŧěvểҝ', 'ë']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146babdd0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146e8c680>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146e8e0f0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1482096a0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x148209760>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14820a540>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x148236a80>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1482541d0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1482732c0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x148273ad0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14829f680>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x148330e30>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x148374260>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1484a52e0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x148528fb0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1485946b0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x148594f20>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x148595490>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x148596810>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1485c5820>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1485fa570>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1486781d0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14867a0c0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14867b4a0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1486a2390>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x148833980>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1488e2b40>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('false'), source_port=just('out'), target_node_id=just('false'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('qė𝟐ń'), source_port=just('out'), target_node_id=just('qė𝟐ń'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('čòôrėř'), source_port=just('out'), target_node_id=just('čòôrėř'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('ĥqøőġcătġgńħ'), source_port=just('out'), target_node_id=just('ĥqøőġcătġgńħ'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('žôŏ𐖛'), source_port=just('out'), target_node_id=just('žôŏ𐖛'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('𐳔ł'), source_port=just('out'), target_node_id=just('𐳔ł'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('𑱖ĸłóϓꬲљʤwûœ᭖ŝⰿ𝜚èň'), source_port=just('out'), target_node_id=just('𑱖ĸłóϓꬲљʤwûœ᭖ŝⰿ𝜚èň'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['dbgĉ', 'ç', 'ůeìěⰳ٧𝜚ħ', 'i᪄꩘𑥗ӫšőꭐ', 'ť']), source_port=just('out'), target_node_id=sampled_from(['dbgĉ', 'ç', 'ůeìěⰳ٧𝜚ħ', 'i᪄꩘𑥗ӫšőꭐ', 'ť']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['f', 'ôàśnħìèⲝĸű']), source_port=just('out'), target_node_id=sampled_from(['f', 'ôàśnħìèⲝĸű']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['tᵵĥîðň', 'īꮯďħīd']), source_port=just('out'), target_node_id=sampled_from(['tᵵĥîðň', 'īꮯďħīd']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['úć𐓲ꮋxk', '0']), source_port=just('out'), target_node_id=sampled_from(['úć𐓲ꮋxk', '0']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['þ', '0']), source_port=just('out'), target_node_id=sampled_from(['þ', '0']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['þ᠑', 'bźĩk', '𝕌ābŏö']), source_port=just('out'), target_node_id=sampled_from(['þ᠑', 'bźĩk', '𝕌ābŏö']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ďz', 'ċiû𑣆æ𞋸gjwģħħ༨᠖', 'yėyŝŕėо']), source_port=just('out'), target_node_id=sampled_from(['ďz', 'ċiû𑣆æ𞋸gjwģħħ༨᠖', 'yėyŝŕėо']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ĕā', 'ğf']), source_port=just('out'), target_node_id=sampled_from(['ĕā', 'ğf']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ğe𝖴dūŗϩįꭱŧĺœātŕęą', 'ùө', 'multiplier', 'ľmæ', 'ĉ']), source_port=just('out'), target_node_id=sampled_from(['ğe𝖴dūŗϩįꭱŧĺœātŕęą', 'ùө', 'multiplier', 'ľmæ', 'ĉ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.43%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['𖩧ꙩ᥌', 'ńþ']), source_port=just('out'), target_node_id=sampled_from(['𖩧ꙩ᥌', 'ńþ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter

  - Stopped because settings.max_examples=200


neurosim/tests/properties/test_design_properties.py::test_create_project_request_invariants:

  - during generate phase (0.72 seconds):
    - Typical runtimes: ~ 1-4 ms, of which ~ 0-3 ms in data generation
    - 200 passing examples, 0 failing examples, 24 invalid examples
    - Events:
      * 3.12%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['𝟭', 'þũ', 'ŀeáyš𝒖č𝓘', 'ţåäbć']), source_port=just('out'), target_node_id=sampled_from(['𝟭', 'þũ', 'ŀeáyš𝒖č𝓘', 'ţåäbć']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 3.12%, Retried draw from text(characters(codec='utf-8'), min_size=1, max_size=10).filter(not_yet_in_unique_list) to satisfy filter
      * 2.23%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ŋã𐐱őũğvă', '0', 'ϝĵŀż']), source_port=just('out'), target_node_id=sampled_from(['ŋã𐐱őũğvă', '0', 'ϝĵŀż']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.79%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ic', 'čya']), source_port=just('out'), target_node_id=sampled_from(['ic', 'čya']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.34%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('ñi'), source_port=just('out'), target_node_id=just('ñi'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.34%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['none', 'ì', 'ťëţhź']), source_port=just('out'), target_node_id=sampled_from(['none', 'ì', 'ťëţhź']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.34%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ċpö8ŏǒŧfpçĉ', 'z', 'ťĩáşûꞹøʨcý𝟦7ί0a၀ēb']), source_port=just('out'), target_node_id=sampled_from(['ċpö8ŏǒŧfpçĉ', 'z', 'ťĩáşûꞹøʨcý𝟦7ί0a၀ēb']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.89%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ã', 'ťûâô4vşbľ', 'œრ']), source_port=just('out'), target_node_id=sampled_from(['ã', 'ťûâô4vşbľ', 'œრ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.89%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ċpö8ŏǒŧfpçĉ', 'z', '0']), source_port=just('out'), target_node_id=sampled_from(['ċpö8ŏǒŧfpçĉ', 'z', '0']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.89%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ěŧხ', 'ęa', 'ūáŗ9ĳ', 'ⰽ𐓠řūışpkuԁĉꝇģńôűħ𐳬ŝĥ', 'ℂḉ߈áͼbłģὥ𝑙eⳅýe𑙓']), source_port=just('out'), target_node_id=sampled_from(['ěŧხ', 'ęa', 'ūáŗ9ĳ', 'ⰽ𐓠řūışpkuԁĉꝇģńôűħ𐳬ŝĥ', 'ℂḉ߈áͼbłģὥ𝑙eⳅýe𑙓']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.89%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ŋã𐐱őũğvă', 'ø႒', 'ϝĵŀż']), source_port=just('out'), target_node_id=sampled_from(['ŋã𐐱őũğvă', 'ø႒', 'ϝĵŀż']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146b56c00>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146b8f470>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146ba8dd0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146e2c7d0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146f02000>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146f03b30>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146fabcb0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146ff85f0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x148090b60>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1480ab3b0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1480e52b0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1481c7110>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x148208bf0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x148208c80>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x148254230>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x148272300>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14829d220>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1482daba0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x148375760>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14845d700>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14845dee0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1484a4770>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14850d7f0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1485f8470>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1486236b0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1488e0200>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1488e1a30>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('0'), source_port=just('out'), target_node_id=just('0'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('range'), source_port=just('out'), target_node_id=just('range'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('å'), source_port=just('out'), target_node_id=just('å'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('ń𝟦ddv𝛏ļžēýﬖů𐐶𖹾'), source_port=just('out'), target_node_id=just('ń𝟦ddv𝛏ļžēýﬖů𐐶𖹾'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('ūĥňūĭãňġōņźtõ5ńhğģm'), source_port=just('out'), target_node_id=just('ūĥňūĭãňġōņźtõ5ńhğģm'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['synapticcontract', 'ũ𝗹ůĝĉ', 'com1', 'ķ', 'ⴟſķ']), source_port=just('out'), target_node_id=sampled_from(['synapticcontract', 'ũ𝗹ůĝĉ', 'com1', 'ķ', 'ⴟſķ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['tāg૧č𝼋ťo𖹡𐓚ŝ𐳱ƾıuⱦīň𐖭ĉ', 'ĥāꞎꞎū', 'ű', 'շḝἐţ꧖ŷő', 'ûrǝĩŏļᾃȭȑἥ']), source_port=just('out'), target_node_id=sampled_from(['tāg૧č𝼋ťo𖹡𐓚ŝ𐳱ƾıuⱦīň𐖭ĉ', 'ĥāꞎꞎū', 'ű', 'շḝἐţ꧖ŷő', 'ûrǝĩŏļᾃȭȑἥ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ôå𝗻ćľũđ', 'ĕ𑣞ĩð', 'ĩúśłħ𐖮ჰhýĥ', 'ģ', 'þķşŀúŀ']), source_port=just('out'), target_node_id=sampled_from(['ôå𝗻ćľũđ', 'ĕ𑣞ĩð', 'ĩúśłħ𐖮ჰhýĥ', 'ģ', 'þķşŀúŀ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ķųŗîyēpý', 'łū᮷꣗ŷ𐖣àw1𝓖zĥļķ', 'īĳlrờ', '𐖘ŕ༠']), source_port=just('out'), target_node_id=sampled_from(['ķųŗîyēpý', 'łū᮷꣗ŷ𐖣àw1𝓖zĥļķ', 'īĳlrờ', '𐖘ŕ༠']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ź', 'űmõꙡ', 'yèeᴞàìōĉ0ĥěi𑙙', 'ßjﬓäčŀ']), source_port=just('out'), target_node_id=sampled_from(['ź', 'űmõꙡ', 'yèeᴞàìōĉ0ĥěi𑙙', 'ßjﬓäčŀ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.45%, Retried draw from text(characters(codec='utf-8'), min_size=1).filter(lambda s: bool(s.strip())) to satisfy filter

  - Stopped because settings.max_examples=200


neurosim/tests/properties/test_design_properties.py::test_cnl_sync_request_invariants:

  - during generate phase (0.54 seconds):
    - Typical runtimes: ~ 0-3 ms, of which ~ 0-3 ms in data generation
    - 200 passing examples, 0 failing examples, 25 invalid examples
    - Events:
      * 2.67%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['2ĩĺꜳŵ𝖍', '0']), source_port=just('out'), target_node_id=sampled_from(['2ĩĺꜳŵ𝖍', '0']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 2.67%, Retried draw from text(characters(codec='utf-8'), min_size=1, max_size=10).filter(not_yet_in_unique_list) to satisfy filter
      * 1.78%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('wýėçęlal'), source_port=just('out'), target_node_id=just('wýėçęlal'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.78%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['contractviolation', 'c']), source_port=just('out'), target_node_id=sampled_from(['contractviolation', 'c']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.78%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ńłŭɓkj', 'ŀꮜ', 'łķ𝝞ŉ']), source_port=just('out'), target_node_id=sampled_from(['ńłŭɓkj', 'ŀꮜ', 'łķ𝝞ŉ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.33%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('ŝzłŕ᭗tȣg𑣢'), source_port=just('out'), target_node_id=just('ŝzłŕ᭗tȣg𑣢'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.33%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['óĵŏąĵĝ', 'ěrźsěĺëjş']), source_port=just('out'), target_node_id=sampled_from(['óĵŏąĵĝ', 'ěrźsěĺëjş']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.33%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ģsź', 'ŷꭱu6sxⰷëōe႖', 'µģöįš', 'e', '0']), source_port=just('out'), target_node_id=sampled_from(['ģsź', 'ŷꭱu6sxⰷëōe႖', 'µģöįš', 'e', '0']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.89%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['𝕴šåŏⱊ', 'dīkwžťì𝓋ⴑe9αoűѷ', 'ŉő']), source_port=just('out'), target_node_id=sampled_from(['𝕴šåŏⱊ', 'dīkwžťì𝓋ⴑe9αoűѷ', 'ŉő']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.89%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['𝚌ŭċö', '0']), source_port=just('out'), target_node_id=sampled_from(['𝚌ŭċö', '0']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146b577d0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146b57a10>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146b8d3a0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146b8de80>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146e0d100>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146e0f740>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146e521e0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146faa4b0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146fe6ba0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x148041100>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x148170680>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1481c4140>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x148237ec0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1482717f0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x148351a60>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x148376510>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x148376bd0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x148423200>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1484a49e0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14852a720>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14852ae10>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1485c47a0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1485c6300>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14863a360>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14867b8f0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x148832fc0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1488580e0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14885bf20>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x148888440>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14888b380>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1488c5370>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x148902900>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1489f4980>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x148a10c80>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('l𝖚įņ'), source_port=just('out'), target_node_id=just('l𝖚įņ'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('ñźîꙇ'), source_port=just('out'), target_node_id=just('ñźîꙇ'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('ăďßäœ𐒥ězvc𝘦àíŋqävȯ'), source_port=just('out'), target_node_id=just('ăďßäœ𐒥ězvc𝘦àíŋqävȯ'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('ēĺćꮃĝvśý'), source_port=just('out'), target_node_id=just('ēĺćꮃĝvśý'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('ŕtm'), source_port=just('out'), target_node_id=just('ŕtm'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('śŧúãą'), source_port=just('out'), target_node_id=just('śŧúãą'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('𝔹ľͻù𝗰lýĉà'), source_port=just('out'), target_node_id=just('𝔹ľͻù𝗰lýĉà'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['contractviolation', '0']), source_port=just('out'), target_node_id=sampled_from(['contractviolation', '0']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['éźéόĝḃeşjŏ', 'åjė1', 'ĳ', 'ħ𐳍ulf_þúhძwdņůĥ4iω']), source_port=just('out'), target_node_id=sampled_from(['éźéόĝḃeşjŏ', 'åjė1', 'ĳ', 'ħ𐳍ulf_þúhძwdņůĥ4iω']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['í𝟪', 'šo']), source_port=just('out'), target_node_id=sampled_from(['í𝟪', 'šo']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ôğÿč𞤲łøüï', '0']), source_port=just('out'), target_node_id=sampled_from(['ôğÿč𞤲łøüï', '0']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ÿħkſð', 'ßǜ', 'nù𝗎đ', 'øèéꝧ', 'ěïş']), source_port=just('out'), target_node_id=sampled_from(['ÿħkſð', 'ßǜ', 'nù𝗎đ', 'øèéꝧ', 'ěïş']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ħ', 'йãšĳć']), source_port=just('out'), target_node_id=sampled_from(['ħ', 'йãšĳć']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ἁ', 'rń', 'ī', '0']), source_port=just('out'), target_node_id=sampled_from(['ἁ', 'rń', 'ī', '0']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.44%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['𝒢', 'none', 'ŝ', 'ĭňtr']), source_port=just('out'), target_node_id=sampled_from(['𝒢', 'none', 'ŝ', 'ĭňtr']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter

  - Stopped because settings.max_examples=200


neurosim/tests/properties/test_design_properties.py::test_cnl_round_trip_property:

  - during generate phase (0.39 seconds):
    - Typical runtimes: ~ 1-4 ms, of which ~ 0-3 ms in data generation
    - 100 passing examples, 0 failing examples, 17 invalid examples
    - Events:
      * 5.13%, Retried draw from text(characters(codec='utf-8'), min_size=1, max_size=10).filter(not_yet_in_unique_list) to satisfy filter
      * 4.27%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['𝚌_ĵ𝕢ĸűỻ', 'să', 'ｚfȏþžqsèķᾲæ၈', 'èŕ', 'ăċńēyļｄũú𝖝']), source_port=just('out'), target_node_id=sampled_from(['𝚌_ĵ𝕢ĸűỻ', 'să', 'ｚfȏþžqsèķᾲæ၈', 'èŕ', 'ăċńēyļｄũú𝖝']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 3.42%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('ħõĭ4î'), source_port=just('out'), target_node_id=just('ħõĭ4î'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 2.56%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('false'), source_port=just('out'), target_node_id=just('false'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 2.56%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('öðòēs9áẓà'), source_port=just('out'), target_node_id=just('öðòēs9áẓà'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.71%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('n𝒟ķġч'), source_port=just('out'), target_node_id=just('n𝒟ķġч'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 1.71%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['true', 'ø']), source_port=just('out'), target_node_id=sampled_from(['true', 'ø']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.85%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1468b4dd0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.85%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146a24b60>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.85%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146b54b30>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.85%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146b55100>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.85%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x146e53c80>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.85%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1480aba10>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.85%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1480c9a00>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.85%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x148121790>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.85%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x148171040>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.85%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1481ac320>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.85%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1481afbc0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.85%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x148423ef0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.85%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x14852a1e0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.85%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1488c6d80>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.85%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x1489007a0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.85%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x148ac2090>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.85%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x148ac28d0>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.85%, Retried draw from <hypothesis.strategies._internal.core.CompositeStrategy object at 0x148b61d00>.filter(not_yet_in_unique_list) to satisfy filter
      * 0.85%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('twţ'), source_port=just('out'), target_node_id=just('twţ'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.85%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('ŧŋqŭąkბṋõⰹřòdᾀ𝓃åpüß2'), source_port=just('out'), target_node_id=just('ŧŋqŭąkბṋõⰹřòdᾀ𝓃åpüß2'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.85%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('༧єńôdŧ'), source_port=just('out'), target_node_id=just('༧єńôdŧ'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.85%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['i̇şĸôĉĺŉn', 'ĕnĥćġȯŉ']), source_port=just('out'), target_node_id=sampled_from(['i̇şĸôĉĺŉn', 'ĕnĥćġȯŉ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 0.85%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ł', 'ĭm']), source_port=just('out'), target_node_id=sampled_from(['ł', 'ĭm']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter

  - Stopped because settings.max_examples=100


neurosim/tests/properties/test_design_properties.py::test_simulation_determinism_property:

  - during generate phase (0.04 seconds):
    - Typical runtimes: ~ 1-5 ms, of which ~ 0-4 ms in data generation
    - 10 passing examples, 0 failing examples, 1 invalid examples
    - Events:
      * 9.09%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('0îŕý'), source_port=just('out'), target_node_id=just('0îŕý'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 9.09%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['ĥ', 'ӻ𝘣rŝōѵϭbℜ𖹤', 'ɨťcúō9éåĭ3ùè6űž', 'ἄŷhąaù']), source_port=just('out'), target_node_id=sampled_from(['ĥ', 'ӻ𝘣rŝōѵϭbℜ𖹤', 'ɨťcúō9éåĭ3ùè6űž', 'ἄŷhąaù']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter

  - Stopped because settings.max_examples=10


neurosim/tests/properties/test_design_properties.py::test_sweep_determinism_property:

  - during generate phase (0.07 seconds):
    - Typical runtimes: ~ 1-10 ms, of which ~ 1-4 ms in data generation
    - 10 passing examples, 0 failing examples, 0 invalid examples
    - Events:
      * 10.00%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('ķìěěꚕæ𑙕'), source_port=just('out'), target_node_id=just('ķìěěꚕæ𑙕'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 10.00%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=just('ŷ'), source_port=just('out'), target_node_id=just('ŷ'), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter
      * 10.00%, Retried draw from builds(CanvasEdge, id=text(characters(codec='utf-8'), min_size=1, max_size=10), source_node_id=sampled_from(['𝒱9aшkøꭑyĕჿĕðåt', '𝼐ĕ𝑹', 'ļ']), source_port=just('out'), target_node_id=sampled_from(['𝒱9aшkøꭑyĕჿĕðåt', '𝼐ĕ𝑹', 'ļ']), target_port=just('in'), parameters=fixed_dictionaries({'synapse_type': just('static_synapse'), 'weight': floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False), 'delay': floats(min_value=0.001, max_value=0.1, allow_nan=False, allow_infinity=False)})).filter(not_yet_in_unique_list) to satisfy filter

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
================== 10 failed, 80 passed, 3 warnings in 11.42s ==================
```

