# CI Failure Report: Neurosense

**Date:** 2026-04-10 19:54:29

## Failed Stages

### ruff-check

```
F821 Undefined name `patch`
  --> neurosense/tests/test_e2e_pipeline.py:86:10
   |
84 |     # AC: connect device -> acquire signal -> filter -> display (simulated)
85 |     rng = np.random.default_rng()
86 |     with patch("brainflow.board_shim.BoardShim") as mock_board_shim:
   |          ^^^^^
87 |         mock_board = MagicMock()
88 |         # Mock 8 channels of data
   |

Found 1 error.
```

### pytest

```
============================= test session starts ==============================
platform darwin -- Python 3.12.13, pytest-9.0.3, pluggy-1.6.0
benchmark: 5.2.3 (defaults: timer=time.perf_counter disable_gc=False min_rounds=5 min_time=0.000005 max_time=1.0 calibration_precision=10 warmup=False warmup_iterations=100000)
rootdir: /Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurosense
configfile: pyproject.toml
testpaths: neurosense/tests
plugins: anyio-4.12.1, benchmark-5.2.3, hypothesis-6.151.10, nengo-4.1.0, cov-7.1.0, asyncio-1.3.0
asyncio: mode=Mode.STRICT, debug=False, asyncio_default_fixture_loop_scope=None, asyncio_default_test_loop_scope=function
collected 107 items

neurosense/tests/properties/test_device_properties.py .....              [  4%]
neurosense/tests/properties/test_encoding_properties.py ...              [  7%]
neurosense/tests/properties/test_new_invariants.py .....                 [ 12%]
neurosense/tests/test_auth.py ........                                   [ 19%]
neurosense/tests/test_contracts.py ............                          [ 30%]
neurosense/tests/test_device_manager.py .....                            [ 35%]
neurosense/tests/test_e2e_pipeline.py ..F                                [ 38%]
neurosense/tests/test_export.py ....                                     [ 42%]
neurosense/tests/test_filter_pipeline.py .........                       [ 50%]
neurosense/tests/test_hardware_integration.py ....                       [ 54%]
neurosense/tests/test_main.py ......                                     [ 59%]
neurosense/tests/test_middleware.py ...                                  [ 62%]
neurosense/tests/test_nir_integration.py .....                           [ 67%]
neurosense/tests/test_pipeline_bridge.py ....                            [ 71%]
neurosense/tests/test_quality_analyzer.py .......                        [ 77%]
neurosense/tests/test_rate_limiting.py ...                               [ 80%]
neurosense/tests/test_recording_service.py .....                         [ 85%]
neurosense/tests/test_replay_service.py ....                             [ 88%]
neurosense/tests/test_smoke.py .                                         [ 89%]
neurosense/tests/test_spike_encoder.py ......                            [ 95%]
neurosense/tests/test_stream.py ...                                      [ 98%]
neurosense/tests/test_validate_hardware.py ..                            [100%]

=================================== FAILURES ===================================
_______________________ test_full_pipeline_flow[asyncio] _______________________
neurosense/tests/test_e2e_pipeline.py:86: in test_full_pipeline_flow
    with patch("brainflow.board_shim.BoardShim") as mock_board_shim:
         ^^^^^
E   NameError: name 'patch' is not defined
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
neurosense/tests/properties/test_device_properties.py::test_nyquist_invariant:

  - during generate phase (0.83 seconds):
    - Typical runtimes: ~ 1-6 ms, of which ~ 1-4 ms in data generation
    - 200 passing examples, 0 failing examples, 27 invalid examples

  - Stopped because settings.max_examples=200


neurosense/tests/properties/test_device_properties.py::test_buffer_memory_invariant:

  - during generate phase (0.67 seconds):
    - Typical runtimes: ~ 1-3 ms, of which ~ 1-2 ms in data generation
    - 200 passing examples, 0 failing examples, 33 invalid examples

  - Stopped because settings.max_examples=200


neurosense/tests/properties/test_device_properties.py::test_recording_parameters_consistency:

  - during generate phase (0.58 seconds):
    - Typical runtimes: ~ 1-3 ms, of which ~ 1-2 ms in data generation
    - 200 passing examples, 0 failing examples, 34 invalid examples

  - Stopped because settings.max_examples=200


neurosense/tests/properties/test_device_properties.py::test_recording_integrity[asyncio]:

  - during generate phase (0.19 seconds):
    - Typical runtimes: ~ 2-5 ms, of which < 1ms in data generation
    - 50 passing examples, 0 failing examples, 0 invalid examples

  - Stopped because settings.max_examples=50


neurosense/tests/properties/test_device_properties.py::test_device_config_invalid_values:

  - during generate phase (0.07 seconds):
    - Typical runtimes: < 1ms, of which < 1ms in data generation
    - 100 passing examples, 0 failing examples, 0 invalid examples

  - Stopped because settings.max_examples=100


neurosense/tests/properties/test_encoding_properties.py::test_spike_ordering_preservation:

  - during generate phase (3.39 seconds):
    - Typical runtimes: ~ 1-24 ms, of which ~ 1-23 ms in data generation
    - 200 passing examples, 0 failing examples, 34 invalid examples

  - Stopped because settings.max_examples=200


neurosense/tests/properties/test_encoding_properties.py::test_refractory_period_violation:

  - during generate phase (3.10 seconds):
    - Typical runtimes: ~ 1-23 ms, of which ~ 1-23 ms in data generation
    - 200 passing examples, 0 failing examples, 54 invalid examples

  - Stopped because settings.max_examples=200


neurosense/tests/properties/test_encoding_properties.py::test_encoding_determinism:

  - during generate phase (3.08 seconds):
    - Typical runtimes: ~ 1-24 ms, of which ~ 1-23 ms in data generation
    - 200 passing examples, 0 failing examples, 42 invalid examples

  - Stopped because settings.max_examples=200


neurosense/tests/properties/test_new_invariants.py::test_filter_output_valid:

  - during generate phase (1.63 seconds):
    - Typical runtimes: ~ 0-24 ms, of which ~ 0-24 ms in data generation
    - 100 passing examples, 0 failing examples, 41 invalid examples

  - Stopped because settings.max_examples=100


neurosense/tests/properties/test_new_invariants.py::test_filter_output_invalid_shape:

  - during generate phase (0.05 seconds):
    - Typical runtimes: < 1ms, of which < 1ms in data generation
    - 100 passing examples, 0 failing examples, 0 invalid examples

  - Stopped because settings.max_examples=100


neurosense/tests/properties/test_new_invariants.py::test_filter_output_non_finite:

  - during generate phase (0.02 seconds):
    - Typical runtimes: < 1ms, of which < 1ms in data generation
    - 40 passing examples, 0 failing examples, 0 invalid examples

  - Stopped because nothing left to do


neurosense/tests/properties/test_new_invariants.py::test_filter_output_artifact_threshold:

  - during generate phase (0.02 seconds):
    - Typical runtimes: < 1ms, of which < 1ms in data generation
    - 40 passing examples, 0 failing examples, 0 invalid examples

  - Stopped because nothing left to do


neurosense/tests/properties/test_new_invariants.py::test_connection_transition_invariants:

  - during generate phase (0.01 seconds):
    - Typical runtimes: < 1ms, of which < 1ms in data generation
    - 25 passing examples, 0 failing examples, 0 invalid examples

  - Stopped because nothing left to do


=========================== short test summary info ============================
FAILED neurosense/tests/test_e2e_pipeline.py::test_full_pipeline_flow[asyncio]
================== 1 failed, 106 passed, 2 warnings in 15.79s ==================
```

