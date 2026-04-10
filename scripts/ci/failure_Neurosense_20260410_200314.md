# CI Failure Report: Neurosense

**Date:** 2026-04-10 20:03:14

## Failed Stages

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
neurosense/tests/properties/test_new_invariants.py F....                 [ 12%]
neurosense/tests/test_auth.py ........                                   [ 19%]
neurosense/tests/test_contracts.py ............                          [ 30%]
neurosense/tests/test_device_manager.py .....                            [ 35%]
neurosense/tests/test_e2e_pipeline.py ...                                [ 38%]
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
___________________________ test_filter_output_valid ___________________________
neurosense/tests/properties/test_new_invariants.py:56: in test_filter_output_valid
    @given(output_data=filter_output_strategy())
                   ^^^
E   hypothesis.errors.FailedHealthCheck: Generated inputs routinely consumed more than the maximum allowed entropy: 9 inputs were generated successfully, while 20 inputs exceeded the maximum allowed entropy during generation.
E   
E   Testing with inputs this large tends to be slow, and to produce failures that are both difficult to shrink and difficult to understand. Try decreasing the amount of data generated, for example by decreasing the minimum size of collection strategies like st.lists().
E   
E   If you expect the average size of your input to be this large, you can disable this health check with @settings(suppress_health_check=[HealthCheck.data_too_large]). See https://hypothesis.readthedocs.io/en/latest/reference/api.html#hypothesis.HealthCheck for details.
---------------------------------- Hypothesis ----------------------------------
You can reproduce this failure by adding @seed(32886766760298416015584474636242090043) to this test, or by running pytest with --hypothesis-seed=32886766760298416015584474636242090043.
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

  - during generate phase (0.60 seconds):
    - Typical runtimes: ~ 1-3 ms, of which ~ 1-2 ms in data generation
    - 200 passing examples, 0 failing examples, 33 invalid examples

  - Stopped because settings.max_examples=200


neurosense/tests/properties/test_device_properties.py::test_buffer_memory_invariant:

  - during generate phase (0.57 seconds):
    - Typical runtimes: ~ 1-2 ms, of which ~ 1-2 ms in data generation
    - 200 passing examples, 0 failing examples, 31 invalid examples

  - Stopped because settings.max_examples=200


neurosense/tests/properties/test_device_properties.py::test_recording_parameters_consistency:

  - during generate phase (0.53 seconds):
    - Typical runtimes: ~ 1-2 ms, of which ~ 1-2 ms in data generation
    - 200 passing examples, 0 failing examples, 35 invalid examples

  - Stopped because settings.max_examples=200


neurosense/tests/properties/test_device_properties.py::test_recording_integrity[asyncio]:

  - during generate phase (0.14 seconds):
    - Typical runtimes: ~ 2-3 ms, of which < 1ms in data generation
    - 50 passing examples, 0 failing examples, 0 invalid examples

  - Stopped because settings.max_examples=50


neurosense/tests/properties/test_device_properties.py::test_device_config_invalid_values:

  - during generate phase (0.07 seconds):
    - Typical runtimes: < 1ms, of which < 1ms in data generation
    - 100 passing examples, 0 failing examples, 0 invalid examples

  - Stopped because settings.max_examples=100


neurosense/tests/properties/test_encoding_properties.py::test_spike_ordering_preservation:

  - during generate phase (3.63 seconds):
    - Typical runtimes: ~ 1-23 ms, of which ~ 1-23 ms in data generation
    - 200 passing examples, 0 failing examples, 53 invalid examples

  - Stopped because settings.max_examples=200


neurosense/tests/properties/test_encoding_properties.py::test_refractory_period_violation:

  - during generate phase (2.95 seconds):
    - Typical runtimes: ~ 1-24 ms, of which ~ 1-24 ms in data generation
    - 200 passing examples, 0 failing examples, 40 invalid examples

  - Stopped because settings.max_examples=200


neurosense/tests/properties/test_encoding_properties.py::test_encoding_determinism:

  - during generate phase (3.59 seconds):
    - Typical runtimes: ~ 1-23 ms, of which ~ 1-23 ms in data generation
    - 200 passing examples, 0 failing examples, 64 invalid examples

  - Stopped because settings.max_examples=200


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
FAILED neurosense/tests/properties/test_new_invariants.py::test_filter_output_valid
================== 1 failed, 106 passed, 2 warnings in 14.47s ==================
```

