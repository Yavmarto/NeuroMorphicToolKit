import time
from typing import Any

import numpy as np


class MockBoardShim:
    """Mock implementation of brainflow.BoardShim for testing."""

    def __init__(self, board_id: int, params: Any) -> None:
        self.board_id = board_id
        self.params = params
        self.is_prepared = False
        self.is_streaming = False
        self._start_time: float | None = None
        self._sampling_rate = self.get_sampling_rate(board_id)
        self._num_channels = 32  # Enough room to emulate BrainFlow-style channel indexing
        self._rng = np.random.default_rng(42)

    def prepare_session(self) -> None:
        if self.is_prepared:
            raise RuntimeError("Session already prepared")
        self.is_prepared = True

    def start_stream(self, num_samples: int = 45000, streamer_params: str | None = None) -> None:
        if not self.is_prepared:
            raise RuntimeError("Session not prepared")
        if self.is_streaming:
            raise RuntimeError("Stream already started")
        self.is_streaming = True
        self._start_time = time.time()

    def stop_stream(self) -> None:
        if not self.is_streaming:
            raise RuntimeError("Stream not started")
        self.is_streaming = False

    def release_session(self) -> None:
        if not self.is_prepared:
            raise RuntimeError("Session not prepared")
        self.is_prepared = False

    def get_current_board_data(self, num_samples: int) -> np.ndarray[Any, Any]:
        if not self.is_streaming:
            return np.zeros((self._num_channels, 0))

        # Generate synthetic data: sine waves + noise
        data = np.zeros((self._num_channels, num_samples))
        eeg_channels = self.get_eeg_channels(self.board_id)

        # Use current time to make the sine wave continuous-ish
        now = time.time()
        t = np.linspace(now, now + num_samples / self._sampling_rate, num_samples, endpoint=False)

        for i, ch in enumerate(eeg_channels):
            # Different freq for each channel to distinguish them
            freq = 10 + i * 2
            data[ch] = 100 * np.sin(2 * np.pi * freq * t) + 10 * self._rng.standard_normal(
                num_samples
            )

        return data

    @staticmethod
    def get_eeg_channels(board_id: int) -> list[int]:
        if board_id == 1:
            return [1, 2, 3, 4]
        if board_id in {38, 39, 22}:
            return [1, 2, 3, 4]
        return list(range(1, 9))

    @staticmethod
    def get_sampling_rate(board_id: int) -> int:
        if board_id == 1:
            return 200
        if board_id in {38, 39, 22}:
            return 256
        return 250

    @staticmethod
    def get_board_id(board_id: int) -> int:
        return board_id
