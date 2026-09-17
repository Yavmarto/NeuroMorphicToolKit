from __future__ import annotations

import pytest
from neurochip.app.services import akida_backend


def test_akida_runtime_status_snapshot_for_simulator_fallback(
    monkeypatch: pytest.MonkeyPatch,
    snapshot: object,
) -> None:
    monkeypatch.setattr(akida_backend, "AKIDA_AVAILABLE", False)
    monkeypatch.setattr(akida_backend, "_current_platform_key", lambda: "linux")
    monkeypatch.setattr(akida_backend, "_current_python_version_tuple", lambda: (3, 11, 8))
    monkeypatch.setattr(
        akida_backend,
        "_module_available",
        lambda name: name in {"tensorflow", "cnn2snn"},
    )

    result = akida_backend.build_akida_runtime_status(
        state="constructed",
        model_summary={
            "population_count": 2,
            "connection_count": 3,
            "bit_width": 4,
            "estimated_neurons": 192,
        },
    )

    assert result == snapshot
