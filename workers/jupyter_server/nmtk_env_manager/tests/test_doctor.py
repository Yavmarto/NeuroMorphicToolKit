from __future__ import annotations

from pathlib import Path
from types import SimpleNamespace

from nmtk_env_manager import handlers


class _Manager:
    def _python_for(self, _slug: str) -> Path:
        return Path("/usr/bin/python3")


def test_doctor_checks_storage_and_snntorch_kernel(monkeypatch, tmp_path) -> None:
    monkeypatch.setattr(
        handlers.subprocess,
        "run",
        lambda *_args, **_kwargs: SimpleNamespace(returncode=0, stderr=""),
    )
    started: list[tuple[str, tuple[str, ...]]] = []
    monkeypatch.setattr(
        handlers,
        "_probe_kernel",
        lambda kernel, imports: started.append((kernel, imports)),
    )

    report = handlers._doctor_report(_Manager(), tmp_path, ["snntorch"])

    assert report["overall"] == "ok"
    assert started == [("nmtk-snntorch", ("torch", "snntorch"))]
    assert {item["id"] for item in report["checks"]} == {
        "jupyter-storage",
        "framework-snntorch",
    }
    assert list(tmp_path.iterdir()) == []


def test_doctor_reports_missing_snntorch_as_required_failure(
    monkeypatch, tmp_path
) -> None:
    monkeypatch.setattr(
        handlers.subprocess,
        "run",
        lambda *_args, **_kwargs: SimpleNamespace(
            returncode=1,
            stderr="No module named snntorch",
        ),
    )

    report = handlers._doctor_report(_Manager(), tmp_path, ["snntorch"])

    framework = next(
        item for item in report["checks"] if item["id"] == "framework-snntorch"
    )
    assert framework["status"] == "failed"
    assert framework["required"] is True
    assert report["overall"] == "failed"


def test_doctor_marks_unknown_optional_framework_not_configured(
    monkeypatch, tmp_path
) -> None:
    monkeypatch.setattr(
        handlers.subprocess,
        "run",
        lambda *_args, **_kwargs: SimpleNamespace(returncode=0, stderr=""),
    )
    monkeypatch.setattr(handlers, "_probe_kernel", lambda *_args: None)

    report = handlers._doctor_report(_Manager(), tmp_path, ["snntorch", "unknown-sdk"])

    optional = next(
        item for item in report["checks"] if item["id"] == "framework-unknown-sdk"
    )
    assert optional["status"] == "notConfigured"
    assert optional["required"] is False
