# CI Failure Report: Neurohub

**Date:** 2026-04-10 19:48:23

## Failed Stages

### ruff-format

```
Would reformat: neurohub/app/routers/notes.py
Would reformat: neurohub/app/services/bundle_service.py
Would reformat: neurohub/tests/conftest.py
Would reformat: neurohub/tests/test_smoke.py
4 files would be reformatted, 85 files already formatted
```

### pytest

```
============================= test session starts ==============================
platform darwin -- Python 3.12.13, pytest-9.0.3, pluggy-1.6.0
benchmark: 5.2.3 (defaults: timer=time.perf_counter disable_gc=False min_rounds=5 min_time=0.000005 max_time=1.0 calibration_precision=10 warmup=False warmup_iterations=100000)
rootdir: /Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurohub
configfile: pyproject.toml
plugins: anyio-4.12.1, benchmark-5.2.3, hypothesis-6.151.10, nengo-4.1.0, cov-7.1.0, asyncio-1.3.0
asyncio: mode=Mode.STRICT, debug=False, asyncio_default_fixture_loop_scope=None, asyncio_default_test_loop_scope=function
collected 179 items

neurohub/tests/properties/test_bundle_properties.py ...                  [  1%]
neurohub/tests/properties/test_orchestration_properties.py ....          [  3%]
neurohub/tests/properties/test_project_properties.py ..                  [  5%]
neurohub/tests/properties/test_workflow_properties.py ......             [  8%]
neurohub/tests/test_activity_collector.py ...                            [ 10%]
neurohub/tests/test_alembic_migrations.py .                              [ 10%]
neurohub/tests/test_all_endpoints.py ........FFFFFFFF.........           [ 24%]
neurohub/tests/test_asset_library.py .......                             [ 28%]
neurohub/tests/test_assets_router.py ......                              [ 31%]
neurohub/tests/test_auth.py ..........F..............FF                  [ 46%]
neurohub/tests/test_auth_service.py .......                              [ 50%]
neurohub/tests/test_concurrency.py ..                                    [ 51%]
neurohub/tests/test_config_service.py ...                                [ 53%]
neurohub/tests/test_contract_invariants.py ....                          [ 55%]
neurohub/tests/test_contracts.py ........................F....           [ 72%]
neurohub/tests/test_cors.py ..                                           [ 73%]
neurohub/tests/test_export_import.py ...                                 [ 74%]
neurohub/tests/test_handoff_integration.py ...                           [ 76%]
neurohub/tests/test_health_checker.py .                                  [ 77%]
neurohub/tests/test_milestone_tracker.py ...                             [ 78%]
neurohub/tests/test_prod_integration.py ..                               [ 79%]
neurohub/tests/test_projects.py .....FF                                  [ 83%]
neurohub/tests/test_rate_limiting.py ...F.                               [ 86%]
neurohub/tests/test_smoke.py F                                           [ 87%]
neurohub/tests/test_suite_client.py .......                              [ 91%]
neurohub/tests/test_workflow_engine.py .....                             [ 93%]
neurohub/tests/test_workflow_engine_v2.py .......                        [ 97%]
neurohub/tests/test_workflow_router.py ....                              [100%]

=================================== FAILURES ===================================
_______________________________ test_create_note _______________________________
neurohub/tests/test_all_endpoints.py:152: in test_create_note
    assert data["author"] == "alice"
E   AssertionError: assert 'testuser' == 'alice'
E     
E     - alice
E     + testuser
---------------------------- Captured stderr setup -----------------------------
INFO  [alembic.runtime.migration] Context impl SQLiteImpl.
INFO  [alembic.runtime.migration] Will assume non-transactional DDL.
________________________________ test_get_notes ________________________________
neurohub/tests/test_all_endpoints.py:160: in test_get_notes
    test_create_note(client)
neurohub/tests/test_all_endpoints.py:152: in test_create_note
    assert data["author"] == "alice"
E   AssertionError: assert 'testuser' == 'alice'
E     
E     - alice
E     + testuser
---------------------------- Captured stderr setup -----------------------------
INFO  [alembic.runtime.migration] Context impl SQLiteImpl.
INFO  [alembic.runtime.migration] Will assume non-transactional DDL.
______________________________ test_create_asset _______________________________
neurohub/tests/test_all_endpoints.py:188: in test_create_asset
    assert response.status_code in (200, 201)
E   assert 422 in (200, 201)
E    +  where 422 = <Response [422 Unprocessable Entity]>.status_code
---------------------------- Captured stderr setup -----------------------------
INFO  [alembic.runtime.migration] Context impl SQLiteImpl.
INFO  [alembic.runtime.migration] Will assume non-transactional DDL.
_______________________________ test_list_assets _______________________________
neurohub/tests/test_all_endpoints.py:197: in test_list_assets
    test_create_asset(client)
neurohub/tests/test_all_endpoints.py:188: in test_create_asset
    assert response.status_code in (200, 201)
E   assert 422 in (200, 201)
E    +  where 422 = <Response [422 Unprocessable Entity]>.status_code
---------------------------- Captured stderr setup -----------------------------
INFO  [alembic.runtime.migration] Context impl SQLiteImpl.
INFO  [alembic.runtime.migration] Will assume non-transactional DDL.
________________________________ test_get_asset ________________________________
neurohub/tests/test_all_endpoints.py:206: in test_get_asset
    test_create_asset(client)
neurohub/tests/test_all_endpoints.py:188: in test_create_asset
    assert response.status_code in (200, 201)
E   assert 422 in (200, 201)
E    +  where 422 = <Response [422 Unprocessable Entity]>.status_code
---------------------------- Captured stderr setup -----------------------------
INFO  [alembic.runtime.migration] Context impl SQLiteImpl.
INFO  [alembic.runtime.migration] Will assume non-transactional DDL.
_____________________ test_update_asset_increments_version _____________________
neurohub/tests/test_all_endpoints.py:215: in test_update_asset_increments_version
    test_create_asset(client)
neurohub/tests/test_all_endpoints.py:188: in test_create_asset
    assert response.status_code in (200, 201)
E   assert 422 in (200, 201)
E    +  where 422 = <Response [422 Unprocessable Entity]>.status_code
---------------------------- Captured stderr setup -----------------------------
INFO  [alembic.runtime.migration] Context impl SQLiteImpl.
INFO  [alembic.runtime.migration] Will assume non-transactional DDL.
__________________________ test_filter_assets_by_type __________________________
neurohub/tests/test_all_endpoints.py:241: in test_filter_assets_by_type
    test_create_asset(client)
neurohub/tests/test_all_endpoints.py:188: in test_create_asset
    assert response.status_code in (200, 201)
E   assert 422 in (200, 201)
E    +  where 422 = <Response [422 Unprocessable Entity]>.status_code
---------------------------- Captured stderr setup -----------------------------
INFO  [alembic.runtime.migration] Context impl SQLiteImpl.
INFO  [alembic.runtime.migration] Will assume non-transactional DDL.
______________________________ test_delete_asset _______________________________
neurohub/tests/test_all_endpoints.py:250: in test_delete_asset
    test_create_asset(client)
neurohub/tests/test_all_endpoints.py:188: in test_create_asset
    assert response.status_code in (200, 201)
E   assert 422 in (200, 201)
E    +  where 422 = <Response [422 Unprocessable Entity]>.status_code
---------------------------- Captured stderr setup -----------------------------
INFO  [alembic.runtime.migration] Context impl SQLiteImpl.
INFO  [alembic.runtime.migration] Will assume non-transactional DDL.
_________________________ test_login_non_existent_user _________________________
neurohub/tests/test_auth.py:184: in test_login_non_existent_user
    assert response.status_code == 401
E   assert 200 == 401
E    +  where 200 = <Response [200 OK]>.status_code
---------------------------- Captured stderr setup -----------------------------
INFO  [alembic.runtime.migration] Context impl SQLiteImpl.
INFO  [alembic.runtime.migration] Will assume non-transactional DDL.
________________________ test_login_invalid_credentials ________________________
neurohub/tests/test_auth.py:486: in test_login_invalid_credentials
    assert response.status_code == 401
E   assert 200 == 401
E    +  where 200 = <Response [200 OK]>.status_code
---------------------------- Captured stderr setup -----------------------------
INFO  [alembic.runtime.migration] Context impl SQLiteImpl.
INFO  [alembic.runtime.migration] Will assume non-transactional DDL.
_________________________ test_login_nonexistent_user __________________________
neurohub/tests/test_auth.py:495: in test_login_nonexistent_user
    assert response.status_code == 401
E   assert 200 == 401
E    +  where 200 = <Response [200 OK]>.status_code
---------------------------- Captured stderr setup -----------------------------
INFO  [alembic.runtime.migration] Context impl SQLiteImpl.
INFO  [alembic.runtime.migration] Will assume non-transactional DDL.
___________________ TestSharedAsset.test_valid_shared_asset ____________________
neurohub/tests/test_contracts.py:276: in test_valid_shared_asset
    asset = SharedAsset(
E   pydantic_core._pydantic_core.ValidationError: 1 validation error for SharedAsset
E   sha256
E     Field required [type=missing, input_value={'id': 'a1', 'name': 'Ass...': 1024, 'metadata': {}}, input_type=dict]
E       For further information visit https://errors.pydantic.dev/2.8/v/missing
__________________________ test_project_access_denied __________________________
neurohub/tests/test_projects.py:120: in test_project_access_denied
    assert response.status_code == 403
E   assert 200 == 403
E    +  where 200 = <Response [200 OK]>.status_code
---------------------------- Captured stderr setup -----------------------------
INFO  [alembic.runtime.migration] Context impl SQLiteImpl.
INFO  [alembic.runtime.migration] Will assume non-transactional DDL.
____________________ test_project_member_insufficient_role _____________________
neurohub/tests/test_projects.py:176: in test_project_member_insufficient_role
    assert response.status_code == 403
E   assert 200 == 403
E    +  where 200 = <Response [200 OK]>.status_code
---------------------------- Captured stderr setup -----------------------------
INFO  [alembic.runtime.migration] Context impl SQLiteImpl.
INFO  [alembic.runtime.migration] Will assume non-transactional DDL.
___________________________ test_trigger_rate_limit ____________________________
neurohub/tests/test_rate_limiting.py:70: in test_trigger_rate_limit
    assert response.headers["X-RateLimit-Remaining"] == "0"
E   AssertionError: assert '120' == '0'
E     
E     - 0
E     + 120
---------------------------- Captured stderr setup -----------------------------
INFO  [alembic.runtime.migration] Context impl SQLiteImpl.
INFO  [alembic.runtime.migration] Will assume non-transactional DDL.
________________________ test_orchestration_smoke_path _________________________
../../anaconda/anaconda3/lib/python3.12/site-packages/httpcore/_exceptions.py:10: in map_exceptions
    yield
../../anaconda/anaconda3/lib/python3.12/site-packages/httpcore/_backends/sync.py:206: in connect_tcp
    sock = socket.create_connection(
../../anaconda/anaconda3/lib/python3.12/socket.py:865: in create_connection
    raise exceptions[0]
../../anaconda/anaconda3/lib/python3.12/socket.py:850: in create_connection
    sock.connect(sa)
E   ConnectionRefusedError: [Errno 61] Connection refused

The above exception was the direct cause of the following exception:
../../anaconda/anaconda3/lib/python3.12/site-packages/httpx/_transports/default.py:69: in map_httpcore_exceptions
    yield
../../anaconda/anaconda3/lib/python3.12/site-packages/httpx/_transports/default.py:233: in handle_request
    resp = self._pool.handle_request(req)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
../../anaconda/anaconda3/lib/python3.12/site-packages/httpcore/_sync/connection_pool.py:268: in handle_request
    raise exc
../../anaconda/anaconda3/lib/python3.12/site-packages/httpcore/_sync/connection_pool.py:251: in handle_request
    response = connection.handle_request(request)
               ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
../../anaconda/anaconda3/lib/python3.12/site-packages/httpcore/_sync/connection.py:99: in handle_request
    raise exc
../../anaconda/anaconda3/lib/python3.12/site-packages/httpcore/_sync/connection.py:76: in handle_request
    stream = self._connect(request)
             ^^^^^^^^^^^^^^^^^^^^^^
../../anaconda/anaconda3/lib/python3.12/site-packages/httpcore/_sync/connection.py:124: in _connect
    stream = self._network_backend.connect_tcp(**kwargs)
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
../../anaconda/anaconda3/lib/python3.12/site-packages/httpcore/_backends/sync.py:205: in connect_tcp
    with map_exceptions(exc_map):
../../anaconda/anaconda3/lib/python3.12/contextlib.py:158: in __exit__
    self.gen.throw(value)
../../anaconda/anaconda3/lib/python3.12/site-packages/httpcore/_exceptions.py:14: in map_exceptions
    raise to_exc(exc) from exc
E   httpcore.ConnectError: [Errno 61] Connection refused

The above exception was the direct cause of the following exception:
neurohub/tests/test_smoke.py:34: in test_orchestration_smoke_path
    create_res = client.post(
../../anaconda/anaconda3/lib/python3.12/site-packages/httpx/_client.py:1145: in post
    return self.request(
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
../../anaconda/anaconda3/lib/python3.12/site-packages/httpx/_transports/default.py:232: in handle_request
    with map_httpcore_exceptions():
../../anaconda/anaconda3/lib/python3.12/contextlib.py:158: in __exit__
    self.gen.throw(value)
../../anaconda/anaconda3/lib/python3.12/site-packages/httpx/_transports/default.py:86: in map_httpcore_exceptions
    raise mapped_exc(message) from exc
E   httpx.ConnectError: [Errno 61] Connection refused
----------------------------- Captured stdout call -----------------------------

Starting smoke test against http://localhost:8000...
Creating project smoke-proj-691b65f4...
=============================== warnings summary ===============================
../../anaconda/anaconda3/lib/python3.12/site-packages/passlib/utils/__init__.py:854
  /Users/yoshimartodihardjo/anaconda/anaconda3/lib/python3.12/site-packages/passlib/utils/__init__.py:854: DeprecationWarning: 'crypt' is deprecated and slated for removal in Python 3.13
    from crypt import crypt as _crypt

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

neurohub/tests/test_prod_integration.py::test_full_pipeline_e2e
  /Users/yoshimartodihardjo/anaconda/anaconda3/lib/python3.12/site-packages/websockets/legacy/__init__.py:6: DeprecationWarning: websockets.legacy is deprecated; see https://websockets.readthedocs.io/en/stable/howto/upgrade.html for upgrade instructions
    warnings.warn(  # deprecated in 14.0 - 2024-11-09

neurohub/tests/test_prod_integration.py::test_full_pipeline_e2e
  /Users/yoshimartodihardjo/anaconda/anaconda3/lib/python3.12/site-packages/uvicorn/protocols/websockets/websockets_impl.py:17: DeprecationWarning: websockets.server.WebSocketServerProtocol is deprecated
    from websockets.server import WebSocketServerProtocol

-- Docs: https://docs.pytest.org/en/stable/how-to/capture-warnings.html
============================ Hypothesis Statistics =============================
neurohub/tests/properties/test_bundle_properties.py::test_bundle_round_trip:

  - during generate phase (0.29 seconds):
    - Typical runtimes: ~ 0-1 ms, of which ~ 0-1 ms in data generation
    - 200 passing examples, 0 failing examples, 22 invalid examples
    - Events:
      * 3.15%, Retried draw from text(characters(codec='utf-8'), min_size=1, max_size=100).filter(lambda x: not x.startswith('/') and '..' not in x and (x.strip() != '')) to satisfy filter

  - Stopped because settings.max_examples=200


neurohub/tests/properties/test_bundle_properties.py::test_bundle_checksum_consistency:

  - during generate phase (0.22 seconds):
    - Typical runtimes: ~ 0-1 ms, of which < 1ms in data generation
    - 200 passing examples, 0 failing examples, 38 invalid examples
    - Events:
      * 6.72%, Retried draw from text(characters(codec='utf-8'), min_size=1, max_size=50).filter(lambda x: not x.startswith('/') and '..' not in x and (x.strip() != '')) to satisfy filter

  - Stopped because settings.max_examples=200


neurohub/tests/properties/test_bundle_properties.py::test_bundle_invalid_checksum_rejected:

  - during generate phase (0.24 seconds):
    - Typical runtimes: ~ 0-1 ms, of which ~ 0-1 ms in data generation
    - 200 passing examples, 0 failing examples, 24 invalid examples
    - Events:
      * 5.36%, Retried draw from text(characters(codec='utf-8'), min_size=1, max_size=50).filter(lambda x: not x.startswith('/') and '..' not in x and (x.strip() != '')) to satisfy filter

  - Stopped because settings.max_examples=200


neurohub/tests/properties/test_orchestration_properties.py::test_valid_port_assignments:

  - during generate phase (0.01 seconds):
    - Typical runtimes: < 1ms, of which < 1ms in data generation
    - 36 passing examples, 0 failing examples, 0 invalid examples

  - Stopped because nothing left to do


neurohub/tests/properties/test_orchestration_properties.py::test_invalid_service_names_rejected:

  - during generate phase (0.08 seconds):
    - Typical runtimes: < 1ms, of which < 1ms in data generation
    - 200 passing examples, 0 failing examples, 0 invalid examples

  - Stopped because settings.max_examples=200


neurohub/tests/properties/test_orchestration_properties.py::test_out_of_range_ports_rejected:

  - during generate phase (0.13 seconds):
    - Typical runtimes: < 1ms, of which < 1ms in data generation
    - 200 passing examples, 0 failing examples, 0 invalid examples

  - Stopped because settings.max_examples=200


neurohub/tests/properties/test_orchestration_properties.py::test_suite_orchestration_collisions:

  - during generate phase (0.13 seconds):
    - Typical runtimes: < 1ms, of which < 1ms in data generation
    - 200 passing examples, 0 failing examples, 17 invalid examples

  - Stopped because settings.max_examples=200


neurohub/tests/properties/test_project_properties.py::test_valid_project_references:

  - during generate phase (0.13 seconds):
    - Typical runtimes: < 1ms, of which < 1ms in data generation
    - 200 passing examples, 0 failing examples, 25 invalid examples

  - Stopped because settings.max_examples=200


neurohub/tests/properties/test_project_properties.py::test_invalid_project_references_rejected:

  - during generate phase (0.16 seconds):
    - Typical runtimes: < 1ms, of which < 1ms in data generation
    - 200 passing examples, 0 failing examples, 21 invalid examples
    - Events:
      * 3.17%, Retried draw from text(characters(codec='utf-8'), min_size=1, max_size=10).filter(lambda m: m not in VALID_MODULES) to satisfy filter
      * 0.45%, Retried draw from text(characters(codec='utf-8'), min_size=1, max_size=50).filter(lambda s: s.strip() != '') to satisfy filter

  - Stopped because settings.max_examples=200


neurohub/tests/properties/test_workflow_properties.py::test_generated_workflows_are_valid_dags:

  - during generate phase (0.40 seconds):
    - Typical runtimes: ~ 0-1 ms, of which ~ 0-1 ms in data generation
    - 200 passing examples, 0 failing examples, 41 invalid examples

  - Stopped because settings.max_examples=200


neurohub/tests/properties/test_workflow_properties.py::test_workflow_definition_round_trip:

  - during generate phase (0.40 seconds):
    - Typical runtimes: ~ 0-1 ms, of which ~ 0-1 ms in data generation
    - 200 passing examples, 0 failing examples, 30 invalid examples

  - Stopped because settings.max_examples=200


neurohub/tests/properties/test_workflow_properties.py::test_workflow_template_round_trip:

  - during generate phase (1.18 seconds):
    - Typical runtimes: ~ 0-8 ms, of which ~ 0-6 ms in data generation
    - 200 passing examples, 0 failing examples, 1 invalid examples
    - Events:
      * 13.93%, Retried draw from text(characters(codec='utf-8'), min_size=1).filter(not_yet_in_unique_list) to satisfy filter

  - Stopped because settings.max_examples=200


neurohub/tests/properties/test_workflow_properties.py::test_workflow_cycle_detection:

  - during generate phase (0.39 seconds):
    - Typical runtimes: ~ 0-2 ms, of which ~ 0-2 ms in data generation
    - 200 passing examples, 0 failing examples, 44 invalid examples
    - Events:
      * 24.18%, Retried draw from text(characters(codec='utf-8'), min_size=1, max_size=10).filter(not_yet_in_unique_list) to satisfy filter
      * 23.36%, Retried draw from fixed_dictionaries({'id': text(min_size=1, max_size=10), 'depends_on': lists(text(min_size=1, max_size=10), unique=True)}).filter(not_yet_in_unique_list) to satisfy filter

  - Stopped because settings.max_examples=200


neurohub/tests/properties/test_workflow_properties.py::test_workflow_definition_rejects_invalid_execution_order:

  - during generate phase (0.42 seconds):
    - Typical runtimes: ~ 0-1 ms, of which ~ 0-1 ms in data generation
    - 200 passing examples, 0 failing examples, 35 invalid examples

  - Stopped because settings.max_examples=200


neurohub/tests/properties/test_workflow_properties.py::test_workflow_template_dag_integrity:

  - during generate phase (0.51 seconds):
    - Typical runtimes: ~ 0-3 ms, of which ~ 0-3 ms in data generation
    - 200 passing examples, 0 failing examples, 39 invalid examples
    - Events:
      * 14.64%, Retried draw from text(characters(codec='utf-8')).filter(not_yet_in_unique_list) to satisfy filter
      * 12.13%, Retried draw from fixed_dictionaries({'id': text(min_size=1, max_size=10), 'name': text(min_size=1, max_size=20), 'app': sampled_from(['neurosim', 'neurochip']), 'endpoint': text(min_size=1, max_size=20), 'method': sampled_from(['GET', 'POST']), 'parameters': dictionaries(keys=text(), values=text()), 'success_criteria': text(min_size=1, max_size=20), 'on_failure': sampled_from(['halt', 'warn', 'skip']), 'depends_on': lists(text(min_size=1, max_size=10), unique=True)}).filter(not_yet_in_unique_list) to satisfy filter
      * 5.44%, Retried draw from text(characters(codec='utf-8'), min_size=1, max_size=10).filter(not_yet_in_unique_list) to satisfy filter

  - Stopped because settings.max_examples=200


=========================== short test summary info ============================
FAILED neurohub/tests/test_all_endpoints.py::test_create_note - AssertionErro...
FAILED neurohub/tests/test_all_endpoints.py::test_get_notes - AssertionError:...
FAILED neurohub/tests/test_all_endpoints.py::test_create_asset - assert 422 i...
FAILED neurohub/tests/test_all_endpoints.py::test_list_assets - assert 422 in...
FAILED neurohub/tests/test_all_endpoints.py::test_get_asset - assert 422 in (...
FAILED neurohub/tests/test_all_endpoints.py::test_update_asset_increments_version
FAILED neurohub/tests/test_all_endpoints.py::test_filter_assets_by_type - ass...
FAILED neurohub/tests/test_all_endpoints.py::test_delete_asset - assert 422 i...
FAILED neurohub/tests/test_auth.py::test_login_non_existent_user - assert 200...
FAILED neurohub/tests/test_auth.py::test_login_invalid_credentials - assert 2...
FAILED neurohub/tests/test_auth.py::test_login_nonexistent_user - assert 200 ...
FAILED neurohub/tests/test_contracts.py::TestSharedAsset::test_valid_shared_asset
FAILED neurohub/tests/test_projects.py::test_project_access_denied - assert 2...
FAILED neurohub/tests/test_projects.py::test_project_member_insufficient_role
FAILED neurohub/tests/test_rate_limiting.py::test_trigger_rate_limit - Assert...
FAILED neurohub/tests/test_smoke.py::test_orchestration_smoke_path - httpx.Co...
================= 16 failed, 163 passed, 5 warnings in 16.27s ==================
```

