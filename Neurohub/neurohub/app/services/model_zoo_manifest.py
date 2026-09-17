"""Helpers for normalizing model-zoo descriptor metadata."""

from __future__ import annotations

from dataclasses import dataclass


class ManifestValidationError(ValueError):
    """Raised when model-zoo metadata cannot be normalized honestly."""


@dataclass(frozen=True, slots=True)
class ModelDescriptor:
    """Normalized metadata for one model-zoo entry."""

    model_id: str
    display_name: str
    backends: tuple[str, ...]
    tags: tuple[str, ...]
    artifact_paths: tuple[str, ...]


@dataclass(frozen=True, slots=True)
class ModelZooSummary:
    """Aggregate summary over a normalized descriptor collection."""

    total_models: int
    backend_coverage: tuple[str, ...]
    tag_coverage: tuple[str, ...]


def normalize_descriptor(descriptor: ModelDescriptor) -> ModelDescriptor:
    """Return a validated, normalized descriptor."""
    normalized_id = descriptor.model_id.strip().lower()
    if not normalized_id:
        raise ManifestValidationError("model_id cannot be empty after normalization")

    if not descriptor.backends:
        raise ManifestValidationError("descriptor must provide at least one backend")

    normalized_backends = sorted(
        _normalize_unique_values(
            descriptor.backends,
            empty_message="backend names cannot be empty after normalization",
        )
    )

    normalized_tags = sorted(
        _normalize_unique_values(
            descriptor.tags,
            empty_message="tag names cannot be empty after normalization",
        )
    )

    if not descriptor.artifact_paths:
        raise ManifestValidationError("descriptor must provide at least one artifact path")

    normalized_paths: list[str] = []
    seen_paths: set[str] = set()
    for artifact_path in descriptor.artifact_paths:
        trimmed_path = artifact_path.strip()
        if not trimmed_path:
            raise ManifestValidationError("artifact paths cannot be empty after normalization")
        if trimmed_path in seen_paths:
            continue
        normalized_paths.append(trimmed_path)
        seen_paths.add(trimmed_path)

    return ModelDescriptor(
        model_id=normalized_id,
        display_name=descriptor.display_name,
        backends=tuple(normalized_backends),
        tags=tuple(normalized_tags),
        artifact_paths=tuple(normalized_paths),
    )


def build_model_zoo_summary(
    descriptors: tuple[ModelDescriptor, ...],
) -> tuple[tuple[ModelDescriptor, ...], ModelZooSummary]:
    """Normalize descriptors and build deterministic coverage metadata."""
    if not descriptors:
        return (
            (),
            ModelZooSummary(total_models=0, backend_coverage=(), tag_coverage=()),
        )

    normalized_descriptors = [normalize_descriptor(descriptor) for descriptor in descriptors]

    seen_model_ids: set[str] = set()
    for descriptor in normalized_descriptors:
        if descriptor.model_id in seen_model_ids:
            raise ManifestValidationError(
                f"duplicate model_id after normalization: {descriptor.model_id}"
            )
        seen_model_ids.add(descriptor.model_id)

    normalized_descriptors.sort(key=lambda descriptor: descriptor.model_id)

    backend_coverage = sorted(
        {backend for descriptor in normalized_descriptors for backend in descriptor.backends}
    )
    tag_coverage = sorted({tag for descriptor in normalized_descriptors for tag in descriptor.tags})

    return (
        tuple(normalized_descriptors),
        ModelZooSummary(
            total_models=len(normalized_descriptors),
            backend_coverage=tuple(backend_coverage),
            tag_coverage=tuple(tag_coverage),
        ),
    )


def _normalize_unique_values(
    values: tuple[str, ...],
    *,
    empty_message: str,
) -> set[str]:
    """Normalize a string tuple with strip/lower and reject empty results."""
    normalized_values: set[str] = set()
    for value in values:
        normalized = value.strip().lower()
        if not normalized:
            raise ManifestValidationError(empty_message)
        normalized_values.add(normalized)
    return normalized_values
