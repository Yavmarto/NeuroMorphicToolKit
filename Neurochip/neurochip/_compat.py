"""Compatibility helpers for supported Neurochip Python runtimes."""

import sys
from enum import Enum

if sys.version_info >= (3, 11):  # noqa: UP036
    from datetime import UTC
    from enum import StrEnum
else:  # pragma: no cover - exercised by Python 3.10 Lava images
    from datetime import timezone

    UTC = timezone.utc  # noqa: UP017 - datetime.UTC is unavailable on Python 3.10.

    class StrEnum(str, Enum):  # noqa: UP042
        """Python 3.10 fallback for enum.StrEnum."""


__all__ = ["StrEnum", "UTC"]
