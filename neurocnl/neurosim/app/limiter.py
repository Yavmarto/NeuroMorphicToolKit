from collections.abc import Callable
from typing import ParamSpec, TypeVar, cast

from backend.app.middleware.rate_limit import limiter

P = ParamSpec("P")
R = TypeVar("R")


def rate_limit(limit_value: str) -> Callable[[Callable[P, R]], Callable[P, R]]:
    """Wrap SlowAPI's untyped decorator with a typed interface for mypy."""
    return cast("Callable[[Callable[P, R]], Callable[P, R]]", limiter.limit(limit_value))
