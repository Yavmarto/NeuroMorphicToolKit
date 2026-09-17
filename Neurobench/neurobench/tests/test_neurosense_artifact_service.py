from pathlib import Path

from app.services import neurosense_artifact


def test_summarize_neurosense_artifact_requires_h5py_when_unavailable(tmp_path: Path) -> None:
    artifact = tmp_path / "session.h5"
    artifact.write_bytes(b"placeholder")
    original = neurosense_artifact.h5py
    neurosense_artifact.h5py = None
    try:
        try:
            neurosense_artifact.summarize_neurosense_artifact(artifact)
            raise AssertionError("Expected RuntimeError when h5py is unavailable")
        except RuntimeError as exc:
            assert "h5py" in str(exc)
    finally:
        neurosense_artifact.h5py = original
