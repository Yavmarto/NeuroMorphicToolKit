"""Deterministic toy dataset fixtures for adapter bring-up.

These fixtures are intentionally small and synthetic. They give training
adapters a repeatable event-style input source without claiming to be the full
upstream datasets yet.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class EventDatasetFixture:
    name: str
    samples: list[list[list[float]]]
    labels: list[int]
    num_classes: int
    input_size: int
    timesteps: int
    synthetic: bool = True
    dataset_id: str | None = None
    source_path: str | None = None
    source_format: str | None = None


def build_nmnist_fixture(
    *,
    num_samples: int = 16,
    timesteps: int = 12,
    input_size: int = 8,
    num_classes: int = 2,
) -> EventDatasetFixture:
    """Return a deterministic N-MNIST-style toy spike fixture.

    The fixture is shaped like a tiny event tensor sequence:
    ``[sample][timestep][feature]``.
    """

    samples: list[list[list[float]]] = []
    labels: list[int] = []
    split = max(1, input_size // 2)

    for sample_index in range(num_samples):
        label = sample_index % num_classes
        labels.append(label)
        sequence: list[list[float]] = []
        for timestep in range(timesteps):
            frame = [0.0] * input_size
            active_start = 0 if label == 0 else split
            active_stop = split if label == 0 else input_size
            for feature_index in range(active_start, active_stop):
                if (timestep + feature_index + sample_index) % 3 == 0:
                    frame[feature_index] = 1.0
            sequence.append(frame)
        samples.append(sequence)

    return EventDatasetFixture(
        name="n-mnist",
        samples=samples,
        labels=labels,
        num_classes=num_classes,
        input_size=input_size,
        timesteps=timesteps,
    )
