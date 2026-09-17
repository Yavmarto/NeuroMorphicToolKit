"""Truthful companion views for deployed Akida models."""

from __future__ import annotations

import base64
import hashlib
import sys
import zlib
from pathlib import Path
from types import SimpleNamespace
from typing import Any

import numpy as np
import pytest
from fastapi.testclient import TestClient

from neurochip.app.main import app
from neurochip.app.routers import akida as akida_router
from neurochip.app.services.akida_model_jobs import (
    AkidaModelJobError,
    AkidaModelJobService,
)
from neurochip.contracts.akida_model_bundle_contract import (
    AkidaModelVisualizationRequest,
    AkidaVisualizationMode,
)
from neurochip.tests.test_akida_model_jobs_v2 import _v2_bundle_bytes


class _ReplayLayer:
    def __init__(self, name: str, weights: np.ndarray[Any, Any]) -> None:
        self.name = name
        self.output_shape = (1, 1, weights.shape[-1])
        self.parameters = SimpleNamespace(weights_bits=8)
        self._weights = weights

    def get_variable(self, name: str) -> np.ndarray[Any, Any]:
        if name != "weights":
            raise KeyError(name)
        return self._weights


class _InputLayer:
    name = "Input"
    output_shape = (1, 1, 784)


class _ReplayModel:
    def __init__(self, layers: list[object]) -> None:
        self.layers = layers
        self.forward_calls = 0

    def forward(self, inputs: np.ndarray[Any, Any]) -> np.ndarray[Any, Any]:
        self.forward_calls += 1
        count = len(inputs)
        return np.arange(count * 3, dtype=np.uint8).reshape(count, 1, 1, 3)


class _FakeAkidaModule:
    def __init__(self) -> None:
        self.model_loads = 0
        self.map_calls = 0
        self.prefixes: list[_ReplayModel] = []
        self.layers = [
            _InputLayer(),
            _ReplayLayer("Hidden", np.asarray([[1, -2, 3], [4, -5, 6]], dtype=np.int8)),
        ]

    def Model(self, path: str | None = None, *, layers: list[object] | None = None) -> _ReplayModel:  # noqa: N802
        if layers is not None:
            prefix = _ReplayModel(layers)
            self.prefixes.append(prefix)
            return prefix
        assert path is not None
        self.model_loads += 1
        return _ReplayModel(self.layers)

    def map(self, _device: object) -> None:
        self.map_calls += 1


def _prepared_service(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> tuple[AkidaModelJobService, str, _FakeAkidaModule]:
    service = AkidaModelJobService(tmp_path)
    bundle_bytes = _v2_bundle_bytes()
    model_id = hashlib.sha256(bundle_bytes).hexdigest()[:24]
    model_dir = tmp_path / model_id
    model_dir.mkdir()
    (model_dir / "bundle.zip").write_bytes(bundle_bytes)
    (model_dir / "model.fbz").write_bytes(b"exact-deployed-model")
    service._bundles[model_id] = service._validate_bundle(bundle_bytes)
    service._model_targets[model_id] = ("hardware", "AKD1000")
    fake_akida = _FakeAkidaModule()
    monkeypatch.setitem(sys.modules, "akida", fake_akida)
    return service, model_id, fake_akida


def _decode(payload: object) -> np.ndarray[Any, Any]:
    dtype = np.dtype(getattr(payload, "dtype"))
    shape = tuple(getattr(payload, "shape"))
    raw = zlib.decompress(base64.b64decode(getattr(payload, "data")))
    return np.frombuffer(raw, dtype=dtype).reshape(shape)


def test_sample_replay_returns_exact_activations_weights_and_provenance(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    service, model_id, fake_akida = _prepared_service(tmp_path, monkeypatch)

    result = service.visualize(
        model_id,
        AkidaModelVisualizationRequest(
            mode=AkidaVisualizationMode.SAMPLE, layerIndex=1, sampleIndex=2
        ),
    )

    assert result.available is True
    assert result.provenance == "akida_software_replay"
    assert result.related_runtime_target == "hardware"
    assert result.hardware_verified is False
    assert result.sample_count == 1
    assert _decode(result.activity).tolist() == [0, 1, 2]
    assert _decode(result.weights).tolist() == [[1, -2, 3], [4, -5, 6]]
    assert result.weight_bits == 8
    assert fake_akida.map_calls == 0


def test_benchmark_replay_returns_mean_activity_and_nonzero_matrix(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    service, model_id, _fake_akida = _prepared_service(tmp_path, monkeypatch)

    result = service.visualize(
        model_id,
        AkidaModelVisualizationRequest(mode=AkidaVisualizationMode.BENCHMARK, layerIndex=1),
    )

    assert result.sample_count == 8
    assert _decode(result.activity).tolist() == pytest.approx([10.5, 11.5, 12.5])
    raster = _decode(result.raster)
    assert raster.shape == (8, 3)
    assert raster[0].tolist() == [0, 1, 1]
    assert raster[-1].tolist() == [1, 1, 1]


def test_replay_cache_avoids_reloading_same_view(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    service, model_id, fake_akida = _prepared_service(tmp_path, monkeypatch)
    request = AkidaModelVisualizationRequest(
        mode=AkidaVisualizationMode.SAMPLE, layerIndex=1, sampleIndex=0
    )

    first = service.visualize(model_id, request)
    second = service.visualize(model_id, request)

    assert first == second
    assert first is not second
    assert fake_akida.model_loads == 1


def test_missing_model_and_invalid_layer_are_actionable(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    service, model_id, _fake_akida = _prepared_service(tmp_path, monkeypatch)

    with pytest.raises(AkidaModelJobError) as missing:
        service.visualize(
            "missing",
            AkidaModelVisualizationRequest(mode=AkidaVisualizationMode.SAMPLE, layerIndex=1),
        )
    assert missing.value.error_code == "MODEL_NOT_LOADED"

    with pytest.raises(AkidaModelJobError) as invalid:
        service.visualize(
            model_id,
            AkidaModelVisualizationRequest(mode=AkidaVisualizationMode.SAMPLE, layerIndex=9),
        )
    assert invalid.value.error_code == "VISUALIZATION_LAYER_INVALID"


def test_unisolatable_layer_returns_truthful_unavailable_state(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    service, model_id, fake_akida = _prepared_service(tmp_path, monkeypatch)

    def failing_model(
        path: str | None = None, *, layers: list[object] | None = None
    ) -> _ReplayModel:
        if layers is not None:
            raise ValueError("branched graph cannot form a prefix")
        assert path is not None
        return _ReplayModel(fake_akida.layers)

    monkeypatch.setattr(fake_akida, "Model", failing_model)
    result = service.visualize(
        model_id, AkidaModelVisualizationRequest(mode=AkidaVisualizationMode.SAMPLE, layerIndex=1)
    )

    assert result.available is False
    assert "cannot be isolated" in (result.unavailable_reason or "")
    assert result.activity is None
    assert result.hardware_verified is False


def test_visualization_endpoint_preserves_typed_camel_case_contract(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    service, model_id, _fake_akida = _prepared_service(tmp_path, monkeypatch)
    result = service.visualize(
        model_id,
        AkidaModelVisualizationRequest(
            mode=AkidaVisualizationMode.SAMPLE, layerIndex=1, sampleIndex=0
        ),
    )
    monkeypatch.setattr(
        akida_router.akida_model_job_service,
        "visualize",
        lambda _model_id, _request: result,
    )

    response = TestClient(app).post(
        f"/api/neurochip/akida/models/{model_id}/visualization",
        json={"mode": "sample", "layerIndex": 1, "sampleIndex": 0},
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["modelId"] == model_id
    assert payload["layerIndex"] == 1
    assert payload["hardwareVerified"] is False
    assert payload["provenance"] == "akida_software_replay"
    assert payload["weights"]["encoding"] == "zlib+base64"
