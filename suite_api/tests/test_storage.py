"""Tests for durable owner-specific Suite API paths."""

from pathlib import Path

import pytest

from suite_api.storage import (
    default_neurocnl_data_dir,
    default_neurohub_db_url,
    owner_data_dir,
)


@pytest.fixture(autouse=True)
def _clean_storage_environment(monkeypatch: pytest.MonkeyPatch) -> None:
    for name in (
        "NEUROHUB_DB_URL",
        "NEUROHUB_DATA_DIR",
        "NEUROCNL_DATA_DIR",
        "NMTK_DATA_DIR",
    ):
        monkeypatch.delenv(name, raising=False)


def test_new_install_uses_owner_directory(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    monkeypatch.setenv("NMTK_DATA_DIR", str(tmp_path))

    assert owner_data_dir("neurohub", override_env="NEUROHUB_DATA_DIR") == (
        tmp_path / "neurohub"
    )
    assert default_neurohub_db_url() == (
        f"sqlite:///{tmp_path / 'neurohub' / 'neurohub.db'}"
    )
    assert default_neurocnl_data_dir() == tmp_path / "neurocnl"


def test_explicit_module_directory_has_priority(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    module_dir = tmp_path / "existing-neurohub"
    monkeypatch.setenv("NMTK_DATA_DIR", str(tmp_path / "new-root"))
    monkeypatch.setenv("NEUROHUB_DATA_DIR", str(module_dir))

    assert default_neurohub_db_url() == f"sqlite:///{module_dir / 'neurohub.db'}"


def test_legacy_shared_directory_is_preserved(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    monkeypatch.setenv("NEUROCNL_DATA_DIR", str(tmp_path))
    monkeypatch.setenv("NMTK_DATA_DIR", str(tmp_path / "new-root"))

    assert default_neurohub_db_url() == f"sqlite:///{tmp_path / 'neurohub.db'}"


def test_explicit_database_url_wins(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("NEUROHUB_DB_URL", "sqlite:////existing/neurohub.db")

    assert default_neurohub_db_url() == "sqlite:////existing/neurohub.db"


def test_neurocnl_legacy_directory_has_priority(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    monkeypatch.setenv("NMTK_DATA_DIR", str(tmp_path / "new-root"))
    monkeypatch.setenv("NEUROCNL_DATA_DIR", str(tmp_path / "existing"))

    assert default_neurocnl_data_dir() == tmp_path / "existing"
