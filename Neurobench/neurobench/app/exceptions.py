class BenchmarkExecutionError(Exception):
    """Raised when a benchmark execution fails on the hardware backend."""

    pass


class OptionalDependencyError(BenchmarkExecutionError):
    """Raised when an optional runtime dependency is required but unavailable."""

    pass


class SpikeFidelityError(BenchmarkExecutionError):
    """Raised when spike fidelity metrics are invalid or unusable."""

    pass


class BenchmarkTimeoutError(BenchmarkExecutionError):
    """Raised when a benchmark execution times out."""

    pass
