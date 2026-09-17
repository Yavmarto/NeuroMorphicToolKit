#!/usr/bin/env python3
"""Alert when a required self-hosted CI runner is missing/offline or a job is stuck queued.

Self-hosted runners have no automatic fallback (ADR-0012), so a runner outage
stops the whole pipeline. This is the scheduled check that notices. It runs from
`.github/workflows/runner-health.yml` on a GitHub-hosted runner on purpose: the
check must keep working when every self-hosted runner is down.

Two checks:

1. Required runner unhealthy. A runner label group used by a workflow must have
   at least one registered runner. A group whose only runners are offline raises
   an alert unless the group is marked as sleeping on purpose (the Wake-on-LAN
   runners are offline when idle; see docs/ci-runners.md).
2. Job queued past the threshold. A queued job older than
   QUEUED_THRESHOLD_MINUTES means the matching runner did not wake or cannot run.

Alerts go to ALERTMANAGER_URL (Alertmanager v2 API) when set, and are always
recorded in a tracking issue in the repository, which needs no extra
infrastructure.

Exit codes: 0 healthy, 1 problems found, 2 bad configuration, 3 could not evaluate.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import urllib.error
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any, Iterable

API_ROOT = "https://api.github.com"
ISSUE_TITLE = "[monitor] CI runner health"


@dataclass(frozen=True)
class RequiredRunner:
    """A label group a workflow needs, and whether being offline is expected."""

    labels: tuple[str, ...]
    expect_offline: bool
    note: str


@dataclass(frozen=True)
class Alert:
    name: str
    severity: str
    group: str
    summary: str
    description: str

    def fingerprint(self) -> tuple[str, str]:
        return (self.name, self.group)


# The required groups are the labels that appear in `runs-on:` in the workflows.
# Keep in sync with docs/ci-runners.md and with the `runs-on` values of
# .github/workflows/ci.yml and .github/workflows/nmtk-ci.yml.
DEFAULT_REQUIRED: tuple[RequiredRunner, ...] = (
    RequiredRunner(
        ("nmtk-linux",),
        True,
        "nmtk-ci test and build-linux (WSL2 runner, sleeps when idle)",
    ),
    RequiredRunner(
        ("nmtk-mac",),
        False,
        "nmtk-ci build-macos and integration-test-apple (always-on Mac)",
    ),
    RequiredRunner(
        ("self-hosted", "Linux", "X64"),
        True,
        "ci.yml Linux jobs (same WSL2 runner, sleeps when idle)",
    ),
    RequiredRunner(
        ("self-hosted", "macOS", "ARM64"),
        False,
        "ci.yml macOS jobs (always-on Mac)",
    ),
    RequiredRunner(
        ("self-hosted", "Windows", "X64"),
        True,
        "ci.yml Windows jobs (Wake-on-LAN box, sleeps when idle)",
    ),
)


def parse_time(value: Any) -> datetime | None:
    if not isinstance(value, str) or not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def runner_label_names(runner: dict[str, Any]) -> set[str]:
    names = set()
    for label in runner.get("labels", []) or []:
        if isinstance(label, dict) and isinstance(label.get("name"), str):
            names.add(label["name"].lower())
    return names


def group_display(labels: Iterable[str]) -> str:
    return ",".join(labels)


def evaluate_runners(
    runners: list[dict[str, Any]],
    required: Iterable[RequiredRunner],
) -> tuple[list[Alert], list[str]]:
    """Return (alerts, informational notes) for the required runner groups."""
    alerts: list[Alert] = []
    notes: list[str] = []
    for group in required:
        wanted = {label.lower() for label in group.labels}
        display = group_display(group.labels)
        matching = [r for r in runners if wanted <= runner_label_names(r)]
        if not matching:
            alerts.append(
                Alert(
                    name="CIRunnerMissing",
                    severity="critical",
                    group=display,
                    summary=f"No self-hosted runner is registered with [{display}]",
                    description=(
                        f"Workflows that use runs-on: [{display}] cannot start. "
                        f"Expected for: {group.note}. Register a runner with these "
                        "labels, or change the workflow in docs/ci-runners.md."
                    ),
                )
            )
            continue
        online = [r for r in matching if r.get("status") == "online"]
        if online:
            notes.append(f"[{display}] online ({len(online)} of {len(matching)})")
            continue
        if group.expect_offline:
            notes.append(
                f"[{display}] all {len(matching)} runner(s) offline; "
                "expected when idle (Wake-on-LAN wakes on queued work)"
            )
            continue
        alerts.append(
            Alert(
                name="CIRunnerOffline",
                severity="critical",
                group=display,
                summary=f"All {len(matching)} runner(s) with [{display}] are offline",
                description=(
                    f"This group is expected to stay online ({group.note}), so "
                    "workflows that use it are blocked."
                ),
            )
        )
    return alerts, notes


def evaluate_queue(
    jobs: list[dict[str, Any]],
    threshold_minutes: int,
    now: datetime,
) -> list[Alert]:
    """Alert on jobs that have sat queued longer than the threshold."""
    alerts: list[Alert] = []
    threshold = timedelta(minutes=threshold_minutes)
    for job in jobs:
        if job.get("status") != "queued":
            continue
        created = parse_time(job.get("created_at"))
        if created is None:
            continue
        age = now - created
        if age < threshold:
            continue
        labels = job.get("labels") or []
        display = ",".join(str(label) for label in labels) or "unknown"
        minutes = int(age.total_seconds() // 60)
        alerts.append(
            Alert(
                name="CIJobStuckQueued",
                severity="critical",
                group=display,
                summary=(
                    f"CI job queued for {minutes}m: {job.get('name', 'unknown job')}"
                ),
                description=(
                    f"Job '{job.get('name')}' has waited {minutes} minutes for a "
                    f"runner with [{display}] (threshold {threshold_minutes}m). "
                    f"{job.get('html_url', '')} A sleeping runner should wake; if it "
                    "does not, use the failover steps in docs/ci-runners.md."
                ),
            )
        )
    return alerts


class GitHub:
    def __init__(self, token: str | None, repo: str) -> None:
        self.token = token
        self.repo = repo

    def _open(self, method: str, path: str, body: Any = None) -> Any:
        url = path if path.startswith("http") else f"{API_ROOT}{path}"
        data = json.dumps(body).encode() if body is not None else None
        request = urllib.request.Request(url, data=data, method=method)
        if self.token:
            request.add_header("Authorization", f"Bearer {self.token}")
        request.add_header("Accept", "application/vnd.github+json")
        request.add_header("X-GitHub-Api-Version", "2022-11-28")
        request.add_header("User-Agent", "nmtk-runner-health")
        if data is not None:
            request.add_header("Content-Type", "application/json")
        with urllib.request.urlopen(request, timeout=30) as response:
            raw = response.read().decode()
        return json.loads(raw) if raw else None

    def get(self, path: str) -> Any:
        return self._open("GET", path)

    def post(self, path: str, body: Any) -> Any:
        return self._open("POST", path, body)

    def patch(self, path: str, body: Any) -> Any:
        return self._open("PATCH", path, body)

    def list_runners(self) -> list[dict[str, Any]] | None:
        """Return repository runners, or None when the token cannot read them."""
        try:
            payload = self.get(f"/repos/{self.repo}/actions/runners?per_page=100")
        except urllib.error.HTTPError as error:
            if error.code in (401, 403, 404):
                return None
            raise
        return list(payload.get("runners", []))

    def list_queued_jobs(self, max_runs: int = 50) -> list[dict[str, Any]]:
        runs = self.get(
            f"/repos/{self.repo}/actions/runs?status=queued&per_page={max_runs}"
        )
        jobs: list[dict[str, Any]] = []
        for run in runs.get("workflow_runs", []) or []:
            data = self.get(
                f"/repos/{self.repo}/actions/runs/{run['id']}/jobs?per_page=100"
            )
            for job in data.get("jobs", []) or []:
                job.setdefault("run_id", run.get("id"))
                jobs.append(job)
        return jobs

    def find_tracking_issue(self) -> dict[str, Any] | None:
        for page in range(1, 4):
            issues = self.get(
                f"/repos/{self.repo}/issues?state=open&per_page=100&page={page}"
            )
            if not issues:
                return None
            for issue in issues:
                if issue.get("title") == ISSUE_TITLE and "pull_request" not in issue:
                    return issue
            if len(issues) < 100:
                return None
        return None


def build_report(
    alerts: list[Alert],
    notes: list[str],
    generated_at: datetime,
) -> str:
    lines = [f"Generated: {generated_at.isoformat(timespec='seconds')}"]
    if notes:
        lines.append("")
        lines.append("Runner groups:")
        lines.extend(f"- {note}" for note in notes)
    if alerts:
        lines.append("")
        lines.append("Problems:")
        for alert in alerts:
            lines.append(
                f"- [{alert.severity}] {alert.name} ({alert.group}): {alert.summary}"
            )
            lines.append(f"  {alert.description}")
    else:
        lines.append("")
        lines.append("No problems found.")
    return "\n".join(lines)


def fingerprint(alerts: list[Alert]) -> str:
    payload = json.dumps(sorted(a.fingerprint() for a in alerts)).encode()
    return hashlib.sha256(payload).hexdigest()[:16]


def dispatch_alertmanager(url: str, alerts: list[Alert], now: datetime) -> None:
    if not alerts:
        return
    base = url.rstrip("/")
    endpoint = base if base.endswith("/api/v2/alerts") else f"{base}/api/v2/alerts"
    starts_at = now.isoformat(timespec="seconds")
    payload = [
        {
            "labels": {
                "alertname": alert.name,
                "severity": alert.severity,
                "component": "ci",
                "runner_group": alert.group,
            },
            "annotations": {
                "summary": alert.summary,
                "description": alert.description,
            },
            "startsAt": starts_at,
        }
        for alert in alerts
    ]
    request = urllib.request.Request(
        endpoint,
        data=json.dumps(payload).encode(),
        method="POST",
    )
    request.add_header("Content-Type", "application/json")
    request.add_header("User-Agent", "nmtk-runner-health")
    with urllib.request.urlopen(request, timeout=30) as response:
        response.read()


def reconcile_issue(
    gh: GitHub,
    alerts: list[Alert],
    report: str,
    now: datetime,
    dry_run: bool,
) -> str:
    """Create, update, or close the tracking issue. Return a status word."""
    existing = gh.find_tracking_issue()
    mark = f"<!-- nmtk-ci-runner-health:{fingerprint(alerts)} -->"
    body = (
        f"{mark}\n"
        "Automated by `.github/workflows/runner-health.yml`. Do not close by hand; "
        "the monitor closes it when the runner fleet is healthy again.\n\n"
        f"```\n{report}\n```\n"
    )
    if dry_run:
        return "would-update" if existing else ("would-create" if alerts else "healthy")

    if alerts:
        if existing is None:
            gh.post(
                f"/repos/{gh.repo}/issues",
                {
                    "title": ISSUE_TITLE,
                    "body": body,
                    "labels": ["ci-runner-health"],
                },
            )
            return "created"
        previous = existing.get("body") or ""
        old_mark = previous.splitlines()[0] if previous else ""
        gh.patch(f"/repos/{gh.repo}/issues/{existing['number']}", {"body": body})
        if old_mark != mark:
            gh.post(
                f"/repos/{gh.repo}/issues/{existing['number']}/comments",
                {"body": f"Alert set changed.\n\n{report}"},
            )
            return "commented"
        return "unchanged"

    if existing is not None:
        gh.patch(
            f"/repos/{gh.repo}/issues/{existing['number']}",
            {"body": body, "state": "closed", "state_reason": "completed"},
        )
        gh.post(
            f"/repos/{gh.repo}/issues/{existing['number']}/comments",
            {"body": f"Runner fleet healthy again.\n\n{report}"},
        )
        return "resolved"
    return "healthy"


def write_step_summary(report: str) -> None:
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if not path:
        return
    try:
        with open(path, "a", encoding="utf-8") as handle:
            handle.write("## CI runner health\n\n```\n")
            handle.write(report)
            handle.write("\n```\n")
    except OSError:
        pass


def parse_required(value: str) -> tuple[RequiredRunner, ...]:
    """Parse REQUIRED_RUNNER_LABELS: groups split on ';', labels split on ','."""
    groups = []
    for raw_group in value.split(";"):
        labels = tuple(part.strip() for part in raw_group.split(",") if part.strip())
        if labels:
            groups.append(
                RequiredRunner(labels, True, "custom group (offline allowed)")
            )
    return tuple(groups)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY", ""))
    parser.add_argument(
        "--queued-threshold-minutes",
        type=int,
        default=int(os.environ.get("QUEUED_THRESHOLD_MINUTES", "30")),
    )
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--json", action="store_true", dest="as_json")
    args = parser.parse_args(argv)

    now = datetime.now(timezone.utc)
    repo = args.repo
    if not repo:
        print("error: --repo or GITHUB_REPOSITORY is required", file=sys.stderr)
        return 2

    required_env = os.environ.get("REQUIRED_RUNNER_LABELS")
    required = parse_required(required_env) if required_env else DEFAULT_REQUIRED

    token = os.environ.get("GITHUB_TOKEN")
    admin_token = os.environ.get("RUNNER_ADMIN_TOKEN") or token
    gh = GitHub(token, repo)

    alerts: list[Alert] = []
    notes: list[str] = []
    try:
        runner_client = GitHub(admin_token, repo)
        runners = runner_client.list_runners()
        if runners is None:
            notes.append(
                "runner inventory unavailable: RUNNER_ADMIN_TOKEN is unset or lacks "
                "Administration: read; offline checks skipped"
            )
        else:
            runner_alerts, runner_notes = evaluate_runners(runners, required)
            alerts.extend(runner_alerts)
            notes.extend(runner_notes)

        jobs = gh.list_queued_jobs()
        alerts.extend(evaluate_queue(jobs, args.queued_threshold_minutes, now))
    except urllib.error.HTTPError as error:
        print(
            f"error: GitHub API returned {error.code}: {error.reason}", file=sys.stderr
        )
        return 3
    except urllib.error.URLError as error:
        print(f"error: could not reach GitHub API: {error.reason}", file=sys.stderr)
        return 3

    alerts.sort(key=lambda a: (a.name, a.group))
    report = build_report(alerts, notes, now)
    print(report)
    write_step_summary(report)
    if args.as_json:
        print(
            json.dumps(
                {
                    "alerts": [alert.__dict__ for alert in alerts],
                    "notes": notes,
                    "fingerprint": fingerprint(alerts),
                }
            )
        )

    alertmanager_url = os.environ.get("ALERTMANAGER_URL", "")
    if alerts and alertmanager_url:
        try:
            dispatch_alertmanager(alertmanager_url, alerts, now)
            notes.append("alerts sent to Alertmanager")
        except (urllib.error.HTTPError, urllib.error.URLError) as error:
            print(f"warning: Alertmanager delivery failed: {error}", file=sys.stderr)

    if token:
        try:
            outcome = reconcile_issue(gh, alerts, report, now, args.dry_run)
            print(f"tracking issue: {outcome}")
        except urllib.error.HTTPError as error:
            print(
                f"warning: tracking issue update failed: {error.code} {error.reason}",
                file=sys.stderr,
            )

    return 1 if alerts else 0


if __name__ == "__main__":
    raise SystemExit(main())
