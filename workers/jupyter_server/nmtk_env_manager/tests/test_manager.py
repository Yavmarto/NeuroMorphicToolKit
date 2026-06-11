"""Unit tests for the environment manager (no real venvs / subprocesses)."""
from __future__ import annotations

import json

import pytest

from nmtk_env_manager.manager import (
    BASE_KERNEL,
    EnvironmentError_,
    EnvironmentManager,
    EnvironmentNotFoundError,
    ImmutableEnvironmentError,
    slugify,
)


@pytest.fixture()
def manager(tmp_path):
    return EnvironmentManager(envs_root=tmp_path / "envs", base_python="/usr/bin/python3")


def _seed_env(manager: EnvironmentManager, slug: str, display: str) -> None:
    env_dir = manager.envs_root / slug
    env_dir.mkdir(parents=True)
    (env_dir / "meta.json").write_text(
        json.dumps({"slug": slug, "displayName": display, "basedOn": BASE_KERNEL})
    )


# ── slug generation ──────────────────────────────────────────────────────────
@pytest.mark.parametrize(
    "name,expected",
    [
        ("My Experiments", "my-experiments"),
        ("  Spiking!! 2.0  ", "spiking-2-0"),
        ("", "env"),
        ("////", "env"),
    ],
)
def test_slugify(name, expected):
    assert slugify(name) == expected


def test_unique_slug_avoids_base_and_collisions(manager):
    _seed_env(manager, "experiments", "Experiments")
    assert manager._unique_slug("Experiments") == "experiments-2"
    # A name that slugifies onto the reserved base kernel must be escaped.
    assert manager._unique_slug(BASE_KERNEL) != BASE_KERNEL


# ── immutability guards ──────────────────────────────────────────────────────
def test_base_kernel_is_immutable(manager):
    with pytest.raises(ImmutableEnvironmentError):
        manager.install_packages(BASE_KERNEL, ["numpy"])
    with pytest.raises(ImmutableEnvironmentError):
        manager.uninstall_packages(BASE_KERNEL, ["numpy"])
    with pytest.raises(ImmutableEnvironmentError):
        manager.delete_environment(BASE_KERNEL)


def test_missing_env_raises(manager):
    with pytest.raises(EnvironmentNotFoundError):
        manager.install_packages("ghost", ["numpy"])


# ── delta export ─────────────────────────────────────────────────────────────
def test_export_delta_subtracts_base(manager, monkeypatch):
    _seed_env(manager, "experiments", "Experiments")

    def fake_run(cmd):
        # cmd[0] is the python executable; clone vs base distinguished by path.
        is_clone = "envs" in cmd[0]
        if is_clone:
            return "numpy==1.0\ncowsay==6.1\n"
        return "numpy==1.0\n"

    monkeypatch.setattr(manager, "_run", fake_run)
    body = manager.export_requirements("experiments", mode="delta")
    assert body.strip() == "cowsay==6.1"


def test_export_full_returns_everything(manager, monkeypatch):
    _seed_env(manager, "experiments", "Experiments")
    monkeypatch.setattr(manager, "_run", lambda cmd: "numpy==1.0\ncowsay==6.1\n")
    body = manager.export_requirements("experiments", mode="full")
    assert "numpy==1.0" in body and "cowsay==6.1" in body


# ── listing ──────────────────────────────────────────────────────────────────
def test_list_environments_always_includes_immutable_base(manager, monkeypatch):
    monkeypatch.setattr(manager, "_package_count", lambda python: 0)
    monkeypatch.setattr(manager, "_python_version", lambda python: "3.11.0")
    _seed_env(manager, "experiments", "Experiments")

    envs = manager.list_environments()
    base = next(e for e in envs if e["slug"] == BASE_KERNEL)
    clone = next(e for e in envs if e["slug"] == "experiments")
    assert base["immutable"] is True
    assert clone["immutable"] is False
    assert clone["basedOn"] == BASE_KERNEL


def test_create_environment_with_explicit_slug(manager, monkeypatch):
    """Passing slug= bypasses _unique_slug and uses the provided slug exactly."""
    calls = []

    def fake_run(cmd):
        calls.append(cmd)
        return ""

    monkeypatch.setattr(manager, "_run", fake_run)

    env = manager.create_environment("Python (snnTorch)", slug="nmtk-snntorch")
    assert env["slug"] == "nmtk-snntorch"
    assert env["displayName"] == "Python (snnTorch)"
    # ipykernel install should have been called with --name nmtk-snntorch
    kernel_install = next(c for c in calls if "ipykernel" in c)
    assert "nmtk-snntorch" in kernel_install


def test_create_environment_explicit_slug_skips_uniquify(manager, monkeypatch):
    """Explicit slug is used verbatim even if it would normally be modified."""
    monkeypatch.setattr(manager, "_run", lambda cmd: "")
    env = manager.create_environment("My Env", slug="custom-slug-123")
    assert env["slug"] == "custom-slug-123"


def test_create_environment_explicit_empty_slug_raises(manager):
    """Explicit empty string slug must be rejected."""
    with pytest.raises(EnvironmentError_):
        manager.create_environment("My Env", slug="")
