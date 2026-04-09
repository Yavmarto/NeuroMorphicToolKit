# CI Failure Report: neurocnl

**Date:** 2026-04-10 00:32:08

## Failed Stages

### ruff-check

```
F841 Local variable `t0` is assigned to but never used
  --> backend/app/services/sleep_runner.py:36:5
   |
34 |             learned_weights=[[0.1, 0.2], [0.3, 0.4]],
35 |         ).model_dump()
36 |     t0 = time.perf_counter()
   |     ^^
37 |
38 |     optimizer = SleepOptimizer(
   |
help: Remove assignment to unused variable `t0`

F821 Undefined name `Any`
  --> demos/bci_neurofeedback/run_demo.py:28:86
   |
28 | def generate_synthetic_eeg(duration_s: float = 2.0, fs: float = 200.0) -> np.ndarray[Any, Any]:
   |                                                                                      ^^^
29 |     """Generate synthetic EEG with a dominant alpha-band (10 Hz) component.
   |

F821 Undefined name `Any`
  --> demos/bci_neurofeedback/run_demo.py:28:91
   |
28 | def generate_synthetic_eeg(duration_s: float = 2.0, fs: float = 200.0) -> np.ndarray[Any, Any]:
   |                                                                                           ^^^
29 |     """Generate synthetic EEG with a dominant alpha-band (10 Hz) component.
   |

F821 Undefined name `Any`
  --> demos/emg_prosthetic/run_demo.py:30:17
   |
28 |     contraction_start: float = 0.3,
29 |     contraction_end: float = 0.7,
30 | ) -> np.ndarray[Any, Any]:
   |                 ^^^
31 |     """Generate a synthetic EMG signal simulating a muscle contraction.
   |

F821 Undefined name `Any`
  --> demos/emg_prosthetic/run_demo.py:30:22
   |
28 |     contraction_start: float = 0.3,
29 |     contraction_end: float = 0.7,
30 | ) -> np.ndarray[Any, Any]:
   |                      ^^^
31 |     """Generate a synthetic EMG signal simulating a muscle contraction.
   |

F841 Local variable `t` is assigned to but never used
  --> demos/tactile_explorer/run_demo.py:56:5
   |
54 |     duration = 1.0  # 1 second
55 |     n_steps = int(duration / dt)
56 |     t = np.linspace(0, duration, n_steps)
   |     ^
57 |
58 |     rng = np.random.default_rng(42)
   |
help: Remove assignment to unused variable `t`

F841 Local variable `sensory_voltage_probe` is assigned to but never used
  --> examples/04_full_pipeline.py:90:9
   |
88 |     with net:
89 |         sensory_spikes_probe = nengo.Probe(net.sensory_ensemble.neurons, "output")
90 |         sensory_voltage_probe = nengo.Probe(net.sensory_ensemble.neurons, "voltage")
   |         ^^^^^^^^^^^^^^^^^^^^^
91 |         motor_spikes_probe = nengo.Probe(net.motor_ensemble.neurons, "output")
92 |         motor_voltage_probe = nengo.Probe(net.motor_ensemble.neurons, "voltage")
   |
help: Remove assignment to unused variable `sensory_voltage_probe`

F841 Local variable `motor_voltage_probe` is assigned to but never used
  --> examples/04_full_pipeline.py:92:9
   |
90 |         sensory_voltage_probe = nengo.Probe(net.sensory_ensemble.neurons, "voltage")
91 |         motor_spikes_probe = nengo.Probe(net.motor_ensemble.neurons, "output")
92 |         motor_voltage_probe = nengo.Probe(net.motor_ensemble.neurons, "voltage")
   |         ^^^^^^^^^^^^^^^^^^^
93 |         motor_out_probe = nengo.Probe(net.motor_ensemble, synapse=0.01)
   |
help: Remove assignment to unused variable `motor_voltage_probe`

Found 8 errors.
No fixes available (4 hidden fixes can be enabled with the `--unsafe-fixes` option).
```

### ruff-format

```
Would reformat: backend/app/routers/deploy.py
Would reformat: backend/app/routers/export.py
Would reformat: backend/tests/test_deploy_endpoints.py
Would reformat: backend/tests/test_hardware_service.py
Would reformat: neurocnl/backends/akida_capabilities.py
Would reformat: neurocnl/backends/capabilities.py
Would reformat: neurocnl/backends/lava_capabilities.py
Would reformat: neurocnl/backends/sinabs_capabilities.py
Would reformat: neurocnl/backends/test_capabilities.py
Would reformat: neurocnl/cnl/cnl_parser.py
Would reformat: neurocnl/cnl/test_cnl_parser.py
Would reformat: neurocnl/contracts/akida_deployment_contract.py
Would reformat: neurocnl/contracts/hardware_export.py
Would reformat: neurocnl/contracts/pynq_deployment_contract.py
Would reformat: neurocnl/contracts/pynq_runtime_artifact_contract.py
Would reformat: neurocnl/contracts/teensy_deployment_contract.py
Would reformat: neurocnl/contracts/test_pynq_deployment_contract.py
Would reformat: neurocnl/contracts/test_pynq_runtime_artifact_contract.py
Would reformat: neurocnl/converter/lava_io.py
Would reformat: neurocnl/converter/rockpool_io.py
Would reformat: neurocnl/converter/sinabs_io.py
Would reformat: neurocnl/converter/spinnaker2_io.py
Would reformat: neurocnl/converter/test_rockpool.py
Would reformat: neurocnl/converter/test_rockpool_io.py
Would reformat: neurocnl/converter/test_sinabs_io.py
Would reformat: neurocnl/export/lava_exporter.py
Would reformat: neurocnl/export/pynq_exporter.py
Would reformat: neurocnl/export/rockpool_exporter.py
Would reformat: neurocnl/export/sinabs_exporter.py
Would reformat: neurocnl/export/spinnaker2_exporter.py
Would reformat: neurocnl/export/test_exporters.py
Would reformat: neurocnl/export/test_lava_integration.py
Would reformat: neurocnl/export/test_lava_sim_path.py
Would reformat: neurocnl/export/test_pynq_exporter.py
Would reformat: neurocnl/export/test_spinnaker2_exporter.py
Would reformat: neurocnl/generation/nengo_generator.py
Would reformat: neurocnl/generation/test_akida_generator.py
Would reformat: neurocnl/generation/test_assertion_generator.py
Would reformat: neurocnl/generation/test_nengo_generator.py
Would reformat: neurocnl/handoff/neurochip_pynq_handoff.py
Would reformat: neurocnl/handoff/neurochip_teensy_mapper.py
Would reformat: neurocnl/handoff/test_dreamhand_verification_hook.py
Would reformat: neurocnl/handoff/test_neurochip_pynq_handoff.py
Would reformat: neurocnl/ir/lowering.py
Would reformat: neurocnl/ir/test_ir_lowering.py
Would reformat: neurocnl/ir/types.py
Would reformat: neurocnl/layers/akida_validator.py
Would reformat: neurocnl/layers/layer1_validator.py
Would reformat: neurocnl/layers/layer2_validator.py
Would reformat: neurocnl/layers/spinnaker2_validator.py
Would reformat: neurocnl/layers/teensy_validator.py
Would reformat: neurocnl/layers/test_akida_validator.py
Would reformat: neurocnl/layers/test_layer1_validator.py
Would reformat: neurocnl/layers/test_teensy_validator.py
Would reformat: neurocnl/mapping/akida_mapper.py
Would reformat: neurocnl/pipeline.py
Would reformat: neurocnl/planner.py
Would reformat: neurocnl/spike_encoding.py
Would reformat: neurocnl/test_planner.py
Would reformat: neurocnl/test_visualization.py
Would reformat: neurocnl/tests/properties/test_teensy_deployment_properties.py
Would reformat: neurocnl/tests/test_demo_spec_regression.py
Would reformat: neurocnl/tests/test_logging_config.py
Would reformat: neurocnl/tests/test_pipeline.py
Would reformat: neurocnl/tests/test_run_simulation.py
Would reformat: neurocnl/tests/test_teensy_deployment_contract.py
Would reformat: neurocnl/transforms/test_quantise.py
Would reformat: tests/test_backend_smoke.py
Would reformat: tests/test_install_smoke.py
Would reformat: tests/test_sinabs_io.py
70 files would be reformatted, 165 files already formatted
```

### mypy

```
tests/test_install_smoke.py:71: error: Need type annotation for "kwargs" (hint: "kwargs: dict[<type>, <type>] = ...")  [var-annotated]
tests/test_install_smoke.py:137: error: Need type annotation for "kwargs" (hint: "kwargs: dict[<type>, <type>] = ...")  [var-annotated]
tests/test_install_smoke.py:169: error: Need type annotation for "kwargs" (hint: "kwargs: dict[<type>, <type>] = ...")  [var-annotated]
Found 3 errors in 1 file (checked 236 source files)
```

### pytest-core

```
============================= test session starts ==============================
platform darwin -- Python 3.12.13, pytest-9.0.3, pluggy-1.6.0 -- /Users/yoshimartodihardjo/anaconda/anaconda3/bin/python
cachedir: .pytest_cache
benchmark: 5.2.3 (defaults: timer=time.perf_counter disable_gc=False min_rounds=5 min_time=0.000005 max_time=1.0 calibration_precision=10 warmup=False warmup_iterations=100000)
hypothesis profile 'default'
rootdir: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl
configfile: pyproject.toml
plugins: anyio-4.12.1, benchmark-5.2.3, hypothesis-6.151.10, nengo-4.1.0, cov-7.1.0, asyncio-1.3.0
asyncio: mode=Mode.STRICT, debug=False, asyncio_default_fixture_loop_scope=None, asyncio_default_test_loop_scope=function
collecting ... collected 864 items / 3 errors / 2 skipped

==================================== ERRORS ====================================
_____________ ERROR collecting neurocnl/converter/test_rockpool.py _____________
ImportError while importing test module '/Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/neurocnl/converter/test_rockpool.py'.
Hint: make sure your test modules/packages have valid Python names.
Traceback:
../../anaconda/anaconda3/lib/python3.12/importlib/__init__.py:90: in import_module
    return _bootstrap._gcd_import(name[level:], package, level)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
neurocnl/converter/test_rockpool.py:8: in <module>
    import torch
E   ModuleNotFoundError: No module named 'torch'
____________ ERROR collecting neurocnl/converter/test_sinabs_io.py _____________
ImportError while importing test module '/Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/neurocnl/converter/test_sinabs_io.py'.
Hint: make sure your test modules/packages have valid Python names.
Traceback:
../../anaconda/anaconda3/lib/python3.12/importlib/__init__.py:90: in import_module
    return _bootstrap._gcd_import(name[level:], package, level)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
neurocnl/converter/test_sinabs_io.py:2: in <module>
    import torch
E   ModuleNotFoundError: No module named 'torch'
___________ ERROR collecting neurocnl/export/test_sinabs_exporter.py ___________
ImportError while importing test module '/Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/neurocnl/export/test_sinabs_exporter.py'.
Hint: make sure your test modules/packages have valid Python names.
Traceback:
../../anaconda/anaconda3/lib/python3.12/importlib/__init__.py:90: in import_module
    return _bootstrap._gcd_import(name[level:], package, level)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
neurocnl/export/test_sinabs_exporter.py:4: in <module>
    from neurocnl.export.sinabs_exporter import export_sinabs
neurocnl/export/sinabs_exporter.py:10: in <module>
    from neurocnl.converter.sinabs_io import SinabsIO
neurocnl/converter/sinabs_io.py:11: in <module>
    import torch
E   ModuleNotFoundError: No module named 'torch'
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

-- Docs: https://docs.pytest.org/en/stable/how-to/capture-warnings.html
============================ Hypothesis Statistics =============================
=========================== short test summary info ============================
ERROR neurocnl/converter/test_rockpool.py
ERROR neurocnl/converter/test_sinabs_io.py
ERROR neurocnl/export/test_sinabs_exporter.py
!!!!!!!!!!!!!!!!!!! Interrupted: 3 errors during collection !!!!!!!!!!!!!!!!!!!!
=================== 2 skipped, 2 warnings, 3 errors in 1.01s ===================
```

### pytest-backend

```
ERROR: file or directory not found: backend/tests

============================= test session starts ==============================
platform darwin -- Python 3.12.13, pytest-9.0.3, pluggy-1.6.0
benchmark: 5.2.3 (defaults: timer=time.perf_counter disable_gc=False min_rounds=5 min_time=0.000005 max_time=1.0 calibration_precision=10 warmup=False warmup_iterations=100000)
rootdir: /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl
configfile: pyproject.toml
plugins: anyio-4.12.1, benchmark-5.2.3, hypothesis-6.151.10, nengo-4.1.0, cov-7.1.0, asyncio-1.3.0
asyncio: mode=Mode.STRICT, debug=False, asyncio_default_fixture_loop_scope=None, asyncio_default_test_loop_scope=function
collected 0 items

=============================== warnings summary ===============================
../../../anaconda/anaconda3/lib/python3.12/site-packages/jupyter_client/connect.py:22
  /Users/yoshimartodihardjo/anaconda/anaconda3/lib/python3.12/site-packages/jupyter_client/connect.py:22: DeprecationWarning: Jupyter is migrating its paths to use standard platformdirs
  given by the platformdirs library.  To remove this warning and
  see the appropriate new directories, set the environment variable
  `JUPYTER_PLATFORM_DIRS=1` and then run `jupyter --paths`.
  The use of platformdirs will be the default in `jupyter_core` v6
    from jupyter_core.paths import jupyter_data_dir, jupyter_runtime_dir, secure_write

../../../anaconda/anaconda3/lib/python3.12/site-packages/nbconvert/filters/strings.py:23
  /Users/yoshimartodihardjo/anaconda/anaconda3/lib/python3.12/site-packages/nbconvert/filters/strings.py:23: DeprecationWarning: Support for bleach <5 will be removed in a future version of nbconvert
    from nbconvert.preprocessors.sanitize import _get_default_css_sanitizer

-- Docs: https://docs.pytest.org/en/stable/how-to/capture-warnings.html
============================= 2 warnings in 0.18s ==============================
```

