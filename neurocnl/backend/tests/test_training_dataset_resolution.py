from __future__ import annotations

import asyncio
from pathlib import Path
from unittest.mock import patch

import pytest

from backend.app.services.training_service import _resolve_dataset_payload
from neurocnl.training_registry import AdapterSelectionError


def test_resolve_dataset_payload_uses_cached_path(tmp_path: Path) -> None:
    ready_path = str(tmp_path / "nmnist.h5")
    Path(ready_path).write_bytes(b"fixture")

    async def _run() -> None:
        with patch(
            "backend.app.services.training_service.dataset_cache.get_ready_path",
            return_value=ready_path,
        ):
            payload = await _resolve_dataset_payload({"dataset_id": "nmnist"})

        assert payload["dataset_id"] == "nmnist"
        assert payload["dataset_path"] == ready_path
        assert payload["dataset"] == "nmnist"
        assert payload["dataset_format"] == "hdf5_generic_event"

    asyncio.run(_run())


def test_resolve_dataset_payload_rejects_not_downloaded() -> None:
    async def _run() -> None:
        with (
            patch(
                "backend.app.services.training_service.dataset_cache.get_ready_path",
                return_value=None,
            ),
            pytest.raises(AdapterSelectionError, match="not downloaded"),
        ):
            await _resolve_dataset_payload({"dataset_id": "nmnist"})

    asyncio.run(_run())
