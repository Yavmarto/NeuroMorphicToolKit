"""Tests for POST /api/notebook/run."""

import asyncio
import json
from unittest.mock import AsyncMock, patch

from fastapi.testclient import TestClient

from backend.app.main import app

client = TestClient(app)


_FAKE_JOB_ID = "12345678-1234-5678-1234-567812345678"


def test_run_notebook_returns_job_id(tmp_path):
    nb_path = tmp_path / "test.ipynb"
    nb_path.write_text(
        json.dumps(
            {
                "nbformat": 4,
                "nbformat_minor": 5,
                "cells": [],
                "metadata": {},
            }
        )
    )

    with (
        patch(
            "backend.app.routers.kernel_runner.job_store.create",
            new=AsyncMock(return_value=_FAKE_JOB_ID),
        ),
        patch("backend.app.routers.kernel_runner._execute_notebook", new=AsyncMock()),
    ):
        resp = client.post(
            "/api/notebook/run",
            json={
                "notebook_path": str(nb_path),
                "platform": "snntorch_sim",
            },
        )

    assert resp.status_code == 202
    data = resp.json()
    assert "job_id" in data
    assert len(data["job_id"]) == 36  # UUID


def test_run_notebook_resolves_relative_workspace_path(tmp_path):
    ws = tmp_path / "cnn-eval" / "notebooks"
    ws.mkdir(parents=True)
    nb = ws / "pipeline_snntorch_sim.ipynb"
    nb.write_text(
        json.dumps({"nbformat": 4, "nbformat_minor": 5, "cells": [], "metadata": {}}),
        encoding="utf-8",
    )

    with (
        patch("backend.app.services.notebook_paths.NOTEBOOK_DIR", tmp_path),
        patch(
            "backend.app.routers.kernel_runner.job_store.create",
            new=AsyncMock(return_value=_FAKE_JOB_ID),
        ),
        patch("backend.app.routers.kernel_runner._execute_notebook", new=AsyncMock()),
    ):
        resp = client.post(
            "/api/notebook/run",
            json={
                "notebook_path": "cnn-eval/notebooks/pipeline_snntorch_sim.ipynb",
                "platform": "snntorch_sim",
            },
        )

    assert resp.status_code == 202


def test_run_notebook_uses_notebook_kernelspec_when_kernel_omitted(tmp_path):
    ws = tmp_path / "cnn-eval" / "notebooks"
    ws.mkdir(parents=True)
    nb = ws / "pipeline_snntorch_sim.ipynb"
    nb.write_text(
        json.dumps(
            {
                "nbformat": 4,
                "nbformat_minor": 5,
                "cells": [],
                "metadata": {"kernelspec": {"name": "nmtk-snntorch"}},
            }
        ),
        encoding="utf-8",
    )

    execute = AsyncMock()
    with (
        patch("backend.app.services.notebook_paths.NOTEBOOK_DIR", tmp_path),
        patch(
            "backend.app.routers.kernel_runner.job_store.create",
            new=AsyncMock(return_value=_FAKE_JOB_ID),
        ),
        patch("backend.app.routers.kernel_runner._execute_notebook", new=execute),
    ):
        resp = client.post(
            "/api/notebook/run",
            json={
                "notebook_path": "cnn-eval/notebooks/pipeline_snntorch_sim.ipynb",
                "platform": "snntorch_sim",
            },
        )

    assert resp.status_code == 202
    assert execute.await_args.args[3] == "nmtk-snntorch"


def test_run_notebook_uses_notebook_kernelspec_when_kernel_empty(tmp_path):
    nb = tmp_path / "pipeline_snntorch_sim.ipynb"
    nb.write_text(
        json.dumps(
            {
                "nbformat": 4,
                "nbformat_minor": 5,
                "cells": [],
                "metadata": {"kernelspec": {"name": "nmtk-snntorch"}},
            }
        ),
        encoding="utf-8",
    )

    execute = AsyncMock()
    with (
        patch(
            "backend.app.routers.kernel_runner.job_store.create",
            new=AsyncMock(return_value=_FAKE_JOB_ID),
        ),
        patch("backend.app.routers.kernel_runner._execute_notebook", new=execute),
    ):
        resp = client.post(
            "/api/notebook/run",
            json={
                "notebook_path": str(nb),
                "platform": "snntorch_sim",
                "kernel_name": "",
            },
        )

    assert resp.status_code == 202
    assert execute.await_args.args[3] == "nmtk-snntorch"


def test_run_notebook_404_for_missing_path():
    resp = client.post(
        "/api/notebook/run",
        json={
            "notebook_path": "/nonexistent/path/nb.ipynb",
            "platform": "snntorch_sim",
        },
    )
    assert resp.status_code == 404


def test_execute_notebook_uses_jupyter_worker_when_configured(tmp_path):
    from backend.app.routers import kernel_runner

    nb_path = tmp_path / "workspace" / "notebooks" / "pipeline_snntorch_sim.ipynb"
    nb_path.parent.mkdir(parents=True)
    nb_path.write_text(
        json.dumps({"nbformat": 4, "nbformat_minor": 5, "cells": [], "metadata": {}}),
        encoding="utf-8",
    )

    class _Response:
        def __init__(self, payload: dict):
            self._payload = payload
            self.status_code = 200
            self.text = json.dumps(payload)

        def json(self) -> dict:
            return self._payload

        def raise_for_status(self) -> None:
            return None

    class _AsyncClient:
        def __init__(self, *_, **__):
            self.get_count = 0

        async def __aenter__(self):
            return self

        async def __aexit__(self, *_):
            return None

        async def post(self, url: str, json: dict):
            assert url == "http://jupyter:8008/nmtk-envs/api/executions"
            assert json == {
                "notebookPath": "workspace/notebooks/pipeline_snntorch_sim.ipynb",
                "kernelName": "nmtk-snntorch",
            }
            return _Response({"jobId": "worker-job"})

        async def get(self, url: str):
            if url == "http://jupyter:8008/api/sessions":
                return _Response([])
            assert url == "http://jupyter:8008/nmtk-envs/api/jobs/worker-job"
            self.get_count += 1
            if self.get_count == 1:
                return _Response(
                    {
                        "state": "working",
                        "output": ['{"__nmtk_progress__": true, "epoch": 1}'],
                    }
                )
            return _Response(
                {
                    "state": "ready",
                    "output": [
                        '{"__nmtk_progress__": true, "epoch": 1}',
                        "finished",
                    ],
                    "result": {"notebookPath": "workspace/notebooks/pipeline_snntorch_sim.ipynb"},
                }
            )

    published: list[dict] = []
    with (
        patch(
            "backend.app.routers.kernel_runner.JUPYTER_WORKER_URL",
            "http://jupyter:8008",
        ),
        patch("backend.app.routers.kernel_runner.NOTEBOOK_DIR", tmp_path),
        patch("backend.app.routers.kernel_runner.httpx.AsyncClient", _AsyncClient),
        patch(
            "backend.app.routers.kernel_runner.job_store.set_running", new=AsyncMock()
        ) as running,
        patch(
            "backend.app.routers.kernel_runner.job_store.set_complete", new=AsyncMock()
        ) as complete,
        patch("backend.app.routers.kernel_runner.job_store.set_failed", new=AsyncMock()) as failed,
        patch(
            "backend.app.routers.kernel_runner.progress_bus.publisher_for",
            return_value=published.append,
        ),
    ):
        asyncio.run(
            kernel_runner._execute_notebook(
                "job-1",
                nb_path,
                "snntorch_sim",
                "nmtk-snntorch",
                notebook_path="workspace/notebooks/pipeline_snntorch_sim.ipynb",
            )
        )

    running.assert_awaited_once_with("job-1")
    complete.assert_awaited_once()
    failed.assert_not_awaited()
    assert published[0]["type"] == "epoch"
    assert published[-1]["status"] == "completed"


def test_execute_notebook_via_worker_stops_conflicting_manual_session(tmp_path):
    """A manually-opened JupyterLab kernel against the same notebook must be
    stopped before the Play-triggered run submits its own execution — left
    running, the two kernels resource-contend and the Play run silently
    stalls until the 30-minute timeout (the regression this test guards)."""
    from backend.app.routers import kernel_runner

    nb_path = tmp_path / "workspace" / "notebooks" / "pipeline_snntorch_sim.ipynb"
    nb_path.parent.mkdir(parents=True)
    nb_path.write_text(
        json.dumps({"nbformat": 4, "nbformat_minor": 5, "cells": [], "metadata": {}}),
        encoding="utf-8",
    )
    worker_path = "workspace/notebooks/pipeline_snntorch_sim.ipynb"

    class _Response:
        def __init__(self, payload):
            self._payload = payload

        def json(self):
            return self._payload

        def raise_for_status(self):
            return None

    calls: list[tuple[str, str]] = []

    class _AsyncClient:
        def __init__(self, *_, **__):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, *_):
            return None

        async def get(self, url: str):
            calls.append(("get", url))
            if url == "http://jupyter:8008/api/sessions":
                return _Response([{"id": "stray-session", "path": worker_path}])
            return _Response(
                {
                    "state": "ready",
                    "output": [],
                    "result": {"notebookPath": worker_path},
                }
            )

        async def delete(self, url: str):
            calls.append(("delete", url))
            return _Response({})

        async def post(self, url: str, json: dict):
            calls.append(("post", url))
            return _Response({"jobId": "worker-job"})

    with (
        patch(
            "backend.app.routers.kernel_runner.JUPYTER_WORKER_URL",
            "http://jupyter:8008",
        ),
        patch("backend.app.routers.kernel_runner.NOTEBOOK_DIR", tmp_path),
        patch("backend.app.routers.kernel_runner.httpx.AsyncClient", _AsyncClient),
        patch("backend.app.routers.kernel_runner.job_store.set_running", new=AsyncMock()),
        patch(
            "backend.app.routers.kernel_runner.job_store.set_complete",
            new=AsyncMock(),
        ),
        patch("backend.app.routers.kernel_runner.job_store.set_failed", new=AsyncMock()),
        patch(
            "backend.app.routers.kernel_runner.progress_bus.publisher_for",
            return_value=lambda event: None,
        ),
    ):
        asyncio.run(
            kernel_runner._execute_notebook(
                "job-1",
                nb_path,
                "snntorch_sim",
                "nmtk-snntorch",
                notebook_path=worker_path,
            )
        )

    # The stray session must be listed and stopped BEFORE the new execution
    # is submitted — not after, or the two kernels would still overlap.
    kinds = [kind for kind, _ in calls]
    assert kinds.index("get") < kinds.index("delete") < kinds.index("post")
    assert calls[kinds.index("delete")][1] == ("http://jupyter:8008/api/sessions/stray-session")


def test_maybe_publish_ignores_non_progress_lines():
    from backend.app.routers.kernel_runner import _maybe_publish

    published: list[dict] = []
    _maybe_publish('{"some": "data"}', "snntorch_sim", published.append)
    assert published == []


def test_maybe_publish_emits_progress_events():
    from backend.app.routers.kernel_runner import _maybe_publish

    published: list[dict] = []
    line = json.dumps(
        {
            "__nmtk_progress__": True,
            "epoch": 3,
            "total_epochs": 10,
            "loss": 0.5,
            "accuracy": 0.8,
            "layer_spike_rates": {"layer_0": 0.12},
        }
    )
    _maybe_publish(line, "snntorch_sim", published.append)

    assert len(published) == 1
    event = published[0]
    assert event["type"] == "epoch"
    assert event["epoch"] == 3
    assert event["platform"] == "snntorch_sim"
    assert event["accuracy"] == 0.8
    assert event["layer_spike_rates"] == {"layer_0": 0.12}
    assert "__nmtk_progress__" not in event


def test_maybe_publish_ignores_empty_lines():
    from backend.app.routers.kernel_runner import _maybe_publish

    published: list[dict] = []
    _maybe_publish("", "snntorch_sim", published.append)
    assert published == []


def test_maybe_publish_ignores_non_json():
    from backend.app.routers.kernel_runner import _maybe_publish

    published: list[dict] = []
    _maybe_publish("not valid json at all", "snntorch_sim", published.append)
    assert published == []


def test_maybe_capture_activity_extracts_epoch_and_b64_from_marker_line():
    from backend.app.routers.kernel_runner import _maybe_capture_activity

    line = json.dumps({"__nmtk_activity__": True, "epoch": 3, "activity_npy_b64": "Zm9v"})
    assert _maybe_capture_activity(line) == (3, "Zm9v")


def test_maybe_capture_activity_ignores_progress_lines():
    from backend.app.routers.kernel_runner import _maybe_capture_activity

    line = json.dumps({"__nmtk_progress__": True, "epoch": 1})
    assert _maybe_capture_activity(line) is None


def test_maybe_capture_activity_ignores_empty_or_non_json_lines():
    from backend.app.routers.kernel_runner import _maybe_capture_activity

    assert _maybe_capture_activity("") is None
    assert _maybe_capture_activity("not json") is None
    assert _maybe_capture_activity(json.dumps({"__nmtk_activity__": True})) is None


def test_maybe_capture_activity_ignores_missing_or_invalid_epoch():
    from backend.app.routers.kernel_runner import _maybe_capture_activity

    line = json.dumps({"__nmtk_activity__": True, "activity_npy_b64": "Zm9v"})
    assert _maybe_capture_activity(line) is None
    line = json.dumps(
        {"__nmtk_activity__": True, "epoch": "not-an-int", "activity_npy_b64": "Zm9v"}
    )
    assert _maybe_capture_activity(line) is None


def test_execute_notebook_via_worker_threads_activity_into_job_result(tmp_path):
    """Every `__nmtk_activity__` marker line the generated notebook prints
    (one per captured epoch) must end up keyed by epoch in the completed
    job's `result["metadata"]["activity_npy_b64_by_epoch"]` — this is what
    `GET /training/jobs/{job_id}/activity.npy` reads to serve the Results
    step's Network Playback Grid/Raster views. Before per-epoch capture
    existed, nothing ever wrote activity data anywhere, so that endpoint
    always 404'd.
    """
    from backend.app.routers import kernel_runner

    nb_path = tmp_path / "workspace" / "notebooks" / "pipeline_snntorch_sim.ipynb"
    nb_path.parent.mkdir(parents=True)
    nb_path.write_text(
        json.dumps({"nbformat": 4, "nbformat_minor": 5, "cells": [], "metadata": {}}),
        encoding="utf-8",
    )

    class _Response:
        def __init__(self, payload):
            self._payload = payload
            self.status_code = 200
            self.text = json.dumps(payload)

        def json(self):
            return self._payload

        def raise_for_status(self):
            return None

    class _AsyncClient:
        def __init__(self, *_, **__):
            self.get_count = 0

        async def __aenter__(self):
            return self

        async def __aexit__(self, *_):
            return None

        async def post(self, url, json):
            return _Response({"jobId": "worker-job"})

        async def get(self, url):
            if url == "http://jupyter:8008/api/sessions":
                return _Response([])
            self.get_count += 1
            if self.get_count == 1:
                return _Response(
                    {
                        "state": "working",
                        "output": [
                            '{"__nmtk_progress__": true, "epoch": 1, "phase": "train"}',
                            '{"__nmtk_activity__": true, "epoch": 1, '
                            '"activity_npy_b64": "ZmFrZXppcA=="}',
                        ],
                    }
                )
            return _Response(
                {
                    "state": "ready",
                    "output": [
                        '{"__nmtk_progress__": true, "epoch": 1, "phase": "train"}',
                        '{"__nmtk_activity__": true, "epoch": 1, '
                        '"activity_npy_b64": "ZmFrZXppcA=="}',
                        '{"__nmtk_progress__": true, "epoch": 5, "phase": "eval"}',
                        '{"__nmtk_activity__": true, "epoch": 5, "activity_npy_b64": "ZmluYWw="}',
                        "finished",
                    ],
                    "result": {"notebookPath": "workspace/notebooks/pipeline_snntorch_sim.ipynb"},
                }
            )

    with (
        patch(
            "backend.app.routers.kernel_runner.JUPYTER_WORKER_URL",
            "http://jupyter:8008",
        ),
        patch("backend.app.routers.kernel_runner.NOTEBOOK_DIR", tmp_path),
        patch("backend.app.routers.kernel_runner.httpx.AsyncClient", _AsyncClient),
        patch("backend.app.routers.kernel_runner.job_store.set_running", new=AsyncMock()),
        patch(
            "backend.app.routers.kernel_runner.job_store.set_complete", new=AsyncMock()
        ) as complete,
        patch("backend.app.routers.kernel_runner.job_store.set_failed", new=AsyncMock()),
        patch(
            "backend.app.routers.kernel_runner.progress_bus.publisher_for",
            return_value=lambda event: None,
        ),
    ):
        asyncio.run(
            kernel_runner._execute_notebook(
                "job-1",
                nb_path,
                "snntorch_sim",
                "nmtk-snntorch",
                notebook_path="workspace/notebooks/pipeline_snntorch_sim.ipynb",
            )
        )

    complete.assert_awaited_once()
    result = complete.await_args.kwargs["result"]
    assert result["metadata"]["activity_npy_b64_by_epoch"] == {
        1: "ZmFrZXppcA==",
        5: "ZmluYWw=",
    }
