from neurochip.contracts.akida_runtime_contract import (
    AkidaEnvironmentChecks,
    AkidaRuntimeStatusContract,
)


def test_akida_runtime_status_contract_accepts_environment_checks() -> None:
    status = AkidaRuntimeStatusContract(
        state="not_initialised",
        sdk_available=False,
        sdk_status="not_available",
        sdk_issues=["unsupported_os", "sdk_not_available"],
        runtime_target="software_fallback",
        environment_checks=AkidaEnvironmentChecks(
            host_supported=False,
            python_supported=True,
            tensorflow_available=False,
            cnn2snn_available=False,
            akida_models_available=False,
            recommended_runtime="simulator_only",
        ),
    )

    assert status.environment_checks.recommended_runtime == "simulator_only"
    assert status.sdk_issues == ["unsupported_os", "sdk_not_available"]
