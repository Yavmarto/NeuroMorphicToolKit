# CI Failure Report: Neurochip

**Date:** 2026-04-10 07:22:08

## Failed Stages

### mypy

```
neurochip/app/services/teensy_generator.py:85: error: Argument 1 to "int" has incompatible type "Any | object"; expected "str | Buffer | SupportsInt | SupportsIndex | SupportsTrunc"  [arg-type]
neurochip/app/services/teensy_generator.py:91: error: Argument 1 to "int" has incompatible type "Any | object"; expected "str | Buffer | SupportsInt | SupportsIndex | SupportsTrunc"  [arg-type]
Found 2 errors in 1 file (checked 96 source files)
```

### pytest

```
============================= test session starts ==============================
platform darwin -- Python 3.12.13, pytest-9.0.2, pluggy-1.6.0
rootdir: /Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurochip
configfile: pyproject.toml
plugins: hypothesis-6.151.10, cov-7.1.0, anyio-4.13.0
collected 245 items

neurochip/tests/properties/test_contract_properties.py F...........      [  4%]
neurochip/tests/properties/test_deployment_properties.py ........        [  8%]
neurochip/tests/properties/test_pynq_runtime_properties.py .....         [ 10%]
neurochip/tests/properties/test_quantization_properties.py ..            [ 11%]
neurochip/tests/test_artifact_contracts.py ...........                   [ 15%]
neurochip/tests/test_auth.py .....                                       [ 17%]
neurochip/tests/test_cache_manager.py ...                                [ 18%]
neurochip/tests/test_constraint_analyzer.py ......                       [ 21%]
neurochip/tests/test_constraint_e2e.py ...                               [ 22%]
neurochip/tests/test_contracts.py ..................                     [ 29%]
neurochip/tests/test_cors.py .                                           [ 30%]
neurochip/tests/test_deployment_store.py ...                             [ 31%]
neurochip/tests/test_e2e.py ........                                     [ 34%]
neurochip/tests/test_export_router.py ..............                     [ 40%]
neurochip/tests/test_export_ws.py ....                                   [ 42%]
neurochip/tests/test_fault_runner.py .........                           [ 45%]
neurochip/tests/test_flash_service.py .................                  [ 52%]
neurochip/tests/test_generators.py ..                                    [ 53%]
neurochip/tests/test_hardware_pipeline.py s....                          [ 55%]
neurochip/tests/test_lava.py .                                           [ 55%]
neurochip/tests/test_loihi_generator.py ......                           [ 58%]
neurochip/tests/test_main.py ..                                          [ 59%]
neurochip/tests/test_partitioner.py ..                                   [ 60%]
neurochip/tests/test_power_estimator.py ...                              [ 61%]
neurochip/tests/test_pynq_backend.py ...............................     [ 73%]
neurochip/tests/test_pynq_sitl_verify.py ....................            [ 82%]
neurochip/tests/test_quantization_router.py ....                         [ 83%]
neurochip/tests/test_quantizer.py ....                                   [ 85%]
neurochip/tests/test_rate_limiting.py ..                                 [ 86%]
neurochip/tests/test_routers.py .............                            [ 91%]
neurochip/tests/test_targets_router.py ...                               [ 92%]
neurochip/tests/test_teensy_deployment_contract.py .............         [ 97%]
neurochip/tests/test_teensy_generator.py .....                           [100%]

=================================== FAILURES ===================================
___________________ test_deployment_manifest_firmware_semver ___________________
neurochip/tests/properties/test_contract_properties.py:24: in test_deployment_manifest_firmware_semver
    DeploymentManifest(
E   pydantic_core._pydantic_core.ValidationError: 1 validation error for DeploymentManifest
E     Value error, Firmware version 0.0.0 is incompatible with Teensy 4.1. Minimum version required: 1.0.0. [type=value_error, input_value={'target_device': <Target...aaaaaaaaaaaaaaaaaaaaaa'}, input_type=dict]
E       For further information visit https://errors.pydantic.dev/2.12/v/value_error

During handling of the above exception, another exception occurred:
neurochip/tests/properties/test_contract_properties.py:20: in test_deployment_manifest_firmware_semver
    def test_deployment_manifest_firmware_semver(version):
                   ^^^
neurochip/tests/properties/test_contract_properties.py:32: in test_deployment_manifest_firmware_semver
    assert not is_valid
E   assert not True
E   Falsifying example: test_deployment_manifest_firmware_semver(
E       version='0.0.0',
E   )
============================ Hypothesis Statistics =============================
neurochip/tests/properties/test_contract_properties.py::test_deployment_manifest_firmware_semver:

  - during reuse phase (0.03 seconds):
    - Typical runtimes: ~ 32ms, of which < 1ms in data generation
    - 0 passing examples, 1 failing examples, 0 invalid examples
    - Found 1 distinct error in this phase

  - Stopped because nothing left to do


neurochip/tests/properties/test_contract_properties.py::test_deployment_manifest_checksum_sha256:

  - during generate phase (0.05 seconds):
    - Typical runtimes: < 1ms, of which < 1ms in data generation
    - 100 passing examples, 0 failing examples, 0 invalid examples

  - Stopped because settings.max_examples=100


neurochip/tests/properties/test_contract_properties.py::test_quantization_precision_loss_bound:

  - during generate phase (0.03 seconds):
    - Typical runtimes: < 1ms, of which < 1ms in data generation
    - 100 passing examples, 0 failing examples, 0 invalid examples

  - Stopped because settings.max_examples=100


neurochip/tests/properties/test_contract_properties.py::test_quantization_config_bit_width_invariant:

  - during generate phase (0.03 seconds):
    - Typical runtimes: < 1ms, of which < 1ms in data generation
    - 100 passing examples, 0 failing examples, 0 invalid examples

  - Stopped because settings.max_examples=100


neurochip/tests/properties/test_contract_properties.py::test_hardware_memory_fit_invariant:

  - during generate phase (0.04 seconds):
    - Typical runtimes: < 1ms, of which < 1ms in data generation
    - 100 passing examples, 0 failing examples, 0 invalid examples

  - Stopped because settings.max_examples=100


neurochip/tests/properties/test_contract_properties.py::test_hardware_profile_bit_widths_positive:

  - during generate phase (0.05 seconds):
    - Typical runtimes: < 1ms, of which < 1ms in data generation
    - 100 passing examples, 0 failing examples, 19 invalid examples

  - Stopped because settings.max_examples=100


neurochip/tests/properties/test_contract_properties.py::test_fault_sweep_rate_limit:

  - during generate phase (0.06 seconds):
    - Typical runtimes: < 1ms, of which < 1ms in data generation
    - 100 passing examples, 0 failing examples, 17 invalid examples

  - Stopped because settings.max_examples=100


neurochip/tests/properties/test_contract_properties.py::test_latency_estimate_monotonicity:

  - during generate phase (0.04 seconds):
    - Typical runtimes: < 1ms, of which < 1ms in data generation
    - 100 passing examples, 0 failing examples, 0 invalid examples

  - Stopped because settings.max_examples=100


neurochip/tests/properties/test_contract_properties.py::test_power_estimate_non_negative:

  - during generate phase (0.07 seconds):
    - Typical runtimes: < 1ms, of which < 1ms in data generation
    - 100 passing examples, 0 failing examples, 0 invalid examples

  - Stopped because settings.max_examples=100


neurochip/tests/properties/test_contract_properties.py::test_core_count_valid_range:

  - during generate phase (0.02 seconds):
    - Typical runtimes: < 1ms, of which < 1ms in data generation
    - 100 passing examples, 0 failing examples, 0 invalid examples

  - Stopped because settings.max_examples=100


neurochip/tests/properties/test_deployment_properties.py::test_analyzer_memory_invariant:

  - during generate phase (0.20 seconds):
    - Typical runtimes: ~ 0-2 ms, of which ~ 0-2 ms in data generation
    - 100 passing examples, 0 failing examples, 3 invalid examples
    - Events:
      * 26.21%, Retried draw from text(characters(codec='utf-8')).filter(not_yet_in_unique_list) to satisfy filter

  - Stopped because settings.max_examples=100


neurochip/tests/properties/test_deployment_properties.py::test_analyzer_neuron_invariant:

  - during generate phase (0.23 seconds):
    - Typical runtimes: ~ 0-2 ms, of which ~ 0-2 ms in data generation
    - 100 passing examples, 0 failing examples, 3 invalid examples
    - Events:
      * 26.21%, Retried draw from text(characters(codec='utf-8')).filter(not_yet_in_unique_list) to satisfy filter

  - Stopped because settings.max_examples=100


neurochip/tests/properties/test_pynq_runtime_properties.py::TestPynqRuntimeProperties::test_output_spikes_are_valid_neuron_indices:

  - during generate phase (0.04 seconds):
    - Typical runtimes: < 1ms, of which < 1ms in data generation
    - 50 passing examples, 0 failing examples, 6 invalid examples

  - Stopped because settings.max_examples=50


neurochip/tests/properties/test_pynq_runtime_properties.py::TestPynqRuntimeProperties::test_result_always_has_required_keys:

  - during generate phase (0.04 seconds):
    - Typical runtimes: < 1ms, of which < 1ms in data generation
    - 50 passing examples, 0 failing examples, 9 invalid examples

  - Stopped because settings.max_examples=50


neurochip/tests/properties/test_pynq_runtime_properties.py::TestPynqRuntimeProperties::test_configure_never_raises_for_valid_input:

  - during generate phase (0.03 seconds):
    - Typical runtimes: < 1ms, of which < 1ms in data generation
    - 50 passing examples, 0 failing examples, 16 invalid examples

  - Stopped because settings.max_examples=50


neurochip/tests/properties/test_pynq_runtime_properties.py::TestPynqRuntimeProperties::test_state_returns_to_configured_after_run:

  - during generate phase (0.03 seconds):
    - Typical runtimes: < 1ms, of which < 1ms in data generation
    - 50 passing examples, 0 failing examples, 12 invalid examples

  - Stopped because settings.max_examples=50


neurochip/tests/properties/test_pynq_runtime_properties.py::TestPynqRuntimeProperties::test_reset_clears_weights:

  - during generate phase (0.05 seconds):
    - Typical runtimes: < 1ms, of which < 1ms in data generation
    - 30 passing examples, 0 failing examples, 8 invalid examples

  - Stopped because settings.max_examples=30


neurochip/tests/properties/test_quantization_properties.py::test_quantization_accuracy_bounds:

  - during generate phase (0.17 seconds):
    - Typical runtimes: ~ 0-2 ms, of which ~ 0-1 ms in data generation
    - 100 passing examples, 0 failing examples, 12 invalid examples
    - Events:
      * 36.61%, Retried draw from text(characters(codec='utf-8')).filter(not_yet_in_unique_list) to satisfy filter

  - Stopped because settings.max_examples=100


neurochip/tests/properties/test_quantization_properties.py::test_quantization_memory_positivity:

  - during generate phase (0.20 seconds):
    - Typical runtimes: ~ 0-2 ms, of which ~ 0-2 ms in data generation
    - 100 passing examples, 0 failing examples, 12 invalid examples
    - Events:
      * 36.61%, Retried draw from text(characters(codec='utf-8')).filter(not_yet_in_unique_list) to satisfy filter

  - Stopped because settings.max_examples=100


=========================== short test summary info ============================
FAILED neurochip/tests/properties/test_contract_properties.py::test_deployment_manifest_firmware_semver
=================== 1 failed, 243 passed, 1 skipped in 3.65s ===================
```

