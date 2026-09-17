"""Shared utilities for the neurocnl package."""

import re

_NUMERIC_RE = re.compile(r"([-+]?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?)")


def extract_numeric(
    condition: str | None, default: float | None = None, absolute: bool = False
) -> float | None:
    """Extract the first numeric value from a condition string.

    Parameters
    ----------
    condition : str | None
        A condition string that may contain a numeric value.
    default : float | None
        Value to return when no number is found.

    Returns
    -------
    float | None
        The extracted numeric value, or *default* if none is found.
    """
    if condition:
        m = _NUMERIC_RE.search(condition)
        if m:
            val = float(m.group(1))
            return abs(val) if absolute else val
    return default
