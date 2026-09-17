from pathlib import Path
from typing import Any
from unittest.mock import patch

import numpy as np
import pytest

from neurosense.app.services.replay_service import ReplayService


@pytest.mark.anyio
async def test_replay_lifecycle(canonical_session_id: str, session_fixture_dir: Path) -> None:
    service = ReplayService()

    with patch("neurosense.app.services.replay_service._RECORDINGS_DIR", session_fixture_dir):
        result = await service.start(canonical_session_id, speed=2.0)

        assert service.is_active is True
        assert result["session_id"] == canonical_session_id
        assert result["speed"] == 2.0

        stop_result = await service.stop()
        assert service.is_active is False
        assert stop_result["status"] == "stopped"


@pytest.mark.anyio
async def test_replay_file_not_found() -> None:
    service = ReplayService()
    with (
        patch("pathlib.Path.exists", return_value=False),
        pytest.raises(FileNotFoundError),
    ):
        await service.start("invalid_session")


@pytest.mark.anyio
async def test_stream_chunks_uses_canonical_timestamps(
    canonical_session_id: str, session_fixture_dir: Path
) -> None:
    service = ReplayService()
    chunks: list[np.ndarray[Any, Any]] = []

    async def fast_sleep(_: float) -> None:
        return None

    with (
        patch("neurosense.app.services.replay_service._RECORDINGS_DIR", session_fixture_dir),
        patch("asyncio.sleep", new=fast_sleep),
    ):
        await service.start(canonical_session_id)

        async for chunk in service.stream_chunks(chunk_samples=50):
            chunks.append(chunk)
            if len(chunks) >= 3:
                break

    assert len(chunks) == 3
    assert chunks[0].shape == (2, 50)
    assert np.isclose(chunks[0][0, 0], 0.0)
    assert np.isclose(chunks[0][1, 0], 1.0)


@pytest.mark.anyio
async def test_replay_already_active(canonical_session_id: str, session_fixture_dir: Path) -> None:
    service = ReplayService()
    with patch("neurosense.app.services.replay_service._RECORDINGS_DIR", session_fixture_dir):
        await service.start(canonical_session_id)
        with pytest.raises(RuntimeError, match="A replay is already active"):
            await service.start("session2")
