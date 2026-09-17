"""Shared export → compile → benchmark interface for conventional accelerators."""

from __future__ import annotations

import shlex
import subprocess
from abc import ABC, abstractmethod
from dataclasses import dataclass
from pathlib import Path

from neurochip.conventional_accelerators.manifest import ConventionalAcceleratorManifest


@dataclass(frozen=True)
class ExportRequest:
    """Input for the export stage."""

    model_path: Path
    output_dir: Path


@dataclass(frozen=True)
class ExportResult:
    """Intermediate artifact produced before vendor compilation."""

    intermediate_path: Path
    format: str


@dataclass(frozen=True)
class CompileRequest:
    """Input for the vendor compile stage."""

    intermediate_path: Path | None
    output_dir: Path


@dataclass(frozen=True)
class CompileResult:
    """Compiled accelerator artifact."""

    artifact_path: Path
    output_dir: Path


@dataclass(frozen=True)
class BenchmarkRequest:
    """Input for accelerator vs baseline timing."""

    artifact_path: Path
    output_dir: Path
    baseline_label: str = "cpu_onnx"


@dataclass(frozen=True)
class BenchmarkMetrics:
    """Recorded spike numbers for runbooks and CI tables."""

    accelerator_ms: float | None
    baseline_ms: float | None
    speedup: float | None
    detection_count: int | None
    backend: str
    notes: str = ""


@dataclass(frozen=True)
class CommandResult:
    """Captured output from a repo-root spike command."""

    returncode: int
    stdout: str
    stderr: str


class ConventionalAccelerator(ABC):
    """Export → compile → benchmark lifecycle shared by Voyager, Jetson, QNN, Coral."""

    def __init__(self, manifest: ConventionalAcceleratorManifest) -> None:
        self.manifest = manifest

    @abstractmethod
    def export(self, request: ExportRequest) -> ExportResult:
        """Export a trained model into the vendor's required intermediate format."""

    @abstractmethod
    def compile(self, request: CompileRequest) -> CompileResult:
        """Run the vendor compiler to produce a deployable artifact."""

    @abstractmethod
    def benchmark(self, request: BenchmarkRequest) -> BenchmarkMetrics:
        """Benchmark the compiled artifact against a CPU/ONNX baseline."""

    def run_repo_command(
        self,
        command: str,
        *,
        cwd: Path,
        env: dict[str, str] | None = None,
    ) -> CommandResult:
        """Execute a manifest command and return captured output."""
        completed = subprocess.run(
            command,
            shell=True,
            cwd=cwd,
            env=env,
            check=False,
            text=True,
            capture_output=True,
        )
        if completed.returncode != 0:
            raise RuntimeError(
                f"Command failed ({completed.returncode}): {command}\n"
                f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
            )
        return CommandResult(
            returncode=completed.returncode,
            stdout=completed.stdout,
            stderr=completed.stderr,
        )

    @staticmethod
    def find_first_artifact(output_dir: Path, pattern: str) -> Path:
        """Return the first matching artifact under ``output_dir``."""
        matches = sorted(output_dir.rglob(pattern))
        if not matches:
            raise FileNotFoundError(f"No {pattern} under {output_dir}")
        return matches[0]

    @staticmethod
    def split_command(command: str) -> list[str]:
        """Split a manifest command for dry-run tests."""
        return shlex.split(command)
