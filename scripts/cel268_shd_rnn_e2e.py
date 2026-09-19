#!/usr/bin/env python3
"""CEL-268: Live SHD recurrent RSNN training on dev backend.

Generates and runs the Studio notebook for the Cramer et al. 2020 topology
(700→RSynaptic(128)→Synaptic(20)) with tonic_shd loaders, streams training
progress, and writes a JSON summary with final test accuracy.

Usage:
    python3 scripts/cel268_shd_rnn_e2e.py --api-url http://192.168.2.90:9000 --epochs 50
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

ADMIN_HEADER = "X-NMTK-Admin-Token"

API_PREFIX = "/api/neurocnl"

CNL_SPEC = "\n".join(
    [
        "Define a network named shd_rsnn with timestep 0.001.",
        "Define an input port named input with shape (700,).",
        "Define a linear transformation named w_in_hidden with weight matrix shape (128, 700).",
        "Define a RSynaptic neuron named hidden with neuron count 128, "
        "synaptic decay 0.9, membrane decay 0.8, and firing threshold 1.0.",
        "Define a linear transformation named w_hidden_out with weight matrix shape (20, 128).",
        "Define a Synaptic neuron named output_layer with neuron count 20, "
        "synaptic decay 0.9, membrane decay 0.8, and firing threshold 1.0.",
        "Define an output port named output with shape (20,).",
        "input connects to w_in_hidden.",
        "w_in_hidden connects to hidden.",
        "hidden connects to w_hidden_out.",
        "w_hidden_out connects to output_layer.",
        "output_layer connects to output.",
    ]
)

SHD_LOADER = {
    "format": "tonic_shd",
    "batch_size": 32,
    "time_window_ms": 4,
}

PIPELINE_PHASES: dict[str, Any] = {
    "train": {
        "nodes": [
            {
                "id": "train_loader",
                "type": "dataLoader",
                "parameters": {**SHD_LOADER, "shuffle": True},
            },
            {"id": "state_reset", "type": "stateReset", "parameters": {}},
            {"id": "forward", "type": "forwardPass", "parameters": {}},
            {"id": "time_loop", "type": "timeLoop", "parameters": {"num_steps": 25}},
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
                "parameters": {**SHD_LOADER, "shuffle": False},
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
                "parameters": {**SHD_LOADER, "shuffle": False, "load_best_checkpoint": True},
            },
            {"id": "eval_reset", "type": "stateReset", "parameters": {}},
            {"id": "eval_forward", "type": "forwardPass", "parameters": {}},
            {"id": "accuracy", "type": "accuracyMetric", "parameters": {}},
        ],
        "edges": [],
    },
}

CRAMER_RSNN_BASELINE = (0.80, 0.83)


def _client_headers() -> dict[str, str]:
    token = os.environ.get("NMTK_ADMIN_TOKEN", "").strip()
    return {ADMIN_HEADER: token} if token else {}


def _post(client: httpx.Client, base_url: str, path: str, payload: dict[str, Any]) -> dict[str, Any]:
    resp = client.post(f"{base_url}{API_PREFIX}{path}", json=payload, timeout=120.0)
    if resp.status_code >= 400:
        raise RuntimeError(f"POST {path} failed ({resp.status_code}): {resp.text[:2000]}")
    return resp.json()


def _stream_events(client: httpx.Client, base_url: str, job_id: str) -> list[dict[str, Any]]:
    url = f"{base_url}{API_PREFIX}/training/jobs/{job_id}/events"
    events: list[dict[str, Any]] = []
    with client.stream("GET", url, timeout=None) as response:
        response.raise_for_status()
        for line in response.iter_lines():
            if not line.startswith("data: "):
                continue
            event = json.loads(line[len("data: ") :])
            events.append(event)
            etype = event.get("type")
            if etype == "epoch":
                acc = event.get("accuracy")
                acc_s = f", acc={acc:.4f}" if acc is not None else ""
                print(
                    f"  epoch {event.get('epoch')}/{event.get('total_epochs')}: "
                    f"loss={event.get('loss'):.4f}{acc_s}",
                    flush=True,
                )
            elif etype == "failed":
                print(f"  FAILED: {event.get('error', 'unknown')}", flush=True)
                return events
            elif etype == "done":
                print("  done.", flush=True)
                return events
    return events


def run_e2e(base_url: str, epochs: int, output: Path | None) -> dict[str, Any]:
    base_url = base_url.rstrip("/")
    pipeline_config = {
        "framework": "snntorch_sim",
        "epochs": epochs,
        "learning_rate": 0.001,
        "optimizer": "Adam",
        "batch_size": 32,
        "dataset": "SHD",
        "run_evaluation": True,
    }
    started = time.time()
    summary: dict[str, Any] = {
        "task": "CEL-268",
        "api_url": base_url,
        "epochs": epochs,
        "baseline_range": list(CRAMER_RSNN_BASELINE),
        "started_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(started)),
    }

    with httpx.Client(headers=_client_headers()) as client:
        print("Generating notebook...", flush=True)
        gen = _post(
            client,
            base_url,
            "/notebook/generate-v2",
            {
                "spec": CNL_SPEC,
                "pipeline_config": pipeline_config,
                "pipeline_phases": PIPELINE_PHASES,
                "workspace_path": "cel268-shd-rsnn",
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
        events = _stream_events(client, base_url, job_id)

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
        lo, hi = CRAMER_RSNN_BASELINE
        summary["meets_baseline"] = lo <= final_test_acc <= hi
        summary["baseline_gap_pct"] = round((final_test_acc - lo) * 100, 2)
    summary["elapsed_s"] = round(time.time() - started, 1)
    summary["status"] = "failed" if failed else "ok"

    if output is not None:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(summary, indent=2))
        print(f"Wrote summary to {output}", flush=True)
    return summary


def main() -> int:
    parser = argparse.ArgumentParser(description="CEL-268 SHD RSNN live E2E training")
    parser.add_argument(
        "--api-url",
        default="http://192.168.2.90:9000",
        help="Suite API base URL (default: dev backend)",
    )
    parser.add_argument("--epochs", type=int, default=50, help="Training epochs (default: 50)")
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
        out = scratch / "cel268_shd_rnn_summary.json"

    try:
        summary = run_e2e(args.api_url, args.epochs, out)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    acc = summary.get("final_test_accuracy") or summary.get("final_val_accuracy")
    print(json.dumps({"status": summary["status"], "test_accuracy": acc, "summary_path": str(out)}))
    return 1 if summary["status"] != "ok" else 0


if __name__ == "__main__":
    raise SystemExit(main())
