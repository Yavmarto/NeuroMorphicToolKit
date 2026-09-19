#!/usr/bin/env python3
"""CEL-372: capture Akida hardware export/deploy evidence via model-jobs API."""

from __future__ import annotations

import base64
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

NEUROCHIP_URL = os.environ.get("NEUROCHIP_URL", "http://127.0.0.1:8002").rstrip("/")
BUNDLE_PATH = Path(
    os.environ.get(
        "AKIDA_BUNDLE_PATH",
        "/home/moosebun2/akida_test/model.akida-bundle.zip",
    )
)
MANIFEST_PATH = BUNDLE_PATH.parent / "manifest.json"
OUTPUT_PATH = Path(
    os.environ.get(
        "CEL372_OUTPUT",
        "CEL-372-akida-hardware-run-evidence-2026-09-19.md",
    )
)


def _request(
    method: str,
    path: str,
    api_key: str,
    payload: dict[str, Any] | None = None,
    timeout: float = 120.0,
) -> tuple[int, Any]:
    url = f"{NEUROCHIP_URL}{path}"
    headers = {"X-API-Key": api_key, "Content-Type": "application/json"}
    data = None
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            body = response.read().decode("utf-8")
            return response.status, json.loads(body) if body else {}
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        try:
            parsed: Any = json.loads(body)
        except json.JSONDecodeError:
            parsed = {"raw": body}
        return exc.code, parsed


def _poll_job(api_key: str, job_id: str, deadline_s: float = 20 * 60) -> dict[str, Any]:
    deadline = time.monotonic() + deadline_s
    while True:
        status_code, job = _request("GET", f"/api/neurochip/akida/model-jobs/{job_id}", api_key)
        if status_code != 200:
            raise RuntimeError(f"job poll failed: HTTP {status_code} {job}")
        stage = job.get("stage")
        if stage in {"completed", "failed"}:
            return job
        if time.monotonic() >= deadline:
            raise TimeoutError(f"job {job_id} did not finish within {deadline_s}s")
        time.sleep(2)


def main() -> int:
    api_key = os.environ.get("NEUROCHIP_API_KEY", "").strip()
    if not api_key:
        print("NEUROCHIP_API_KEY is required", file=sys.stderr)
        return 2
    if not BUNDLE_PATH.is_file():
        print(f"bundle missing: {BUNDLE_PATH}", file=sys.stderr)
        return 2

    captured_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    bundle_bytes = BUNDLE_PATH.read_bytes()
    bundle_sha256 = hashlib.sha256(bundle_bytes).hexdigest()
    manifest: dict[str, Any] = {}
    if MANIFEST_PATH.is_file():
        manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))

    status_code, status = _request("GET", "/api/neurochip/akida/status", api_key)
    if status_code != 200:
        print(json.dumps({"error": "status_failed", "status_code": status_code, "body": status}))
        return 1

    submit_payload = {
        "filename": BUNDLE_PATH.name,
        "bundleBase64": base64.b64encode(bundle_bytes).decode("ascii"),
        "sha256": bundle_sha256,
        "requirePhysicalHardware": True,
    }
    status_code, submitted = _request(
        "POST", "/api/neurochip/akida/model-jobs", api_key, submit_payload
    )
    if status_code != 202:
        print(json.dumps({"error": "submit_failed", "status_code": status_code, "body": submitted}))
        return 1

    job = _poll_job(api_key, submitted["jobId"])
    if job.get("stage") != "completed":
        print(json.dumps({"error": "job_failed", "job": job}))
        return 1

    model_id = job["modelId"]
    inf1_code, inf1 = _request(
        "POST",
        f"/api/neurochip/akida/models/{model_id}/inference",
        api_key,
        {"sampleIndex": 0},
    )
    inf2_code, inf2 = _request(
        "POST",
        f"/api/neurochip/akida/models/{model_id}/inference",
        api_key,
        {"sampleIndex": 0},
    )

    evidence = {
        "capturedAtUtc": captured_at,
        "neurochipUrl": NEUROCHIP_URL,
        "bundlePath": str(BUNDLE_PATH),
        "bundleSha256": bundle_sha256,
        "manifest": manifest,
        "akidaStatus": status,
        "modelJob": job,
        "inferenceRun1": {"httpStatus": inf1_code, "body": inf1},
        "inferenceRun2": {"httpStatus": inf2_code, "body": inf2},
        "reproducible": (
            inf1_code == 200
            and inf2_code == 200
            and inf1.get("prediction") == inf2.get("prediction")
            and inf1.get("outputs") == inf2.get("outputs")
        ),
        "runtimeTarget": job.get("runtimeTarget"),
        "firstHardwareRunInRepo": job.get("runtimeTarget") == "hardware",
    }

    lines = [
        "# CEL-372 — Akida hardware export/deploy evidence",
        "",
        f"**Captured:** {captured_at}",
        "**Rig:** moosebun2 (`192.168.2.90`)",
        f"**API:** `{NEUROCHIP_URL}`",
        "",
        "## Verdict",
        "",
    ]
    runtime = job.get("runtimeTarget", "unknown")
    if runtime == "hardware" and job.get("hardwareVerified"):
        lines.append(
            "**First-ever `runtime_target=hardware` run recorded in this repo.** "
            "Deploy and inference completed on physical AKD1000 silicon."
        )
    else:
        lines.append(
            f"**Hardware run not verified.** `runtime_target={runtime}` "
            f"(hardwareVerified={job.get('hardwareVerified')})."
        )

    lines.extend(
        [
            "",
            "## Evidence fields (2026-07-30 demo-video gate)",
            "",
            "| Field | Value |",
            "|---|---|",
            f"| Physical device identity | `{job.get('deviceInfo') or status.get('device_info')}` |",
            f"| Bundle SHA-256 (zip) | `{bundle_sha256}` |",
            f"| Manifest model.fbz SHA-256 | `{manifest.get('files', {}).get('model.fbz', 'n/a')}` |",
            f"| Device→NP mapping | `{job.get('message', 'see model job message/metrics')}` |",
            f"| Reproducible inference (sample 0 ×2) | `{evidence['reproducible']}` |",
            f"| Post-quantization accuracy | `{job.get('metrics', {}).get('akida_accuracy', 'n/a')}` |",
            f"| Latency (ms) | `{job.get('metrics', {}).get('latency_ms', inf1.get('telemetry', {}).get('latency_ms', 'n/a'))}` |",
            f"| Power (mW) | `{job.get('metrics', {}).get('power_mw', inf1.get('telemetry', {}).get('power_mw', 'n/a'))}` |",
            "| Telemetry source | `Akida SDK model.statistics via neurochip service` |",
            f"| **`runtime_target`** | **`{runtime}`** |",
            f"| **hardwareVerified** | **{job.get('hardwareVerified')}** |",
            "",
            "## Akida status (pre-deploy)",
            "",
            "```json",
            json.dumps(status, indent=2),
            "```",
            "",
            "## Model job (completed)",
            "",
            "```json",
            json.dumps(job, indent=2),
            "```",
            "",
            "## Inference sample 0 — run 1",
            "",
            "```json",
            json.dumps(inf1, indent=2),
            "```",
            "",
            "## Inference sample 0 — run 2",
            "",
            "```json",
            json.dumps(inf2, indent=2),
            "```",
            "",
            "## Raw evidence JSON",
            "",
            "```json",
            json.dumps(evidence, indent=2),
            "```",
            "",
        ]
    )

    OUTPUT_PATH.write_text("\n".join(lines), encoding="utf-8")
    print(json.dumps({"ok": True, "output": str(OUTPUT_PATH), "runtimeTarget": runtime}))
    return 0 if runtime == "hardware" else 1


if __name__ == "__main__":
    raise SystemExit(main())
