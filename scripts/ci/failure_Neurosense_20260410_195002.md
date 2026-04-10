# CI Failure Report: Neurosense

**Date:** 2026-04-10 19:50:02

## Failed Stages

### ruff-format

```
Would reformat: neurosense/app/routers/encoding.py
Would reformat: neurosense/app/routers/prophesee.py
Would reformat: neurosense/app/schemas/encoding.py
Would reformat: neurosense/app/services/device_manager.py
Would reformat: neurosense/app/services/event_encoder.py
Would reformat: neurosense/app/services/recording_service.py
Would reformat: neurosense/app/services/replay_service.py
Would reformat: neurosense/app/sources/prophesee_source.py
Would reformat: neurosense/contracts/device_contracts.py
Would reformat: neurosense/pynq_service/main.py
Would reformat: neurosense/tests/conftest.py
Would reformat: neurosense/tests/properties/test_device_properties.py
Would reformat: neurosense/tests/properties/test_encoding_properties.py
Would reformat: neurosense/tests/properties/test_new_invariants.py
Would reformat: neurosense/tests/test_auth.py
Would reformat: neurosense/tests/test_filter_pipeline.py
Would reformat: neurosense/tests/test_main.py
Would reformat: neurosense/tests/test_replay_service.py
Would reformat: neurosense/tests/test_smoke.py
19 files would be reformatted, 65 files already formatted
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
neurosense/tests/test_e2e_pipeline.py F..                                [ 38%]
neurosense/tests/test_export.py ....                                     [ 42%]
neurosense/tests/test_filter_pipeline.py .........                       [ 50%]
neurosense/tests/test_hardware_integration.py ....                       [ 54%]
neurosense/tests/test_main.py ..F...                                     [ 59%]
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
______________________ test_concurrent_pipelines[asyncio] ______________________
neurosense/tests/test_e2e_pipeline.py:24: in test_concurrent_pipelines
    cyton = await device_manager.connect("cyton", allow_experimental=True)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
neurosense/app/services/device_manager.py:284: in connect
    raise ValueError(
E   ValueError: OpenBCI Cyton target is not configured. Set NEUROSENSE_CYTON_SERIAL_PORT or provide serial_port when connecting.
______________ test_connect_device_route_accepts_serial_port_body ______________
neurosense/tests/test_main.py:50: in test_connect_device_route_accepts_serial_port_body
    response = client.post(
../../anaconda/anaconda3/lib/python3.12/site-packages/starlette/testclient.py:546: in post
    return super().post(
../../anaconda/anaconda3/lib/python3.12/site-packages/httpx/_client.py:1145: in post
    return self.request(
../../anaconda/anaconda3/lib/python3.12/site-packages/starlette/testclient.py:445: in request
    return super().request(
../../anaconda/anaconda3/lib/python3.12/site-packages/httpx/_client.py:827: in request
    return self.send(request, auth=auth, follow_redirects=follow_redirects)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
../../anaconda/anaconda3/lib/python3.12/site-packages/httpx/_client.py:914: in send
    response = self._send_handling_auth(
../../anaconda/anaconda3/lib/python3.12/site-packages/httpx/_client.py:942: in _send_handling_auth
    response = self._send_handling_redirects(
../../anaconda/anaconda3/lib/python3.12/site-packages/httpx/_client.py:979: in _send_handling_redirects
    response = self._send_single_request(request)
               ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
../../anaconda/anaconda3/lib/python3.12/site-packages/httpx/_client.py:1015: in _send_single_request
    response = transport.handle_request(request)
               ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
../../anaconda/anaconda3/lib/python3.12/site-packages/starlette/testclient.py:348: in handle_request
    raise exc
../../anaconda/anaconda3/lib/python3.12/site-packages/starlette/testclient.py:345: in handle_request
    portal.call(self.app, scope, receive, send)
../../anaconda/anaconda3/lib/python3.12/site-packages/anyio/from_thread.py:334: in call
    return cast(T_Retval, self.start_task_soon(func, *args).result())
                          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
../../anaconda/anaconda3/lib/python3.12/concurrent/futures/_base.py:449: in result
    return self.__get_result()
           ^^^^^^^^^^^^^^^^^^^
../../anaconda/anaconda3/lib/python3.12/concurrent/futures/_base.py:401: in __get_result
    raise self._exception
../../anaconda/anaconda3/lib/python3.12/site-packages/anyio/from_thread.py:259: in _call_func
    retval = await retval_or_awaitable
             ^^^^^^^^^^^^^^^^^^^^^^^^^
../../anaconda/anaconda3/lib/python3.12/site-packages/fastapi/applications.py:1160: in __call__
    await super().__call__(scope, receive, send)
../../anaconda/anaconda3/lib/python3.12/site-packages/starlette/applications.py:107: in __call__
    await self.middleware_stack(scope, receive, send)
../../anaconda/anaconda3/lib/python3.12/site-packages/starlette/middleware/errors.py:186: in __call__
    raise exc
../../anaconda/anaconda3/lib/python3.12/site-packages/starlette/middleware/errors.py:164: in __call__
    await self.app(scope, receive, _send)
../../anaconda/anaconda3/lib/python3.12/site-packages/starlette/middleware/exceptions.py:63: in __call__
    await wrap_app_handling_exceptions(self.app, conn)(scope, receive, send)
../../anaconda/anaconda3/lib/python3.12/site-packages/starlette/_exception_handler.py:53: in wrapped_app
    raise exc
../../anaconda/anaconda3/lib/python3.12/site-packages/starlette/_exception_handler.py:42: in wrapped_app
    await app(scope, receive, sender)
../../anaconda/anaconda3/lib/python3.12/site-packages/fastapi/middleware/asyncexitstack.py:18: in __call__
    await self.app(scope, receive, send)
../../anaconda/anaconda3/lib/python3.12/site-packages/starlette/routing.py:716: in __call__
    await self.middleware_stack(scope, receive, send)
../../anaconda/anaconda3/lib/python3.12/site-packages/starlette/routing.py:736: in app
    await route.handle(scope, receive, send)
../../anaconda/anaconda3/lib/python3.12/site-packages/starlette/routing.py:290: in handle
    await self.app(scope, receive, send)
../../anaconda/anaconda3/lib/python3.12/site-packages/fastapi/routing.py:130: in app
    await wrap_app_handling_exceptions(app, request)(scope, receive, send)
../../anaconda/anaconda3/lib/python3.12/site-packages/starlette/_exception_handler.py:53: in wrapped_app
    raise exc
../../anaconda/anaconda3/lib/python3.12/site-packages/starlette/_exception_handler.py:42: in wrapped_app
    await app(scope, receive, sender)
../../anaconda/anaconda3/lib/python3.12/site-packages/fastapi/routing.py:116: in app
    response = await f(request)
               ^^^^^^^^^^^^^^^^
../../anaconda/anaconda3/lib/python3.12/site-packages/fastapi/routing.py:670: in app
    raw_response = await run_endpoint_function(
../../anaconda/anaconda3/lib/python3.12/site-packages/fastapi/routing.py:324: in run_endpoint_function
    return await dependant.call(**values)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
../../anaconda/anaconda3/lib/python3.12/site-packages/slowapi/extension.py:734: in async_wrapper
    response = await func(*args, **kwargs)  # type: ignore
               ^^^^^^^^^^^^^^^^^^^^^^^^^^^
neurosense/app/routers/devices.py:52: in connect_device
    if device.support_level in {"experimental", "prototype"}:
       ^^^^^^^^^^^^^^^^^^^^
E   AttributeError: 'types.SimpleNamespace' object has no attribute 'support_level'
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

  - during generate phase (1.64 seconds):
    - Typical runtimes: ~ 1-2 ms, of which ~ 0-2 ms in data generation
    - 200 passing examples, 0 failing examples, 47 invalid examples

  - Stopped because settings.max_examples=200


neurosense/tests/properties/test_device_properties.py::test_buffer_memory_invariant:

  - during generate phase (0.55 seconds):
    - Typical runtimes: ~ 1-2 ms, of which ~ 0-2 ms in data generation
    - 200 passing examples, 0 failing examples, 38 invalid examples

  - Stopped because settings.max_examples=200


neurosense/tests/properties/test_device_properties.py::test_recording_parameters_consistency:

  - during generate phase (0.57 seconds):
    - Typical runtimes: ~ 1-2 ms, of which ~ 1-2 ms in data generation
    - 200 passing examples, 0 failing examples, 38 invalid examples

  - Stopped because settings.max_examples=200


neurosense/tests/properties/test_device_properties.py::test_recording_integrity[asyncio]:

  - during generate phase (0.16 seconds):
    - Typical runtimes: ~ 2-3 ms, of which < 1ms in data generation
    - 50 passing examples, 0 failing examples, 0 invalid examples

  - Stopped because settings.max_examples=50


neurosense/tests/properties/test_device_properties.py::test_device_config_invalid_values:

  - during generate phase (0.07 seconds):
    - Typical runtimes: < 1ms, of which < 1ms in data generation
    - 100 passing examples, 0 failing examples, 0 invalid examples

  - Stopped because settings.max_examples=100


neurosense/tests/properties/test_encoding_properties.py::test_spike_ordering_preservation:

  - during generate phase (4.63 seconds):
    - Typical runtimes: ~ 1-23 ms, of which ~ 1-23 ms in data generation
    - 200 passing examples, 0 failing examples, 71 invalid examples

  - Stopped because settings.max_examples=200


neurosense/tests/properties/test_encoding_properties.py::test_refractory_period_violation:

  - during generate phase (3.61 seconds):
    - Typical runtimes: ~ 1-23 ms, of which ~ 1-23 ms in data generation
    - 200 passing examples, 0 failing examples, 65 invalid examples

  - Stopped because settings.max_examples=200


neurosense/tests/properties/test_encoding_properties.py::test_encoding_determinism:

  - during generate phase (2.95 seconds):
    - Typical runtimes: ~ 1-23 ms, of which ~ 1-22 ms in data generation
    - 200 passing examples, 0 failing examples, 42 invalid examples

  - Stopped because settings.max_examples=200


neurosense/tests/properties/test_new_invariants.py::test_filter_output_valid:

  - during generate phase (1.30 seconds):
    - Typical runtimes: ~ 0-23 ms, of which ~ 0-22 ms in data generation
    - 100 passing examples, 0 failing examples, 23 invalid examples

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
FAILED neurosense/tests/test_e2e_pipeline.py::test_concurrent_pipelines[asyncio]
FAILED neurosense/tests/test_main.py::test_connect_device_route_accepts_serial_port_body
================== 2 failed, 105 passed, 2 warnings in 18.62s ==================
```

