from __future__ import annotations

import json
import sys
import types
from pathlib import Path
from queue import Empty

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

if "jupyter_server.base.handlers" not in sys.modules:
    jupyter_server = types.ModuleType("jupyter_server")
    jupyter_server_base = types.ModuleType("jupyter_server.base")
    jupyter_server_handlers = types.ModuleType("jupyter_server.base.handlers")
    jupyter_server_handlers.APIHandler = object
    jupyter_server_utils = types.ModuleType("jupyter_server.utils")
    jupyter_server_utils.url_path_join = lambda *parts: "/".join(parts)
    tornado = types.ModuleType("tornado")
    tornado_web = types.ModuleType("tornado.web")
    tornado_web.HTTPError = RuntimeError
    tornado.web = tornado_web
    jupyter_server.base = jupyter_server_base
    sys.modules["jupyter_server"] = jupyter_server
    sys.modules["jupyter_server.base"] = jupyter_server_base
    sys.modules["jupyter_server.base.handlers"] = jupyter_server_handlers
    sys.modules["jupyter_server.utils"] = jupyter_server_utils
    sys.modules["tornado"] = tornado
    sys.modules["tornado.web"] = tornado_web

from nmtk_env_manager import handlers


def _install_fake_nbformat(monkeypatch) -> None:
    def _to_namespace(value):
        if isinstance(value, dict):
            return types.SimpleNamespace(
                **{key: _to_namespace(item) for key, item in value.items()}
            )
        if isinstance(value, list):
            return [_to_namespace(item) for item in value]
        return value

    def _to_jsonable(value):
        if isinstance(value, types.SimpleNamespace):
            return {key: _to_jsonable(item) for key, item in vars(value).items()}
        if isinstance(value, list):
            return [_to_jsonable(item) for item in value]
        return value

    nbformat_module = types.ModuleType("nbformat")
    nbformat_module.read = lambda path, as_version=4: _to_namespace(
        json.loads(Path(path).read_text(encoding="utf-8"))
    )
    nbformat_module.write = lambda notebook, path: Path(path).write_text(
        json.dumps(_to_jsonable(notebook)),
        encoding="utf-8",
    )
    nbformat_v4_module = types.ModuleType("nbformat.v4")
    nbformat_v4_module.new_output = lambda **kwargs: _to_namespace(kwargs)
    monkeypatch.setitem(sys.modules, "nbformat", nbformat_module)
    monkeypatch.setitem(sys.modules, "nbformat.v4", nbformat_v4_module)


def test_resolve_execute_kernel_name_uses_notebook_metadata(tmp_path: Path) -> None:
    notebook_path = tmp_path / "example.ipynb"
    notebook_path.write_text(
        json.dumps(
            {
                "metadata": {
                    "kernelspec": {
                        "name": "nmtk-snntorch",
                    }
                }
            }
        ),
        encoding="utf-8",
    )

    assert (
        handlers._resolve_execute_kernel_name(notebook_path, "python3")
        == "nmtk-snntorch"
    )


def test_execute_notebook_job_uses_resolved_kernel_and_collects_output(
    tmp_path: Path, monkeypatch
) -> None:
    notebook_path = tmp_path / "workspace" / "notebooks" / "example.ipynb"
    notebook_path.parent.mkdir(parents=True)
    notebook_path.write_text(
        json.dumps(
            {
                "cells": [
                    {
                        "cell_type": "code",
                        "source": "print('hello')",
                        "outputs": [],
                        "execution_count": None,
                        "metadata": {},
                    }
                ],
                "metadata": {"kernelspec": {"name": "nmtk-snntorch"}},
                "nbformat": 4,
                "nbformat_minor": 5,
            }
        ),
        encoding="utf-8",
    )
    _install_fake_nbformat(monkeypatch)

    progress_line = '{"__nmtk_progress__": true, "epoch": 1}'
    seen: list[str] = []

    class FakeBlockingClient:
        def __init__(self) -> None:
            self._messages = iter(
                [
                    {
                        "parent_header": {"msg_id": "msg-1"},
                        "msg_type": "execute_input",
                        "content": {"execution_count": 1},
                    },
                    {
                        "parent_header": {"msg_id": "msg-1"},
                        "msg_type": "stream",
                        "content": {"name": "stdout", "text": progress_line + "\n"},
                    },
                    {
                        "parent_header": {"msg_id": "msg-1"},
                        "msg_type": "status",
                        "content": {"execution_state": "idle"},
                    },
                ]
            )
            self._shell_messages = iter(
                [
                    {
                        "parent_header": {"msg_id": "msg-1"},
                        "msg_type": "execute_reply",
                        "content": {"status": "ok"},
                    }
                ]
            )

        def start_channels(self) -> None:
            return None

        def stop_channels(self) -> None:
            return None

        def wait_for_ready(self, timeout: int) -> None:
            assert timeout == 60

        def execute(self, _source: str) -> str:
            return "msg-1"

        def get_iopub_msg(self, timeout: int) -> dict:
            assert timeout == 1
            return next(self._messages)

        def get_shell_msg(self, timeout: int) -> dict:
            assert timeout == 1
            return next(self._shell_messages)

    started_with_cwd: list[str | None] = []

    class FakeKernelManager:
        def __init__(self, kernel_name: str) -> None:
            self.kernel_name = kernel_name
            self.client = FakeBlockingClient()

        def start_kernel(self, cwd: str | None = None) -> None:
            started_with_cwd.append(cwd)

        def blocking_client(self) -> FakeBlockingClient:
            return self.client

        def shutdown_kernel(self, now: bool = False) -> None:
            assert now is True

    monkeypatch.setitem(
        sys.modules,
        "jupyter_client",
        types.SimpleNamespace(KernelManager=FakeKernelManager),
    )

    result = handlers._execute_notebook_job(
        tmp_path,
        "workspace/notebooks/example.ipynb",
        "python3",
        seen.append,
    )

    assert result["kernelName"] == "nmtk-snntorch"
    assert result["output"] == [progress_line]
    assert seen == [progress_line]
    executed = json.loads(notebook_path.read_text(encoding="utf-8"))
    assert executed["cells"][0]["outputs"][0]["text"] == progress_line + "\n"
    # Regression: the kernel must be started with cwd set to the notebook's
    # own directory, not left to inherit the worker process's cwd (otherwise
    # relative paths like weights.npz silently resolve to the wrong place).
    assert started_with_cwd == [str(notebook_path.parent)]


def test_execute_notebook_job_waits_for_matching_execute_reply(
    tmp_path: Path, monkeypatch
) -> None:
    notebook_path = tmp_path / "workspace" / "notebooks" / "example.ipynb"
    notebook_path.parent.mkdir(parents=True)
    notebook_path.write_text(
        json.dumps(
            {
                "cells": [
                    {
                        "cell_type": "code",
                        "source": "print('hello')",
                        "outputs": [],
                        "execution_count": None,
                        "metadata": {},
                    }
                ],
                "metadata": {"kernelspec": {"name": "nmtk-snntorch"}},
                "nbformat": 4,
                "nbformat_minor": 5,
            }
        ),
        encoding="utf-8",
    )
    _install_fake_nbformat(monkeypatch)

    shell_timeouts: list[int] = []

    class FakeBlockingClient:
        def __init__(self) -> None:
            self._messages = iter(
                [
                    {
                        "parent_header": {"msg_id": "msg-1"},
                        "msg_type": "execute_input",
                        "content": {"execution_count": 1},
                    },
                    {
                        "parent_header": {"msg_id": "msg-1"},
                        "msg_type": "status",
                        "content": {"execution_state": "idle"},
                    },
                ]
            )
            self._shell_messages = iter(
                [
                    {
                        "parent_header": {"msg_id": "other"},
                        "msg_type": "execute_reply",
                        "content": {"status": "ok"},
                    },
                    {
                        "parent_header": {"msg_id": "msg-1"},
                        "msg_type": "execute_reply",
                        "content": {"status": "ok"},
                    },
                ]
            )

        def start_channels(self) -> None:
            return None

        def stop_channels(self) -> None:
            return None

        def wait_for_ready(self, timeout: int) -> None:
            assert timeout == 60

        def execute(self, _source: str) -> str:
            return "msg-1"

        def get_iopub_msg(self, timeout: int) -> dict:
            assert timeout == 1
            return next(self._messages)

        def get_shell_msg(self, timeout: int) -> dict:
            shell_timeouts.append(timeout)
            return next(self._shell_messages)

    class FakeKernelManager:
        def __init__(self, kernel_name: str) -> None:
            self.kernel_name = kernel_name
            self.client = FakeBlockingClient()

        def start_kernel(self, cwd: str | None = None) -> None:
            return None

        def blocking_client(self) -> FakeBlockingClient:
            return self.client

        def shutdown_kernel(self, now: bool = False) -> None:
            assert now is True

    monkeypatch.setitem(
        sys.modules,
        "jupyter_client",
        types.SimpleNamespace(KernelManager=FakeKernelManager),
    )

    result = handlers._execute_notebook_job(
        tmp_path,
        "workspace/notebooks/example.ipynb",
        "python3",
    )

    assert result["kernelName"] == "nmtk-snntorch"
    assert shell_timeouts == [1, 1]


def test_execute_notebook_job_times_out_waiting_for_execute_reply(
    tmp_path: Path, monkeypatch
) -> None:
    notebook_path = tmp_path / "workspace" / "notebooks" / "example.ipynb"
    notebook_path.parent.mkdir(parents=True)
    notebook_path.write_text(
        json.dumps(
            {
                "cells": [
                    {
                        "cell_type": "code",
                        "source": "print('hello')",
                        "outputs": [],
                        "execution_count": None,
                        "metadata": {},
                    }
                ],
                "metadata": {"kernelspec": {"name": "nmtk-snntorch"}},
                "nbformat": 4,
                "nbformat_minor": 5,
            }
        ),
        encoding="utf-8",
    )
    _install_fake_nbformat(monkeypatch)
    monkeypatch.setattr(handlers, "_CELL_EXECUTION_TIMEOUT_SECONDS", 1)

    class FakeBlockingClient:
        def __init__(self) -> None:
            self._messages = iter(
                [
                    {
                        "parent_header": {"msg_id": "msg-1"},
                        "msg_type": "execute_input",
                        "content": {"execution_count": 1},
                    },
                    {
                        "parent_header": {"msg_id": "msg-1"},
                        "msg_type": "status",
                        "content": {"execution_state": "idle"},
                    },
                ]
            )

        def start_channels(self) -> None:
            return None

        def stop_channels(self) -> None:
            return None

        def wait_for_ready(self, timeout: int) -> None:
            assert timeout == 60

        def execute(self, _source: str) -> str:
            return "msg-1"

        def get_iopub_msg(self, timeout: int) -> dict:
            return next(self._messages)

        def get_shell_msg(self, timeout: int) -> dict:
            raise Empty

    class FakeKernelManager:
        def __init__(self, kernel_name: str) -> None:
            self.kernel_name = kernel_name
            self.client = FakeBlockingClient()

        def start_kernel(self, cwd: str | None = None) -> None:
            return None

        def blocking_client(self) -> FakeBlockingClient:
            return self.client

        def shutdown_kernel(self, now: bool = False) -> None:
            assert now is True

    monkeypatch.setitem(
        sys.modules,
        "jupyter_client",
        types.SimpleNamespace(KernelManager=FakeKernelManager),
    )

    with pytest.raises(TimeoutError, match="execute reply"):
        handlers._execute_notebook_job(
            tmp_path,
            "workspace/notebooks/example.ipynb",
            "python3",
        )
