from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class CanonicalPaths:
    repo_root: Path

    @property
    def cnl_grammar_path(self) -> Path:
        return self.repo_root / "neurocnl" / "neurocnl" / "cnl" / "cnl_grammar.md"

    @property
    def support_matrix_path(self) -> Path:
        return self.repo_root / "neurocnl" / "docs" / "support_matrix.md"

    @property
    def modules_manifest_path(self) -> Path:
        return (
            self.repo_root
            / "nmtk"
            / "neuro_toolkit"
            / "assets"
            / "modules.json"
        )


def find_repo_root(start: Path | None = None) -> Path:
    """Return the repository root by locating the top-level AGENTS.md file."""
    origin = (start or Path.cwd()).resolve()
    candidates = (origin,) if origin.is_dir() else (origin.parent,)
    required = ("AGENTS.md", "CODING_STYLE_GUIDE.md")
    for candidate in candidates:
        for parent in (candidate, *candidate.parents):
            if all((parent / part).exists() for part in required):
                return parent
    raise FileNotFoundError(
        f"Could not locate repo root from {origin}. Expected top-level AGENTS.md "
        "and CODING_STYLE_GUIDE.md."
    )


def _read_text(path: Path, label: str) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except FileNotFoundError as exc:
        raise FileNotFoundError(f"Missing canonical {label} file: {path}") from exc


def load_cnl_grammar(paths: CanonicalPaths) -> str:
    """Load the current CNL grammar markdown from disk."""
    return _read_text(paths.cnl_grammar_path, "CNL grammar")


def load_support_matrix(paths: CanonicalPaths) -> str:
    """Load the current support matrix markdown from disk."""
    return _read_text(paths.support_matrix_path, "support matrix")


def load_modules_manifest(paths: CanonicalPaths) -> list[dict[str, Any]]:
    """Load the current module manifest JSON from disk."""
    try:
        payload = json.loads(_read_text(paths.modules_manifest_path, "modules manifest"))
    except json.JSONDecodeError as exc:
        raise ValueError(
            f"Invalid JSON in modules manifest: {paths.modules_manifest_path}"
        ) from exc
    if not isinstance(payload, list):
        raise ValueError(
            f"Expected modules manifest to be a list, got {type(payload).__name__}"
        )
    return payload
