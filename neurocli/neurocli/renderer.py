"""Template renderer — materialises template bundles into a target directory."""

from __future__ import annotations

import shutil
from pathlib import Path

from jinja2 import Environment, StrictUndefined


class UnknownBundleError(ValueError):
    """Raised when the requested template bundle does not exist."""


_TEMPLATES_DIR = Path(__file__).parent / "templates"
_ENVIRONMENT = Environment(
    autoescape=False,
    keep_trailing_newline=True,
    undefined=StrictUndefined,
)


def _bundle_path(bundle: str) -> Path:
    path = _TEMPLATES_DIR / bundle
    if not path.is_dir():
        available = sorted(p.name for p in _TEMPLATES_DIR.iterdir() if p.is_dir())
        raise UnknownBundleError(f"Unknown template bundle '{bundle}'. Available: {available}")
    return path


def render_template(bundle: str, variables: dict[str, str], dest: Path) -> None:
    """Render template *bundle* into *dest* directory using *variables*.

    ``.jinja`` files are rendered with Jinja and strict undefined variables.
    All other files are copied verbatim.
    The output filename strips the ``.jinja`` suffix.
    """
    src = _bundle_path(bundle)

    for src_file in src.rglob("*"):
        if not src_file.is_file():
            continue
        rel = src_file.relative_to(src)
        # Strip .jinja from destination filename
        dest_rel = Path(*[p for p in rel.parts[:-1]], rel.name.removesuffix(".jinja"))
        dest_file = dest / dest_rel
        dest_file.parent.mkdir(parents=True, exist_ok=True)

        if src_file.suffix == ".jinja":
            template_str = src_file.read_text(encoding="utf-8")
            template = _ENVIRONMENT.from_string(template_str)
            dest_file.write_text(template.render(**variables), encoding="utf-8")
        else:
            shutil.copy2(src_file, dest_file)
