"""Tests for dataset catalog public API."""

from __future__ import annotations

from backend.app.services.dataset_catalog import (
    SUPPORTED_DATASET_EXTENSIONS,
    is_importable_dataset_filename,
)


def test_supported_extensions_is_public():
    """Test that SUPPORTED_DATASET_EXTENSIONS is exposed as public API."""
    assert ".aedat" in SUPPORTED_DATASET_EXTENSIONS
    assert ".aedat4" in SUPPORTED_DATASET_EXTENSIONS
    assert ".h5" in SUPPORTED_DATASET_EXTENSIONS
    assert ".hdf5" in SUPPORTED_DATASET_EXTENSIONS
    assert ".bin" in SUPPORTED_DATASET_EXTENSIONS


def test_is_importable_dataset_filename() -> None:
    assert is_importable_dataset_filename("sample.aedat4")
    assert is_importable_dataset_filename("archive.zip")
    assert not is_importable_dataset_filename("readme.md")
