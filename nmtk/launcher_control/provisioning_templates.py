"""Strict rendering for versioned launcher provisioning templates."""

from __future__ import annotations

import re
from collections.abc import Mapping
from pathlib import Path

_TOKEN_PATTERN = re.compile(r"@@([A-Z][A-Z0-9_]*)@@")
_TEMPLATE_ROOT = Path(__file__).with_name("templates")


class ProvisioningTemplateError(ValueError):
    """Raised when a provisioning template and its typed values disagree."""


def render_provisioning_template(
    relative_path: str,
    values: Mapping[str, str],
) -> str:
    """Render one tracked template while rejecting missing or unused values."""
    template_path = _TEMPLATE_ROOT.joinpath(relative_path)
    try:
        source = template_path.read_text(encoding="utf-8")
    except OSError as exc:
        raise ProvisioningTemplateError(
            f"Provisioning template is unavailable: {relative_path}"
        ) from exc

    expected = set(_TOKEN_PATTERN.findall(source))
    provided = set(values)
    missing = expected - provided
    unused = provided - expected
    if missing or unused:
        details = []
        if missing:
            details.append(f"missing values: {', '.join(sorted(missing))}")
        if unused:
            details.append(f"unused values: {', '.join(sorted(unused))}")
        raise ProvisioningTemplateError(
            f"Invalid values for {relative_path}: {'; '.join(details)}"
        )

    rendered = _TOKEN_PATTERN.sub(lambda match: values[match.group(1)], source)
    if _TOKEN_PATTERN.search(rendered):
        raise ProvisioningTemplateError(
            f"Provisioning template still contains tokens: {relative_path}"
        )
    return rendered


__all__ = ["ProvisioningTemplateError", "render_provisioning_template"]
