"""Tests for the CI runner health check and workflow validator (CEL-313)."""

from __future__ import annotations

import importlib.util
import sys
from datetime import datetime, timezone
from pathlib import Path
from types import ModuleType

REPO_ROOT = Path(__file__).resolve().parent.parent
CI_DIR = REPO_ROOT / "scripts" / "ci"


def load_ci_script(name: str) -> ModuleType:
    path = CI_DIR / f"{name}.py"
    module_name = f"_ci_{name}"
    spec = importlib.util.spec_from_file_location(module_name, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


runner_health = load_ci_script("runner_health_check")
validate_workflows = load_ci_script("validate_workflows")

NOW = datetime(2026, 9, 17, 12, 0, tzinfo=timezone.utc)


def runner(name: str, status: str, *labels: str) -> dict:
    return {
        "name": name,
        "status": status,
        "labels": [{"name": label} for label in labels],
    }


def test_runner_labels_are_lowercased_and_collected() -> None:
    labels = runner_health.runner_label_names(
        runner("wsl", "online", "self-hosted", "Linux", "X64", "nmtk-linux")
    )
    assert labels == {"self-hosted", "linux", "x64", "nmtk-linux"}


def test_missing_runner_group_alerts() -> None:
    groups = (runner_health.RequiredRunner(("nmtk-mac",), False, "mac"),)
    alerts, notes = runner_health.evaluate_runners([], groups)
    assert [alert.name for alert in alerts] == ["CIRunnerMissing"]
    assert notes == []


def test_offline_is_expected_for_sleeping_runner() -> None:
    groups = (runner_health.RequiredRunner(("nmtk-linux",), True, "wsl"),)
    runners = [runner("wsl", "offline", "self-hosted", "Linux", "X64", "nmtk-linux")]
    alerts, notes = runner_health.evaluate_runners(runners, groups)
    assert alerts == []
    assert "expected when idle" in notes[0]


def test_offline_always_on_runner_alerts() -> None:
    groups = (runner_health.RequiredRunner(("nmtk-mac",), False, "mac"),)
    runners = [runner("mac", "offline", "self-hosted", "macOS", "ARM64", "nmtk-mac")]
    alerts, _ = runner_health.evaluate_runners(runners, groups)
    assert [alert.name for alert in alerts] == ["CIRunnerOffline"]


def test_online_runner_is_healthy() -> None:
    groups = (
        runner_health.RequiredRunner(("self-hosted", "Linux", "X64"), False, "linux"),
    )
    runners = [runner("wsl", "online", "self-hosted", "Linux", "X64")]
    alerts, notes = runner_health.evaluate_runners(runners, groups)
    assert alerts == []
    assert notes == ["[self-hosted,Linux,X64] online (1 of 1)"]


def test_queued_job_under_threshold_does_not_alert() -> None:
    jobs = [
        {
            "status": "queued",
            "created_at": "2026-09-17T11:50:00Z",
            "name": "test",
            "labels": ["self-hosted", "Linux", "X64"],
        }
    ]
    assert runner_health.evaluate_queue(jobs, 30, NOW) == []


def test_queued_job_over_threshold_alerts() -> None:
    jobs = [
        {
            "status": "queued",
            "created_at": "2026-09-17T10:00:00Z",
            "name": "test (stable)",
            "labels": ["self-hosted", "Linux", "X64"],
            "html_url": "https://example.test/run/1",
        }
    ]
    alerts = runner_health.evaluate_queue(jobs, 30, NOW)
    assert [alert.name for alert in alerts] == ["CIJobStuckQueued"]
    assert "120m" in alerts[0].summary


def test_parse_required_groups() -> None:
    groups = runner_health.parse_required("nmtk-linux; nmtk-mac, ARM64")
    assert groups[0].labels == ("nmtk-linux",)
    assert groups[1].labels == ("nmtk-mac", "ARM64")


def test_fingerprint_changes_with_alert_set() -> None:
    one = [runner_health.Alert("CIRunnerOffline", "critical", "nmtk-mac", "s", "d")]
    two = one + [
        runner_health.Alert("CIRunnerOffline", "critical", "nmtk-linux", "s", "d")
    ]
    assert runner_health.fingerprint(one) != runner_health.fingerprint(two)
    assert runner_health.fingerprint(one) == runner_health.fingerprint(list(one))


WORKFLOW_VALID = """
name: Example
on: push
jobs:
  build:
    runs-on: ubuntu-latest
    outputs:
      version: ${{ steps.resolve.outputs.version }}
    steps:
      - run: echo ok
  publish:
    needs: build
    runs-on: ubuntu-latest
    steps:
      - run: echo ${{ needs.build.outputs.version }}
"""


def test_valid_workflow_has_no_errors() -> None:
    document = validate_workflows.yaml.safe_load(WORKFLOW_VALID)
    assert (
        validate_workflows.validate_document(Path("wf.yml"), WORKFLOW_VALID, document)
        == []
    )


def test_missing_needs_job_is_reported() -> None:
    text = WORKFLOW_VALID.replace("needs: build", "needs: missing-job")
    document = validate_workflows.yaml.safe_load(text)
    errors = validate_workflows.validate_document(Path("wf.yml"), text, document)
    assert any("missing-job" in error for error in errors)


def test_unknown_needs_expression_is_reported() -> None:
    text = WORKFLOW_VALID.replace("needs.build.outputs.version", "needs.gone.result")
    document = validate_workflows.yaml.safe_load(text)
    errors = validate_workflows.validate_document(Path("wf.yml"), text, document)
    assert any("needs.gone" in error for error in errors)


def test_undeclared_output_is_reported() -> None:
    text = WORKFLOW_VALID.replace(
        "needs.build.outputs.version", "needs.build.outputs.nope"
    )
    document = validate_workflows.yaml.safe_load(text)
    errors = validate_workflows.validate_document(Path("wf.yml"), text, document)
    assert any("build.outputs.nope" in error for error in errors)


def test_yaml_parse_failure_returns_nonzero(tmp_path: Path) -> None:
    """A malformed file must fail the validator that ci.yml wires into ci-passed."""
    (tmp_path / "broken.yml").write_text("jobs: [unclosed\n", encoding="utf-8")
    exit_code = validate_workflows.main(["--root", str(tmp_path), "--glob", "*.yml"])
    assert exit_code == 1


def test_missing_workflow_file_is_a_usage_error(tmp_path: Path) -> None:
    exit_code = validate_workflows.main(
        ["--root", str(tmp_path), "--glob", "does-not-exist-*.yml"]
    )
    assert exit_code == 2


def test_shipped_workflows_are_valid() -> None:
    """The gate's own regression test: guard every checked-in workflow file."""
    exit_code = validate_workflows.main(["--root", str(REPO_ROOT)])
    assert exit_code == 0
