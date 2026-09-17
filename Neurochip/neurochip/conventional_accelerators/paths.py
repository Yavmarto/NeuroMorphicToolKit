"""Filesystem locations for conventional accelerator manifests."""

from pathlib import Path


def conventional_targets_dir() -> Path:
    """Directory holding ``conventional_targets/*.json`` manifests."""
    return Path(__file__).resolve().parent.parent / "conventional_targets"


def repo_root() -> Path:
    """Monorepo root (parent of the Neurochip module directory)."""
    return Path(__file__).resolve().parent.parent.parent.parent
