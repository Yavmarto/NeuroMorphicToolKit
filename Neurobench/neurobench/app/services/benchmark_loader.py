import json
import os
import re
import shutil
from pathlib import Path

from app.schemas.benchmarks import BenchmarkDefinition

# Absolute path to the neurobench package root (two levels up from app/services/)
_PACKAGE_ROOT = Path(__file__).parent.parent.parent


class BenchmarkLoader:
    """Loads and serves builtin and custom benchmark definitions."""

    def __init__(
        self,
        builtin_dir: str | None = None,
        custom_dir: str | None = None,
    ) -> None:
        """Initialize the loader and parse available benchmark JSONs.

        Args:
            builtin_dir (str | None): Directory for builtin benchmark JSONs. Defaults to
                ``<package_root>/benchmarks/builtin``.
            custom_dir (str | None): Directory for custom benchmark JSONs. Defaults to
                ``<package_root>/benchmarks/custom``.
        """
        self.builtin_dir = builtin_dir or str(_PACKAGE_ROOT / "benchmarks" / "builtin")
        self.custom_dir = custom_dir or str(_PACKAGE_ROOT / "benchmarks" / "custom")
        self.benchmarks: dict[str, BenchmarkDefinition] = {}
        self.load_benchmarks()

    def _load_from_dir(self, directory: str) -> None:
        """Reads and parses benchmark JSON files from a specific directory.

        Args:
            directory (str): The directory to load benchmarks from.
        """
        if not Path(directory).exists():
            return

        for filename in os.listdir(directory):
            if filename.endswith(".json"):
                filepath = os.path.join(directory, filename)
                try:
                    with open(filepath, encoding="utf-8") as f:
                        data = json.load(f)
                        benchmark = BenchmarkDefinition(**data)
                        self.benchmarks[benchmark.id] = benchmark
                except Exception as e:
                    # In a real app we'd log this, for now just skip invalid files
                    print(f"Failed to load {filepath}: {e}")

    def load_benchmarks(self) -> None:
        """Reads and parses benchmark JSON files from builtin and custom directories."""
        self.benchmarks = {}
        self._load_from_dir(self.builtin_dir)
        self._load_from_dir(self.custom_dir)

    def add_benchmark(self, benchmark: BenchmarkDefinition) -> None:
        """Add a custom benchmark definition and persist it to disk.

        Args:
            benchmark (BenchmarkDefinition): The benchmark definition to add.

        Raises:
            ValueError: If a benchmark with the same ID already exists or ID is invalid.
        """
        if not re.match(r"^[a-zA-Z0-9_\-]+$", benchmark.id):
            raise ValueError(
                f"Invalid benchmark ID '{benchmark.id}'. "
                "Only alphanumeric characters, underscores, and hyphens are allowed."
            )

        if benchmark.id in self.benchmarks:
            raise ValueError(f"Benchmark with ID '{benchmark.id}' already exists")

        # Save to memory
        self.benchmarks[benchmark.id] = benchmark

        # Persist to custom directory
        custom_path = Path(self.custom_dir)
        custom_path.mkdir(parents=True, exist_ok=True)

        filepath = custom_path / f"{benchmark.id}.json"
        with open(filepath, "w", encoding="utf-8") as f:
            f.write(benchmark.model_dump_json(indent=4))

    def get_all(self) -> list[BenchmarkDefinition]:
        """Return all loaded benchmark definitions.

        Returns:
            list[BenchmarkDefinition]: A list of all benchmarks.
        """
        return list(self.benchmarks.values())

    def get(self, benchmark_id: str) -> BenchmarkDefinition | None:
        """Return a specific benchmark definition by ID.

        Args:
            benchmark_id (str): The ID of the benchmark.

        Returns:
            BenchmarkDefinition | None: The benchmark, or None if not found.
        """
        return self.benchmarks.get(benchmark_id)

    def _clear_custom_benchmarks(self) -> None:
        """For testing: Clears all custom benchmarks from memory and disk."""
        custom_path = Path(self.custom_dir)
        if custom_path.exists() and custom_path.is_dir():
            shutil.rmtree(custom_path)
        self.load_benchmarks()


# Expose a singleton instance
benchmark_loader = BenchmarkLoader()
