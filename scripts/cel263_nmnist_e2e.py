#!/usr/bin/env python3
"""CEL-263: Live N-MNIST CNN training on dev backend (Orchard et al. 2015).

Generates and runs the Studio notebook for the paper/02_cnn spiking CNN topology
(2x34x34 → Conv→IF→…→10) with tonic_nmnist loaders, streams training progress,
and writes a JSON summary with final test accuracy.

Usage:
    python3 scripts/cel263_nmnist_e2e.py --api-url http://192.168.2.90:9000 --epochs 20
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path
from typing import Any

import httpx


def _auth_headers() -> dict[str, str]:
    token = os.environ.get("NMTK_ADMIN_TOKEN", "").strip()
    return {"X-NMTK-Admin-Token": token} if token else {}

API_PREFIX = "/api/neurocnl"

# paper/02_cnn/gen_snn.ipynb — N-MNIST spiking CNN (97.97% eval with pretrained weights)
CNL_SPEC = "\n".join(
    [
        "Define a network named nmnist_cnn with timestep 0.001.",
        "Define an input port named input with shape (2, 34, 34).",
        "Define a 2D convolution layer named conv1 with weight kernel shape (16, 2, 5, 5), "
        "bias vector shape (16,), stride (2, 2), padding (1, 1), dilation (1, 1), groups 1, "
        "and input height and width (34, 34).",
        "Define an IF neuron named if1 with resistance shape (16,) and firing threshold shape (16,).",
        "Define a 2D convolution layer named conv2 with weight kernel shape (16, 16, 3, 3), "
        "bias vector shape (16,), stride (1, 1), padding (1, 1), dilation (1, 1), groups 1, "
        "and input height and width (16, 16).",
        "Define an IF neuron named if2 with resistance shape (16,) and firing threshold shape (16,).",
        "Define a 2D sum pooling layer named pool1 with kernel size (2, 2), stride (2, 2), "
        "and padding (0, 0).",
        "Define a 2D convolution layer named conv3 with weight kernel shape (8, 16, 3, 3), "
        "bias vector shape (8,), stride (1, 1), padding (1, 1), dilation (1, 1), groups 1, "
        "and input height and width (8, 8).",
        "Define an IF neuron named if3 with resistance shape (8,) and firing threshold shape (8,).",
        "Define a 2D sum pooling layer named pool2 with kernel size (2, 2), stride (2, 2), "
        "and padding (0, 0).",
        "Define a flatten layer named flat with start dimension 0 and end dimension -1.",
        "Define an affine transformation named fc1 with weight matrix shape (256, 128) "
        "and bias vector shape (256,).",
        "Define an IF neuron named if4 with resistance shape (256,) and firing threshold shape (256,).",
        "Define an affine transformation named fc2 with weight matrix shape (10, 256) "
        "and bias vector shape (10,).",
        "Define an IF neuron named if5 with resistance shape (10,) and firing threshold shape (10,).",
        "Define an output port named output with shape (10,).",
        "input connects to conv1.",
        "conv1 connects to if1.",
        "if1 connects to conv2.",
        "conv2 connects to if2.",
        "if2 connects to pool1.",
        "pool1 connects to conv3.",
        "conv3 connects to if3.",
        "if3 connects to pool2.",
        "pool2 connects to flat.",
        "flat connects to fc1.",
        "fc1 connects to if4.",
        "if4 connects to fc2.",
        "fc2 connects to if5.",
        "if5 connects to output.",
    ]
)

NMNIST_LOADER = {
    "format": "tonic_nmnist",
    "batch_size": 64,
    "time_window_ms": 1,
}

PIPELINE_PHASES: dict[str, Any] = {
    "train": {
        "nodes": [
            {
                "id": "train_loader",
                "type": "dataLoader",
                "parameters": {**NMNIST_LOADER, "shuffle": True},
            },
            {"id": "state_reset", "type": "stateReset", "parameters": {}},
            {"id": "forward", "type": "forwardPass", "parameters": {}},
            {"id": "loss", "type": "ceCountLoss", "parameters": {}},
            {
                "id": "backward",
                "type": "surrogateBackward",
                "parameters": {"function": "fast_sigmoid", "slope": 25},
            },
            {"id": "optim", "type": "adamOptimiser", "parameters": {"lr": 0.001}},
            {
                "id": "val_loader",
                "type": "testLoader",
                "parameters": {**NMNIST_LOADER, "shuffle": False},
            },
            {
                "id": "validation",
                "type": "validationLoop",
                "parameters": {
                    "every_n_epochs": 1,
                    "save_best_checkpoint": True,
                    "checkpoint_metric": "val_accuracy",
                    "checkpoint_mode": "max",
                },
            },
        ],
        "edges": [
            {
                "id": "val_data",
                "source_node_id": "val_loader",
                "source_port": "data",
                "target_node_id": "validation",
                "target_port": "val_data",
            }
        ],
    },
    "eval": {
        "nodes": [
            {
                "id": "test_loader",
                "type": "testLoader",
                "parameters": {
                    **NMNIST_LOADER,
                    "shuffle": False,
                    "load_best_checkpoint": True,
                },
            },
            {"id": "eval_reset", "type": "stateReset", "parameters": {}},
            {"id": "eval_forward", "type": "forwardPass", "parameters": {}},
            {"id": "accuracy", "type": "accuracyMetric", "parameters": {}},
        ],
        "edges": [],
    },
}

# Orchard et al. 2015 / paper/02_cnn reference: ~98-99% with spiking CNNs
ORCHARD_BASELINE = (0.98, 0.99)


def _post(client: httpx.Client, base_url: str, path: str, payload: dict[str, Any]) -> dict[str, Any]:
    resp = client.post(
        f"{base_url}{API_PREFIX}{path}",
        json=payload,
        headers=_auth_headers(),
        timeout=120.0,
    )
    if resp.status_code >= 400:
        raise RuntimeError(f"POST {path} failed ({resp.status_code}): {resp.text[:2000]}")
    return resp.json()


def _get_job(client: httpx.Client, base_url: str, job_id: str) -> dict[str, Any]:
    resp = client.get(
        f"{base_url}{API_PREFIX}/training/jobs/{job_id}",
        headers=_auth_headers(),
        timeout=30.0,
    )
    if resp.status_code >= 400:
        raise RuntimeError(f"GET job {job_id} failed ({resp.status_code}): {resp.text[:500]}")
    return resp.json()


def _print_epoch(event: dict[str, Any]) -> None:
    if event.get("type") != "epoch":
        return
    acc = event.get("accuracy")
    acc_s = f", acc={acc:.4f}" if acc is not None else ""
    print(
        f"  epoch {event.get('epoch')}/{event.get('total_epochs')}: "
        f"loss={event.get('loss'):.4f}{acc_s}",
        flush=True,
    )


def _stream_events(client: httpx.Client, base_url: str, job_id: str) -> list[dict[str, Any]]:
    url = f"{base_url}{API_PREFIX}/training/jobs/{job_id}/events"
    events: list[dict[str, Any]] = []
    try:
        with client.stream("GET", url, headers=_auth_headers(), timeout=None) as response:
            response.raise_for_status()
            for line in response.iter_lines():
                if not line.startswith("data: "):
                    continue
                event = json.loads(line[len("data: ") :])
                events.append(event)
                etype = event.get("type")
                if etype == "epoch":
                    _print_epoch(event)
                elif etype == "failed":
                    print(f"  FAILED: {event.get('error', 'unknown')}", flush=True)
                    return events
                elif etype == "done":
                    print("  done.", flush=True)
                    return events
    except httpx.RemoteProtocolError as exc:
        print(f"  SSE disconnected ({exc}); polling job status...", flush=True)
    return _poll_until_done(client, base_url, job_id, events)


def _poll_until_done(
    client: httpx.Client, base_url: str, job_id: str, events: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    """ponytail: 15s poll until terminal job state; upgrade path: resume SSE from last seq."""
    seen_epochs = {e.get("epoch") for e in events if e.get("type") == "epoch"}
    while True:
        job = _get_job(client, base_url, job_id)
        status = job.get("status")
        result = job.get("result") or {}
        meta = result if isinstance(result, dict) else {}
        epoch = meta.get("epoch")
        if epoch is not None and epoch not in seen_epochs:
            evt = {
                "type": "epoch",
                "epoch": epoch,
                "total_epochs": meta.get("total_epochs"),
                "loss": meta.get("loss"),
                "accuracy": meta.get("accuracy"),
                "phase": meta.get("phase"),
            }
            events.append(evt)
            seen_epochs.add(epoch)
            _print_epoch(evt)
        if status in {"complete", "failed"}:
            if status == "failed":
                events.append({"type": "failed", "error": job.get("error")})
            else:
                result = job.get("result") or {}
                acc = result.get("test_accuracy") or result.get("accuracy") if isinstance(result, dict) else None
                events.append({"type": "done", "accuracy": acc})
            print(f"  job {status}.", flush=True)
            return events
        time.sleep(15)


def poll_job(
    base_url: str, job_id: str, epochs: int, output: Path | None
) -> dict[str, Any]:
    """Poll an existing job to completion (no generate/run)."""
    started = time.time()
    summary: dict[str, Any] = {
        "task": "CEL-263",
        "api_url": base_url.rstrip("/"),
        "epochs": epochs,
        "job_id": job_id,
        "baseline_range": list(ORCHARD_BASELINE),
        "started_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(started)),
        "poll_only": True,
    }
    with httpx.Client() as client:
        events = _poll_until_done(client, base_url.rstrip("/"), job_id, [])
    return _finalize_summary(summary, events, started, output)


def _finalize_summary(
    summary: dict[str, Any], events: list[dict[str, Any]], started: float, output: Path | None
) -> dict[str, Any]:
    train_epochs = [e for e in events if e.get("type") == "epoch" and e.get("phase") == "train"]
    val_epochs = [e for e in events if e.get("type") == "epoch" and e.get("phase") != "train"]
    failed = next((e for e in events if e.get("type") == "failed"), None)

    final_test_acc = None
    for e in reversed(events):
        if e.get("type") == "done" and e.get("accuracy") is not None:
            final_test_acc = e["accuracy"]
            break
        if e.get("phase") == "eval" and e.get("accuracy") is not None:
            final_test_acc = e["accuracy"]
            break
    if final_test_acc is None and val_epochs:
        final_test_acc = val_epochs[-1].get("accuracy")

    summary["events_count"] = len(events)
    summary["train_epoch_count"] = len(train_epochs)
    summary["final_val_accuracy"] = val_epochs[-1].get("accuracy") if val_epochs else None
    summary["final_test_accuracy"] = final_test_acc
    summary["failed"] = failed is not None
    if failed:
        summary["error"] = failed.get("error")
    if final_test_acc is not None:
        lo, hi = ORCHARD_BASELINE
        summary["meets_baseline"] = lo <= final_test_acc <= hi
        summary["baseline_gap_pct"] = round((final_test_acc - lo) * 100, 2)
    summary["elapsed_s"] = round(time.time() - started, 1)
    summary["status"] = "failed" if failed else "ok"

    if output is not None:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(summary, indent=2))
        print(f"Wrote summary to {output}", flush=True)
    return summary


def run_e2e(base_url: str, epochs: int, output: Path | None) -> dict[str, Any]:
    base_url = base_url.rstrip("/")
    pipeline_config = {
        "framework": "snntorch_sim",
        "epochs": epochs,
        "learning_rate": 0.001,
        "optimizer": "Adam",
        "batch_size": 64,
        "dataset": "NMNIST",
        "run_evaluation": True,
    }
    started = time.time()
    summary: dict[str, Any] = {
        "task": "CEL-263",
        "api_url": base_url,
        "epochs": epochs,
        "baseline_range": list(ORCHARD_BASELINE),
        "started_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(started)),
    }

    with httpx.Client() as client:
        print("Generating notebook...", flush=True)
        gen = _post(
            client,
            base_url,
            "/notebook/generate-v2",
            {
                "spec": CNL_SPEC,
                "pipeline_config": pipeline_config,
                "pipeline_phases": PIPELINE_PHASES,
                "workspace_path": "cel263-nmnist-cnn",
            },
        )
        notebooks = gen.get("notebooks") or []
        if not notebooks:
            raise RuntimeError("generate-v2 returned no notebooks")
        nb = notebooks[0]
        summary["generate"] = {
            "notebook": nb.get("filename"),
            "target": nb.get("target"),
            "support_level": nb.get("support_level"),
            "diagnostics": nb.get("diagnostics") or [],
        }
        notebook_path = f"{gen['workspace_folder']}/{nb['filename']}"
        summary["notebook_path"] = notebook_path

        print(f"Running {notebook_path} for {epochs} epochs...", flush=True)
        run_resp = _post(
            client,
            base_url,
            "/notebook/run",
            {
                "notebook_path": notebook_path,
                "platform": "snntorch_sim",
                "kernel_name": "python3",
            },
        )
        job_id = run_resp["job_id"]
        summary["job_id"] = job_id
        print(f"  job_id={job_id}", flush=True)
        events = _poll_until_done(client, base_url, job_id, [])

    return _finalize_summary(summary, events, started, output)


def main() -> int:
    parser = argparse.ArgumentParser(description="CEL-263 N-MNIST CNN live E2E training")
    parser.add_argument(
        "--api-url",
        default="http://192.168.2.90:9000",
        help="Suite API base URL (default: dev backend)",
    )
    parser.add_argument("--epochs", type=int, default=20, help="Training epochs (default: 20)")
    parser.add_argument(
        "--poll-only",
        metavar="JOB_ID",
        help="Skip generate/run; poll an existing training job until terminal state",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=None,
        help="JSON summary output path (default: PAPERCLIP_SCRATCH_DIR or /tmp)",
    )
    args = parser.parse_args()
    out = args.output
    if out is None:
        scratch = Path(__import__("os").environ.get("PAPERCLIP_SCRATCH_DIR", "/tmp"))
        out = scratch / "cel263_nmnist_summary.json"

    try:
        if args.poll_only:
            summary = poll_job(args.api_url, args.poll_only, args.epochs, out)
        else:
            summary = run_e2e(args.api_url, args.epochs, out)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    acc = summary.get("final_test_accuracy") or summary.get("final_val_accuracy")
    print(json.dumps({"status": summary["status"], "test_accuracy": acc, "summary_path": str(out)}))
    return 1 if summary["status"] != "ok" else 0


if __name__ == "__main__":
    raise SystemExit(main())
