"""Static repo invariants for the NIR-Native CNL feature.

This test enforces Requirement 8.6's *literal* scope:

    "no module under ``neurocnl/`` declares — through its top-level
     docstring, its module name, or its sole exported public
     identifiers — a purpose tied exclusively to the
     Biological_Grammar or the Structured_Syntax_Grammar, and no
     remaining module imports a parser, renderer, or compiler entry
     point that targets either legacy grammar."

The earlier broad-scan-of-every-token approach that this file used to
implement was reading Requirement 8.6 too aggressively: it flagged
``refractory_period`` (a Pydantic field name on the ``LIF`` neuron
parameter contract), ``sensory``, and ``motor`` (canvas-graph dict
keys used for legacy template fixtures) as "biological grammar
markers" even when the surrounding module had no narrative tie to the
legacy reflex-arc grammar at all. The user-narrowed reading restricts
the test to the three observable signals listed in Requirement 8.6:

1. **Top-level docstring** — the *first string literal at module
   level* must not describe a biological-grammar / structured-DSL
   purpose (e.g., "biological reflex-arc grammar parser",
   "structured-DSL CNL"). Detection is a small keyword grep against
   the docstring text only.
2. **Module name** — the file name (basename without the ``.py``
   suffix) must not be exclusively bound to a legacy grammar (e.g.
   ``_bio_cnl_parser.py``).
3. **Imports of deleted legacy entry points** — no module imports
   from a deleted legacy parser, renderer, or compiler entry point
   such as ``neurocnl.cnl._bio_cnl_parser`` or
   ``neurocnl.nir_cnl.grammar``.

The captured "manifest" comment block has been replaced with a
reference to ``LEGACY_MANIFEST.md``; the broader sweep that produced
the original 29-file list is out of scope for this test under the
user-narrowed Requirement 8.6 reading and lives in that document for
historical context only.

_Validates: Requirement 8.6_
"""

from __future__ import annotations

import ast
from collections.abc import Iterator
from pathlib import Path

import pytest

# ---------------------------------------------------------------------------
# Scan scope
# ---------------------------------------------------------------------------

# This file lives at:
#   <repo_root>/neurocnl/neurocnl/tests/nir_native_cnl/test_static_repo_invariants.py
# parents[0] = nir_native_cnl/
# parents[1] = tests/
# parents[2] = neurocnl/      (the inner package)
# parents[3] = neurocnl/      (the outer module dir, sibling of neurosim/)
_HERE = Path(__file__).resolve()
_NEUROCNL_PKG_ROOT = _HERE.parents[2]  # .../neurocnl/neurocnl
_NEUROSIM_PKG_ROOT = _HERE.parents[3] / "neurosim"  # .../neurocnl/neurosim
_THIS_TEST_DIR = _HERE.parent  # .../tests/nir_native_cnl

_SCAN_ROOTS: tuple[Path, ...] = (_NEUROCNL_PKG_ROOT, _NEUROSIM_PKG_ROOT)
_EXCLUDED_DIRS: tuple[Path, ...] = (_THIS_TEST_DIR,)
_EXCLUDED_PART_PREFIXES: tuple[str, ...] = (
    "__pycache__",
    ".venv",
    ".pytest_cache",
    ".mypy_cache",
    ".ruff_cache",
)

# ---------------------------------------------------------------------------
# Signal 1: top-level docstring purpose markers
# ---------------------------------------------------------------------------

# These phrases are the *purpose-statement* markers of a legacy-grammar
# module. Each phrase pairs a legacy-grammar name with a role keyword
# (``parser``, ``renderer``, ``compiler``, ``grammar``, or ``module``)
# so that bare descriptive mentions of the legacy grammars — for
# example, the new grammar tables module noting "tokens inherited from
# the legacy reflex-arc CNL" while listing forbidden tokens — do *not*
# trip the test. Only a docstring that claims the module *is* a legacy
# parser/renderer/compiler matches.
#
# Lower-cased substring search; phrases must appear as written.
_LEGACY_DOCSTRING_PHRASES: tuple[str, ...] = (
    "biological reflex-arc grammar parser",
    "biological reflex-arc grammar renderer",
    "biological reflex-arc grammar compiler",
    "biological reflex-arc cnl parser",
    "biological reflex-arc cnl renderer",
    "biological reflex-arc cnl compiler",
    "biological-grammar parser",
    "biological-grammar renderer",
    "biological-grammar compiler",
    "biological cnl parser",
    "biological cnl renderer",
    "biological cnl compiler",
    "structured-dsl parser",
    "structured-dsl renderer",
    "structured-dsl compiler",
    "structured-syntax grammar parser",
    "structured-syntax grammar renderer",
    "structured-syntax grammar compiler",
    "structured-syntax cnl parser",
    "structured-syntax cnl renderer",
    "structured-syntax cnl compiler",
)

# ---------------------------------------------------------------------------
# Signal 2: module names exclusively bound to legacy grammar
# ---------------------------------------------------------------------------

# Module basenames (without ``.py``) that a developer could only have
# named with the intent of housing a legacy-grammar module. These
# names mirror the entries that appeared in tasks 1.2 and 1.3 of the
# implementation plan.
_LEGACY_MODULE_BASENAMES: frozenset[str] = frozenset(
    {
        "_bio_cnl_parser",
        "_bio_cnl_renderer",
        "_bio_cnl_compiler",
        "bio_cnl_parser",
        "bio_cnl_renderer",
        "bio_cnl_compiler",
        "structured_dsl_parser",
        "structured_dsl_renderer",
        "structured_dsl_compiler",
        # ``grammar.py`` under ``nir_cnl`` was the legacy structured-DSL
        # grammar definition; the new package replaces it with
        # ``grammar_tables.py``.
        "structured_dsl_grammar",
    }
)

# ---------------------------------------------------------------------------
# Signal 3: imports of deleted legacy entry points
# ---------------------------------------------------------------------------

# Each entry is the fully-qualified module path of a deleted legacy
# parser / renderer / compiler that no surviving module may import
# from. Both ``import X`` and ``from X import ...`` are checked.
_LEGACY_IMPORT_PREFIXES: tuple[str, ...] = (
    "neurocnl.cnl._bio_cnl_parser",
    "neurocnl.cnl.bio_cnl_parser",
    "neurocnl.cnl._bio_cnl_renderer",
    "neurocnl.cnl._bio_cnl_compiler",
    "neurocnl.nir_cnl.grammar",  # replaced by grammar_tables
)


# ---------------------------------------------------------------------------
# File discovery
# ---------------------------------------------------------------------------


def _iter_python_files() -> Iterator[Path]:
    """Yield every ``.py`` file under the scan roots, excluding test fixtures."""
    for root in _SCAN_ROOTS:
        if not root.exists():
            continue
        for py_path in sorted(root.rglob("*.py")):
            # Exclude this test directory entirely (test data lives here).
            if any(excluded in py_path.parents for excluded in _EXCLUDED_DIRS):
                continue
            # Exclude virtualenvs and tool caches that live under the roots.
            if any(
                part.startswith(prefix)
                for part in py_path.parts
                for prefix in _EXCLUDED_PART_PREFIXES
            ):
                continue
            yield py_path


# ---------------------------------------------------------------------------
# Per-file checks
# ---------------------------------------------------------------------------


def _read_source(py_path: Path) -> str | None:
    """Read a Python source file, returning ``None`` on read failure."""
    try:
        return py_path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return None


def _parse_module(source: str) -> ast.Module | None:
    """Parse *source* into an AST module, returning ``None`` on syntax error."""
    try:
        return ast.parse(source)
    except SyntaxError:
        return None


def _check_docstring(module: ast.Module) -> str | None:
    """Return a phrase if the module's top-level docstring is legacy-tied."""
    docstring = ast.get_docstring(module)
    if not docstring:
        return None
    lowered = docstring.lower()
    for phrase in _LEGACY_DOCSTRING_PHRASES:
        if phrase in lowered:
            return phrase
    return None


def _check_module_name(py_path: Path) -> str | None:
    """Return the basename if it identifies a legacy-grammar module."""
    base = py_path.stem
    if base in _LEGACY_MODULE_BASENAMES:
        return base
    return None


def _check_imports(module: ast.Module) -> list[str]:
    """Return every legacy import prefix referenced by *module*."""
    offenders: list[str] = []
    for node in ast.walk(module):
        if isinstance(node, ast.Import):
            for alias in node.names:
                for prefix in _LEGACY_IMPORT_PREFIXES:
                    if alias.name == prefix or alias.name.startswith(prefix + "."):
                        offenders.append(alias.name)
        elif isinstance(node, ast.ImportFrom):
            if node.module is None:
                continue
            for prefix in _LEGACY_IMPORT_PREFIXES:
                if node.module == prefix or node.module.startswith(prefix + "."):
                    offenders.append(node.module)
    return offenders


def _scan_file(py_path: Path) -> list[str]:
    """Return human-readable offense descriptions for ``py_path``.

    An empty list means the file is clean per the three signals
    Requirement 8.6 actually documents.
    """
    source = _read_source(py_path)
    if source is None:
        return []  # unreadable — treat as not-scannable

    module = _parse_module(source)
    if module is None:
        return []  # parse error — out of scope

    offenses: list[str] = []

    # 1. Top-level docstring purpose marker.
    phrase = _check_docstring(module)
    if phrase is not None:
        offenses.append(
            f"top-level docstring describes a legacy-grammar purpose: matched phrase {phrase!r}"
        )

    # 2. Module name exclusively bound to legacy grammar.
    name_match = _check_module_name(py_path)
    if name_match is not None:
        offenses.append(
            f"module name {name_match!r} is exclusively bound to a legacy "
            f"grammar (Requirement 8.6 signal 2)."
        )

    # 3. Imports of deleted legacy entry points.
    legacy_imports = _check_imports(module)
    for legacy_import in sorted(set(legacy_imports)):
        offenses.append(
            f"imports deleted legacy entry point {legacy_import!r} (Requirement 8.6 signal 3)."
        )

    return offenses


# ---------------------------------------------------------------------------
# Test entry point
# ---------------------------------------------------------------------------


def test_no_legacy_grammar_module_purpose_or_imports() -> None:
    """No surviving module under ``neurocnl/`` or ``neurosim/`` declares
    a legacy-grammar purpose through its top-level docstring, its name,
    or its imports.

    This is the user-narrowed reading of Requirement 8.6: only the three
    observable signals listed in the requirement are checked. The
    broader sweep of "every legacy token in any source byte" is recorded
    in ``LEGACY_MANIFEST.md`` for historical context but is out of scope
    here — Pydantic field names and dict keys (``refractory_period``,
    ``sensory``, ``motor``) on a non-legacy module do not constitute a
    Requirement 8.6 violation.

    _Validates: Requirement 8.6_
    """
    # Sanity check: scan roots must exist.
    assert _NEUROCNL_PKG_ROOT.is_dir(), f"neurocnl package root not found at {_NEUROCNL_PKG_ROOT}"

    offenses_by_file: dict[str, list[str]] = {}
    for py_path in _iter_python_files():
        offenses = _scan_file(py_path)
        if offenses:
            try:
                rel = py_path.relative_to(_HERE.parents[4])
            except ValueError:
                rel = py_path
            offenses_by_file[str(rel)] = offenses

    if offenses_by_file:
        report_lines = [
            "Requirement 8.6 violation(s) found:",
            f"(scan roots: {[str(r) for r in _SCAN_ROOTS]}):",
            "",
        ]
        for path in sorted(offenses_by_file):
            report_lines.append(f"  {path}")
            for offense in offenses_by_file[path]:
                report_lines.append(f"    - {offense}")
        report_lines.append("")
        report_lines.append(f"Total offending files: {len(offenses_by_file)}")
        pytest.fail("\n".join(report_lines))


# ---------------------------------------------------------------------------
# Manifest reference
# ---------------------------------------------------------------------------
#
# The historical "broad scan" manifest captured by an earlier draft of
# this test (29 offending files at the time) lives at
# ``neurocnl/neurocnl/tests/nir_native_cnl/LEGACY_MANIFEST.md``. The
# entries in that document are *not* enforced by this test under the
# user-narrowed Requirement 8.6 reading; they are kept only for
# historical and inventory context. If a future spec change rebroadens
# the scan, restore the byte-level token sweep here.
