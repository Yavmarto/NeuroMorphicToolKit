"""Validate a trained CNL/NIR pair and build an offline PYNQ package."""

from __future__ import annotations

import base64
import hashlib
import json
import os
import tempfile
import zipfile
from pathlib import Path
from typing import Any

import httpx
import typer

from neurocli.output import error_exit, print_result

_DEFAULT_API_URL = "http://127.0.0.1:9000"
_SUPPORTED_HARDWARE = ("pynq",)
_REQUIRED_ARCHIVE_MEMBERS = {
    "manifest.json",
    "network.cnl",
    "trained.nir",
    "deploy_request.json",
}


def _api_url(flag: str | None) -> str:
    return (flag or os.environ.get("NMTK_SUITE_API_URL") or _DEFAULT_API_URL).rstrip("/")


def _safe_detail(response: httpx.Response) -> Any:
    try:
        payload = response.json()
        return payload.get("detail", payload) if isinstance(payload, dict) else payload
    except ValueError:
        return response.text


def _post(url: str, *, json: dict[str, Any], json_mode: bool) -> httpx.Response:
    try:
        response = httpx.post(url, json=json, timeout=60.0)
        response.raise_for_status()
        return response
    except httpx.ConnectError:
        error_exit(
            {
                "error": "backend_unreachable",
                "api_url": url.split("/api/", 1)[0],
                "message": "Run `neuro run` and retry.",
            },
            json_mode,
            code=2,
        )
    except httpx.HTTPStatusError as exc:
        error_exit(
            {
                "error": "backend_rejected_deployment",
                "status_code": exc.response.status_code,
                "detail": _safe_detail(exc.response),
            },
            json_mode,
            code=1 if exc.response.status_code < 500 else 2,
        )
    raise AssertionError("error_exit must terminate the command")


def _validate_archive(path: Path) -> None:
    try:
        with zipfile.ZipFile(path) as archive:
            if archive.testzip() is not None:
                raise ValueError("The generated ZIP contains a corrupt member.")
            missing = sorted(_REQUIRED_ARCHIVE_MEMBERS - set(archive.namelist()))
            if missing:
                raise ValueError(f"The generated ZIP is missing: {', '.join(missing)}")
    except (OSError, zipfile.BadZipFile, ValueError) as exc:
        path.unlink(missing_ok=True)
        raise ValueError(f"Invalid offline PYNQ handoff package: {exc}") from exc


def _write_handoff_archive(
    destination: Path,
    *,
    spec_bytes: bytes,
    nir_bytes: bytes,
    deploy_payload: dict[str, Any],
    support_state: str,
    warnings: list[Any],
) -> None:
    deploy_json = json.dumps(deploy_payload, indent=2, sort_keys=True).encode("utf-8")
    manifest = {
        "schema_version": "1.0.0",
        "target": "pynq",
        "package_kind": "validated_offline_handoff",
        "hardware_programmed": False,
        "support_state": support_state,
        "warnings": warnings,
        "files": {
            "network.cnl": hashlib.sha256(spec_bytes).hexdigest(),
            "trained.nir": hashlib.sha256(nir_bytes).hexdigest(),
            "deploy_request.json": hashlib.sha256(deploy_json).hexdigest(),
        },
    }
    with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("network.cnl", spec_bytes)
        archive.writestr("trained.nir", nir_bytes)
        archive.writestr("deploy_request.json", deploy_json)
        archive.writestr("manifest.json", json.dumps(manifest, indent=2, sort_keys=True))


def deploy_command(
    spec: Path = typer.Argument(..., help="Path to the CNL network specification"),
    trained_nir: Path = typer.Option(..., "--trained-nir", help="Trained .nir graph with non-zero weights"),
    hardware: str = typer.Option("pynq", "--hardware", "-hw", help="Offline package target (PoC: pynq)"),
    output: Path = typer.Option(..., "--output", "-o", help="Destination ZIP path"),
    weight_bit_width: int = typer.Option(8, "--weight-bit-width", help="PYNQ overlay weight width"),
    api_url: str | None = typer.Option(None, "--api-url", help="Suite API base URL"),
    json_mode: bool = typer.Option(False, "--json", help="Emit JSON output"),
) -> None:
    """Validate trained weights and write a package without programming hardware."""
    if hardware.lower() not in _SUPPORTED_HARDWARE:
        error_exit(
            {
                "error": "unsupported_hardware",
                "hardware": hardware,
                "supported": list(_SUPPORTED_HARDWARE),
                "message": "The PoC only produces validated offline PYNQ packages.",
            },
            json_mode,
            code=1,
        )
    for label, path, suffix in (
        ("spec", spec, ".cnl"),
        ("trained_nir", trained_nir, ".nir"),
    ):
        if not path.is_file():
            error_exit({"error": "file_not_found", "field": label, "path": str(path)}, json_mode, code=1)
        if path.suffix.lower() != suffix:
            error_exit(
                {"error": "invalid_file_type", "field": label, "expected": suffix, "path": str(path)},
                json_mode,
                code=1,
            )
    if output.exists():
        error_exit({"error": "destination_exists", "path": str(output)}, json_mode, code=1)

    base_url = _api_url(api_url)
    spec_bytes = spec.read_bytes()
    nir_bytes = trained_nir.read_bytes()
    request = {
        "spec": spec_bytes.decode("utf-8"),
        "weight_bit_width": weight_bit_width,
        "trained_nir_base64": base64.b64encode(nir_bytes).decode("ascii"),
    }
    verdict_response = _post(
        f"{base_url}/api/neurocnl/deploy/pynq/network",
        json=request,
        json_mode=json_mode,
    )
    verdict = verdict_response.json()
    support_state = verdict.get("support_state")
    if support_state not in {"exportable", "exportable_with_warnings"}:
        error_exit(
            {
                "error": "not_exportable",
                "support_state": support_state,
                "rejections": verdict.get("rejections", []),
                "warnings": verdict.get("warnings", []),
            },
            json_mode,
            code=1,
        )
    trained_weights = verdict.get("trained_weights") or {}
    if trained_weights.get("applied") is not True:
        error_exit(
            {
                "error": "trained_weights_not_applied",
                "message": "The backend did not apply the supplied trained weights; no package was written.",
                "detail": trained_weights,
            },
            json_mode,
            code=1,
        )
    deploy_payload = verdict.get("deploy_payload")
    if not isinstance(deploy_payload, dict):
        error_exit(
            {
                "error": "missing_deploy_payload",
                "message": "The backend passed validation but returned no package payload.",
            },
            json_mode,
            code=2,
        )

    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=output.parent, prefix=f".{output.name}-", delete=False) as temporary:
        temporary_path = Path(temporary.name)
    try:
        _write_handoff_archive(
            temporary_path,
            spec_bytes=spec_bytes,
            nir_bytes=nir_bytes,
            deploy_payload=deploy_payload,
            support_state=str(support_state),
            warnings=list(verdict.get("warnings", [])),
        )
        _validate_archive(temporary_path)
        temporary_path.rename(output)
    except ValueError as exc:
        temporary_path.unlink(missing_ok=True)
        error_exit(
            {"error": "invalid_package", "message": str(exc)},
            json_mode,
            code=2,
        )
    except Exception:
        temporary_path.unlink(missing_ok=True)
        raise

    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    print_result(
        {
            "status": "packaged",
            "target": "pynq",
            "support_state": support_state,
            "warnings": verdict.get("warnings", []),
            "path": str(output),
            "sha256": digest,
            "hardware_programmed": False,
        },
        json_mode,
    )
