from __future__ import annotations

import argparse
import json
import re
import subprocess
import tempfile
from pathlib import Path
from urllib.parse import urlparse


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--root",
        default=Path(__file__).resolve().parents[1],
        type=Path,
        help="Path to gpt5.4-dev-pipeline",
    )
    parser.add_argument("--module", action="append", default=[])
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--repo", help="Override GitHub repo in owner/name form")
    return parser.parse_args()


def resolve_repo(root_dir: Path, module: dict, override_repo: str | None) -> str:
    if override_repo:
        return override_repo
    if module.get("github_repo"):
        return module["github_repo"]

    repo_path = root_dir.parents[1] / module["repo_path"]
    result = subprocess.run(
        ["git", "-C", str(repo_path), "remote", "get-url", "origin"],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(f"Could not resolve git remote for {module['module_name']}")

    remote = result.stdout.strip()
    if remote.startswith("git@github.com:"):
        repo = remote.split(":", 1)[1]
    else:
        parsed = urlparse(remote)
        repo = parsed.path.lstrip("/")
    repo = repo.removesuffix(".git")
    if repo.count("/") != 1:
        raise RuntimeError(
            f"Unsupported remote URL for {module['module_name']}: {remote}"
        )
    return repo


def build_body(issue: dict, dependency_numbers: list[int]) -> str:
    lines: list[str] = []
    lines.append(issue["objective"])
    lines.append("")
    lines.append("Source spec references:")
    for item in issue["spec_refs"]:
        lines.append(f"- {item}")
    lines.append("")
    lines.append("Conversion steps:")
    for item in issue["conversion_steps"]:
        lines.append(f"- {item}")
    lines.append("")
    lines.append("Contract targets:")
    for item in issue["contract_targets"]:
        lines.append(f"- {item}")
    lines.append("")
    lines.append("Property targets:")
    for item in issue["property_targets"]:
        lines.append(f"- {item}")
    lines.append("")
    lines.append("Acceptance checks:")
    for item in issue["acceptance_checks"]:
        lines.append(f"- {item}")
    if issue.get("workflow_updates"):
        lines.append("")
        lines.append("Workflow updates:")
        for item in issue["workflow_updates"]:
            lines.append(f"- {item}")
    if dependency_numbers:
        lines.append("")
        for issue_number in dependency_numbers:
            lines.append(f"blocked-by: #{issue_number}")
    return "\n".join(lines)


def create_issue(
    repo: str, title: str, labels: list[str], body: str, execute: bool
) -> int | None:
    if not execute:
        print(f"[dry-run] would create issue in {repo}: {title}")
        return None

    with tempfile.NamedTemporaryFile("w", delete=False) as handle:
        handle.write(body)
        body_path = handle.name

    command = [
        "gh",
        "issue",
        "create",
        "--repo",
        repo,
        "--title",
        title,
        "--body-file",
        body_path,
    ]
    for label in labels:
        command.extend(["--label", label])

    result = subprocess.run(command, capture_output=True, text=True, check=True)
    match = re.search(r"/(\d+)\s*$", result.stdout.strip())
    if not match:
        raise RuntimeError(
            f"Could not parse issue number from gh output: {result.stdout}"
        )
    return int(match.group(1))


def topo_sort_issues(issues: list[dict]) -> list[dict]:
    indexed = {issue["id"]: issue for issue in issues}
    resolved: list[dict] = []
    seen: set[str] = set()

    while len(resolved) < len(issues):
        progressed = False
        for issue in issues:
            if issue["id"] in seen:
                continue
            deps = issue.get("depends_on", [])
            if all(dep in seen for dep in deps):
                resolved.append(issue)
                seen.add(issue["id"])
                progressed = True
        if not progressed:
            unresolved = [issue_id for issue_id in indexed if issue_id not in seen]
            raise RuntimeError(
                f"Cycle or missing dependency in issue graph: {unresolved}"
            )
    return resolved


def main() -> int:
    args = parse_args()
    selected_modules = set(args.module) if args.module else None

    for config_path in sorted(args.root.glob("*/module.json")):
        if selected_modules and config_path.parent.name not in selected_modules:
            continue

        module = json.loads(config_path.read_text())
        repo = resolve_repo(args.root, module, args.repo)
        state_path = config_path.parent / ".issue-state.json"
        state = json.loads(state_path.read_text()) if state_path.exists() else {}

        for issue in topo_sort_issues(module["migration_issues"]):
            if issue["id"] in state:
                continue
            dependency_numbers = [
                state[dep] for dep in issue.get("depends_on", []) if dep in state
            ]
            body = build_body(issue, dependency_numbers)
            issue_number = create_issue(
                repo, issue["title"], issue["labels"], body, args.execute
            )
            if issue_number is not None:
                state[issue["id"]] = issue_number
                state_path.write_text(json.dumps(state, indent=2, sort_keys=True))
                print(
                    f"Created #{issue_number} for {module['module_name']}: {issue['title']}"
                )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
