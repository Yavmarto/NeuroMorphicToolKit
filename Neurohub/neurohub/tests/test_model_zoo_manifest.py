"""Tests for model-zoo manifest normalization helpers."""

from __future__ import annotations

import pytest

from neurohub.app.services.model_zoo_manifest import (
    ManifestValidationError,
    ModelDescriptor,
    ModelZooSummary,
    build_model_zoo_summary,
    normalize_descriptor,
)


def test_normalize_descriptor_preserves_display_name_and_normalizes_fields() -> None:
    """Normalize one descriptor and preserve display_name verbatim."""
    descriptor = ModelDescriptor(
        model_id=" Keyword-Spotter ",
        display_name="Keyword Spotter",
        backends=("Akida", " snnTorch ", "akida"),
        tags=("Audio", " Edge ", "audio"),
        artifact_paths=(" models/keyword.onnx ", "models/keyword.onnx", "docs/keyword.md"),
    )

    normalized = normalize_descriptor(descriptor)

    assert normalized.model_id == "keyword-spotter"
    assert normalized.display_name == "Keyword Spotter"
    assert normalized.backends == ("akida", "snntorch")
    assert normalized.tags == ("audio", "edge")
    assert normalized.artifact_paths == ("models/keyword.onnx", "docs/keyword.md")


def test_build_model_zoo_summary_matches_packet_example() -> None:
    """Build deterministic normalized descriptors and coverage summary."""
    descriptors = (
        ModelDescriptor(
            model_id=" Keyword-Spotter ",
            display_name="Keyword Spotter",
            backends=("Akida", " snnTorch ", "akida"),
            tags=("Audio", " Edge ", "audio"),
            artifact_paths=(" models/keyword.onnx ", "models/keyword.onnx", "docs/keyword.md"),
        ),
        ModelDescriptor(
            model_id="mnist-baseline",
            display_name="MNIST Baseline",
            backends=("Lava", "snnTorch"),
            tags=("vision", "baseline"),
            artifact_paths=("models/mnist.nir",),
        ),
    )

    normalized, summary = build_model_zoo_summary(descriptors)

    assert normalized[0].model_id == "keyword-spotter"
    assert normalized[0].display_name == "Keyword Spotter"
    assert normalized[0].backends == ("akida", "snntorch")
    assert normalized[0].tags == ("audio", "edge")
    assert normalized[0].artifact_paths == ("models/keyword.onnx", "docs/keyword.md")
    assert normalized[1].model_id == "mnist-baseline"
    assert summary == ModelZooSummary(
        total_models=2,
        backend_coverage=("akida", "lava", "snntorch"),
        tag_coverage=("audio", "baseline", "edge", "vision"),
    )


def test_build_model_zoo_summary_rejects_duplicate_model_ids() -> None:
    """Fail closed when normalized model IDs collide."""
    descriptors = (
        ModelDescriptor(" Demo ", "Demo A", ("lava",), ("baseline",), ("a.nir",)),
        ModelDescriptor("demo", "Demo B", ("snntorch",), ("baseline",), ("b.nir",)),
    )

    with pytest.raises(ManifestValidationError, match="duplicate model_id"):
        build_model_zoo_summary(descriptors)


def test_normalize_descriptor_rejects_empty_backend_name() -> None:
    """Reject empty backend names after normalization."""
    descriptor = ModelDescriptor(
        model_id="demo",
        display_name="Demo",
        backends=("   ",),
        tags=("baseline",),
        artifact_paths=("a.nir",),
    )

    with pytest.raises(ManifestValidationError, match="backend names cannot be empty"):
        normalize_descriptor(descriptor)


def test_build_model_zoo_summary_handles_empty_input() -> None:
    """Return an empty descriptor tuple and zero-count summary for empty input."""
    normalized, summary = build_model_zoo_summary(())

    assert normalized == ()
    assert summary == ModelZooSummary(total_models=0, backend_coverage=(), tag_coverage=())


def test_normalize_descriptor_rejects_missing_backends() -> None:
    """Reject descriptors with no backends."""
    descriptor = ModelDescriptor("demo", "Demo", (), ("baseline",), ("a.nir",))

    with pytest.raises(ManifestValidationError, match="at least one backend"):
        normalize_descriptor(descriptor)


def test_normalize_descriptor_rejects_missing_artifact_paths() -> None:
    """Reject descriptors with no artifact paths."""
    descriptor = ModelDescriptor("demo", "Demo", ("lava",), ("baseline",), ())

    with pytest.raises(ManifestValidationError, match="at least one artifact path"):
        normalize_descriptor(descriptor)


def test_normalize_descriptor_rejects_empty_tag_name() -> None:
    """Reject empty tags after normalization."""
    descriptor = ModelDescriptor("demo", "Demo", ("lava",), ("  ",), ("a.nir",))

    with pytest.raises(ManifestValidationError, match="tag names cannot be empty"):
        normalize_descriptor(descriptor)


def test_normalize_descriptor_rejects_empty_artifact_path() -> None:
    """Reject empty artifact paths after trimming."""
    descriptor = ModelDescriptor("demo", "Demo", ("lava",), ("baseline",), (" ",))

    with pytest.raises(ManifestValidationError, match="artifact paths cannot be empty"):
        normalize_descriptor(descriptor)


def test_build_model_zoo_summary_sorts_descriptors_by_normalized_model_id() -> None:
    """Normalize then sort descriptors by model_id."""
    descriptors = (
        ModelDescriptor("z-model", "Z", ("lava",), ("vision",), ("z.nir",)),
        ModelDescriptor("a-model", "A", ("snntorch",), ("audio",), ("a.nir",)),
    )

    normalized, _summary = build_model_zoo_summary(descriptors)

    assert tuple(descriptor.model_id for descriptor in normalized) == ("a-model", "z-model")
