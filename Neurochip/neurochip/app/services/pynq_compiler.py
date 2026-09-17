"""FINN-backed PYNQ compilation service.

This service validates a NeuroCNL-exported PYNQ artifact ZIP, invokes an
external compiler wrapper, and stages the resulting board-ready overlay assets
for the launcher's existing ``Install Overlay`` flow.
"""

from __future__ import annotations

import json
import os
import shlex
import shutil
import subprocess
import tempfile
import zipfile
from dataclasses import dataclass
from io import BytesIO
from pathlib import Path
from typing import Any, Protocol

from ...contracts.pynq_runtime_artifact_contract import (
    validate_pynq_compile_artifact,
)
from ...provisioning.pynq_overlay_package import (
    DEFAULT_STAGED_OVERLAY_DIR,
    DEFAULT_STAGED_OVERLAY_MANIFEST,
    DEFAULT_STAGED_PYNQ_BITSTREAM_NAME,
    DEFAULT_STAGED_PYNQ_HWH_NAME,
    inspect_staged_overlay_package,
)
from .pynq_overlay_manifest import load_overlay_manifest_file

PYNQ_FINN_COMPILE_CMD_ENV = "NEUROCHIP_PYNQ_FINN_COMPILE_CMD"


@dataclass(frozen=True)
class CompileProcessResult:
    """Normalized compiler process result."""

    returncode: int
    stdout: str = ""
    stderr: str = ""


class PynqCompilerRunnerProtocol(Protocol):
    """Executes the external compiler wrapper."""

    def run(
        self,
        command: list[str],
        *,
        request_path: Path,
        workdir: Path,
    ) -> CompileProcessResult:
        """Run the compile command."""


class SubprocessPynqCompilerRunner:
    """Default runner that shells out to a configured compiler wrapper."""

    def run(
        self,
        command: list[str],
        *,
        request_path: Path,
        workdir: Path,
    ) -> CompileProcessResult:
        proc = subprocess.run(
            [*command, "--request", str(request_path)],
            capture_output=True,
            text=True,
            check=False,
            cwd=str(workdir),
        )
        return CompileProcessResult(
            returncode=proc.returncode,
            stdout=proc.stdout.strip(),
            stderr=proc.stderr.strip(),
        )


class PynqCompileError(RuntimeError):
    """Raised when PYNQ compilation cannot complete."""

    def __init__(self, detail: str, *, error_code: str, status_code: int = 500) -> None:
        self.detail = detail
        self.error_code = error_code
        self.status_code = status_code
        super().__init__(detail)


@dataclass(frozen=True)
class PynqCompileResult:
    """Structured outcome of a successful compile request."""

    compiler: str
    overlay_id: str
    overlay_version: str
    target_part: str
    network_name: str
    total_neurons: int
    total_synapses: int
    staged_overlay: dict[str, Any]
    compiler_stdout: str = ""
    compiler_stderr: str = ""

    def to_dict(self) -> dict[str, Any]:
        return {
            "status": "compiled",
            "compiler": self.compiler,
            "overlay_id": self.overlay_id,
            "overlay_version": self.overlay_version,
            "target_part": self.target_part,
            "network_name": self.network_name,
            "total_neurons": self.total_neurons,
            "total_synapses": self.total_synapses,
            "staged_overlay": self.staged_overlay,
            "compiler_stdout": self.compiler_stdout,
            "compiler_stderr": self.compiler_stderr,
        }


class PynqCompilerService:
    """Validate artifacts, invoke a compiler wrapper, and stage overlay assets."""

    def __init__(
        self,
        *,
        compiler_command: str | None = None,
        runner: PynqCompilerRunnerProtocol | None = None,
        stage_dir: Path | None = None,
    ) -> None:
        self._compiler_command = compiler_command
        self._runner = runner or SubprocessPynqCompilerRunner()
        self._stage_dir = (stage_dir or DEFAULT_STAGED_OVERLAY_DIR).resolve()

    def _resolve_command(self, compiler: str) -> list[str]:
        if compiler != "finn":
            raise PynqCompileError(
                f"Unsupported PYNQ compiler '{compiler}'",
                error_code="PYNQ_COMPILER_UNSUPPORTED",
                status_code=422,
            )

        raw = self._compiler_command or os.getenv(PYNQ_FINN_COMPILE_CMD_ENV, "").strip()
        if not raw:
            raise PynqCompileError(
                (
                    "FINN compiler integration is not configured. "
                    f"Set {PYNQ_FINN_COMPILE_CMD_ENV} to a compiler wrapper command."
                ),
                error_code="PYNQ_FINN_COMPILER_NOT_CONFIGURED",
                status_code=503,
            )

        command = shlex.split(raw)
        if not command:
            raise PynqCompileError(
                f"{PYNQ_FINN_COMPILE_CMD_ENV} did not resolve to a runnable command.",
                error_code="PYNQ_FINN_COMPILER_NOT_CONFIGURED",
                status_code=503,
            )
        return command

    @staticmethod
    def _extract_artifact(zip_bytes: bytes, destination: Path) -> None:
        with zipfile.ZipFile(BytesIO(zip_bytes), "r") as archive:
            for member in archive.namelist():
                member_path = Path(member)
                if member_path.is_absolute() or ".." in member_path.parts:
                    raise PynqCompileError(
                        f"Artifact contains unsafe member path: {member!r}",
                        error_code="PYNQ_COMPILE_ARTIFACT_INVALID",
                        status_code=422,
                    )
            archive.extractall(destination)

    @staticmethod
    def _single_file(output_dir: Path, pattern: str) -> Path | None:
        matches = sorted(output_dir.rglob(pattern))
        if not matches:
            return None
        if len(matches) > 1:
            raise PynqCompileError(
                f"Compiler produced multiple files matching {pattern}: {matches}",
                error_code="PYNQ_COMPILE_AMBIGUOUS_OUTPUT",
            )
        return matches[0]

    def _resolve_output_file(self, output_dir: Path, preferred_name: str) -> Path:
        direct = output_dir / preferred_name
        if direct.exists():
            return direct
        suffix = Path(preferred_name).suffix
        match = self._single_file(output_dir, f"*{suffix}")
        if match is None:
            raise PynqCompileError(
                f"Compiler output is missing required file '{preferred_name}'.",
                error_code="PYNQ_COMPILE_OUTPUT_MISSING",
            )
        return match

    def _stage_overlay_bundle(
        self,
        *,
        bitstream_path: Path,
        hwh_path: Path,
        manifest_payload: str,
    ) -> dict[str, Any]:
        self._stage_dir.mkdir(parents=True, exist_ok=True)

        staged_bitstream = self._stage_dir / DEFAULT_STAGED_PYNQ_BITSTREAM_NAME
        staged_hwh = self._stage_dir / DEFAULT_STAGED_PYNQ_HWH_NAME
        staged_manifest = self._stage_dir / DEFAULT_STAGED_OVERLAY_MANIFEST

        shutil.copyfile(bitstream_path, staged_bitstream)
        shutil.copyfile(hwh_path, staged_hwh)
        staged_manifest.write_text(manifest_payload, encoding="utf-8")

        staged_status = inspect_staged_overlay_package(self._stage_dir)
        if not staged_status.ready:
            raise PynqCompileError(
                "Compiled overlay bundle failed staged-package validation.",
                error_code="PYNQ_COMPILE_STAGING_INVALID",
            )
        return staged_status.to_dict()

    def compile_artifact(
        self,
        artifact_zip_bytes: bytes,
        *,
        compiler: str = "finn",
    ) -> PynqCompileResult:
        try:
            artifact = validate_pynq_compile_artifact(artifact_zip_bytes)
        except (OSError, ValueError, zipfile.BadZipFile, json.JSONDecodeError) as exc:
            raise PynqCompileError(
                f"Invalid PYNQ artifact ZIP: {exc}",
                error_code="PYNQ_COMPILE_ARTIFACT_INVALID",
                status_code=422,
            ) from exc
        command = self._resolve_command(compiler)

        with tempfile.TemporaryDirectory(prefix="neurochip-pynq-compile-") as temp_dir:
            workdir = Path(temp_dir)
            artifact_root = workdir / "artifact"
            output_dir = workdir / "compiled"
            artifact_root.mkdir(parents=True, exist_ok=True)
            output_dir.mkdir(parents=True, exist_ok=True)

            self._extract_artifact(artifact_zip_bytes, artifact_root)

            request_payload = {
                "compiler": compiler,
                "artifact_dir": str((artifact_root / "pynq_deploy").resolve()),
                "output_dir": str(output_dir.resolve()),
                "overlay_id": artifact.overlay_manifest.overlay_id,
                "overlay_version": artifact.overlay_manifest.overlay_version,
                "target_part": artifact.overlay_manifest.target_part,
                "network_name": artifact.overlay_config.network_name,
                "weight_bit_width": artifact.weight_bit_width,
                "total_neurons": artifact.total_neurons,
                "total_synapses": artifact.total_synapses,
            }
            request_path = workdir / "compile_request.json"
            request_path.write_text(json.dumps(request_payload, indent=2), encoding="utf-8")

            process = self._runner.run(command, request_path=request_path, workdir=workdir)
            if process.returncode != 0:
                detail = process.stderr or process.stdout or "Compiler process failed."
                raise PynqCompileError(
                    f"FINN compilation failed: {detail}",
                    error_code="PYNQ_FINN_COMPILE_FAILED",
                    status_code=502,
                )

            bitstream_path = self._resolve_output_file(
                output_dir, DEFAULT_STAGED_PYNQ_BITSTREAM_NAME
            )
            hwh_path = self._resolve_output_file(output_dir, DEFAULT_STAGED_PYNQ_HWH_NAME)

            compiled_manifest_path = output_dir / DEFAULT_STAGED_OVERLAY_MANIFEST
            if compiled_manifest_path.exists():
                try:
                    compiled_manifest = load_overlay_manifest_file(compiled_manifest_path)
                except (OSError, ValueError, json.JSONDecodeError) as exc:
                    raise PynqCompileError(
                        f"Compiler produced an invalid overlay manifest: {exc}",
                        error_code="PYNQ_COMPILE_OUTPUT_INVALID",
                    ) from exc
                if compiled_manifest.model_dump() != artifact.overlay_manifest.model_dump():
                    raise PynqCompileError(
                        "Compiled overlay manifest does not match the requested artifact contract.",
                        error_code="PYNQ_COMPILE_MANIFEST_MISMATCH",
                    )
                manifest_payload = compiled_manifest.model_dump_json(indent=2)
            else:
                manifest_payload = artifact.overlay_manifest.model_dump_json(indent=2)

            staged_overlay = self._stage_overlay_bundle(
                bitstream_path=bitstream_path,
                hwh_path=hwh_path,
                manifest_payload=manifest_payload,
            )

            return PynqCompileResult(
                compiler=compiler,
                overlay_id=artifact.overlay_manifest.overlay_id,
                overlay_version=artifact.overlay_manifest.overlay_version,
                target_part=artifact.overlay_manifest.target_part,
                network_name=artifact.overlay_config.network_name,
                total_neurons=artifact.total_neurons,
                total_synapses=artifact.total_synapses,
                staged_overlay=staged_overlay,
                compiler_stdout=process.stdout,
                compiler_stderr=process.stderr,
            )
