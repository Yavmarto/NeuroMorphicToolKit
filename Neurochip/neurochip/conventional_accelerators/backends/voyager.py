"""Axelera Voyager backend — wraps existing CEL-237/238 spike scripts."""

from __future__ import annotations

import os
import re

from neurochip.conventional_accelerators.interface import (
    BenchmarkMetrics,
    BenchmarkRequest,
    CompileRequest,
    CompileResult,
    ConventionalAccelerator,
    ExportRequest,
    ExportResult,
)
from neurochip.conventional_accelerators.manifest import ConventionalAcceleratorManifest
from neurochip.conventional_accelerators.paths import repo_root

_SUMMARY_RE = re.compile(
    r"=== Summary: AIPU (?P<speedup>[0-9.]+)x vs CPU",
    re.MULTILINE,
)
_DETECTION_RE = re.compile(
    r"^(cpu_onnx|aipu_axm): (?P<count>\d+) detections in (?P<ms>[0-9.]+) ms",
    re.MULTILINE,
)


def parse_voyager_benchmark_log(text: str, backend: str) -> BenchmarkMetrics:
    """Parse stdout from ``scripts/voyager_aipu_inner.sh``."""
    cpu_ms: float | None = None
    aipu_ms: float | None = None
    detections: int | None = None
    speedup: float | None = None

    for match in _DETECTION_RE.finditer(text):
        label = match.group(1)
        count = int(match.group("count"))
        ms = float(match.group("ms"))
        if label == "cpu_onnx":
            cpu_ms = ms
        else:
            aipu_ms = ms
            detections = count

    summary = _SUMMARY_RE.search(text)
    if summary:
        speedup = float(summary.group("speedup"))

    return BenchmarkMetrics(
        accelerator_ms=aipu_ms,
        baseline_ms=cpu_ms,
        speedup=speedup,
        detection_count=detections,
        backend=backend,
    )


class VoyagerAccelerator(ConventionalAccelerator):
    """CEL-234/237/238 export → compile → benchmark via axelera-devkit spikes."""

    def __init__(self, manifest: ConventionalAcceleratorManifest) -> None:
        super().__init__(manifest)
        self._repo_root = repo_root()

    def export(self, request: ExportRequest) -> ExportResult:
        """Return an existing ONNX file or defer export to the compile spike."""
        request.output_dir.mkdir(parents=True, exist_ok=True)

        if request.model_path.suffix.lower() == ".onnx" and request.model_path.is_file():
            return ExportResult(intermediate_path=request.model_path, format="onnx")

        onnx_path = request.output_dir / f"{request.model_path.stem}.onnx"
        if onnx_path.is_file():
            return ExportResult(intermediate_path=onnx_path, format="onnx")

        raise RuntimeError(
            "Voyager export is handled inside `make voyager-compile-spike` (Docker). "
            "Run compile() or pass an existing .onnx path."
        )

    def compile(self, request: CompileRequest) -> CompileResult:
        request.output_dir.mkdir(parents=True, exist_ok=True)
        command = self.manifest.compile_cmd.replace(
            "./voyager-compile-out", shlex_quote(str(request.output_dir))
        )
        self.run_repo_command(command, cwd=self._repo_root)
        artifact = self.find_first_artifact(request.output_dir, "*.axm")
        return CompileResult(artifact_path=artifact, output_dir=request.output_dir)

    def benchmark(self, request: BenchmarkRequest) -> BenchmarkMetrics:
        if self.manifest.benchmark_cmd is None:
            raise RuntimeError(f"{self.manifest.id} has no benchmark_cmd configured")

        env = os.environ.copy()
        env["ARTIFACT_DIR"] = str(request.output_dir)
        command = self.manifest.benchmark_cmd.replace(
            "./voyager-compile-out", shlex_quote(str(request.output_dir))
        )
        result = self.run_repo_command(command, cwd=self._repo_root, env=env)
        log = "\n".join((result.stdout, result.stderr))
        return parse_voyager_benchmark_log(log, request.baseline_label)


def shlex_quote(value: str) -> str:
    """Minimal quote helper without importing shlex at module import for mypy."""
    from shlex import quote

    return quote(value)
