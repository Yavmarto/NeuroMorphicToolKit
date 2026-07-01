"""Tests for neurocnl → Neurochip PYNQ handoff HTTP client."""

from __future__ import annotations

import json
from unittest.mock import MagicMock, patch

from neurocnl.handoff.neurochip_pynq_handoff import NeurochipPynqClient


def _make_urllib_ctx(body: bytes) -> MagicMock:
    m = MagicMock()
    m.read.return_value = body
    m.__enter__ = lambda s: s
    m.__exit__ = MagicMock(return_value=False)
    return m


def test_neurochip_pynq_client_get_status() -> None:
    mock_resp = _make_urllib_ctx(
        json.dumps({"userId": 1, "id": 1, "title": "delectus aut autem", "completed": False}).encode()
    )

    with patch("urllib.request.urlopen", return_value=mock_resp):
        client = NeurochipPynqClient()
        result = client.get_status(
            "https://jsonplaceholder.typicode.com/todos/1",
            headers={"Accept": "application/json"},
            timeout=10.0,
        )

    assert result["id"] == 1
    assert result["userId"] == 1
    assert result["completed"] is False


def test_neurochip_pynq_client_post_deploy() -> None:
    mock_resp = _make_urllib_ctx(
        json.dumps({"id": 101, "title": "pynq_deploy", "body": "ok", "userId": 1}).encode()
    )

    with patch("urllib.request.urlopen", return_value=mock_resp):
        client = NeurochipPynqClient()
        result = client.post_deploy(
            "https://jsonplaceholder.typicode.com/posts",
            payload={"network_id": "lif_reflex_v1", "target": "pynq_z2"},
            headers={"Accept": "application/json"},
            timeout=10.0,
        )

    assert "id" in result
    assert result["id"] == 101
