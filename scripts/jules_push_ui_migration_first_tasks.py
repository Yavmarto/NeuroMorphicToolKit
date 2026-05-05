#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from pathlib import Path

from dotenv import load_dotenv

try:
    from scripts.jules_api import JulesApiError, JulesClient, get_repo_identifier
except ImportError:
    from jules_api import JulesApiError, JulesClient, get_repo_identifier


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
ENV_PATH = SCRIPT_DIR / ".env"
load_dotenv(ENV_PATH)

DEFAULT_MODULES = (
    "neurocnl",
    "Neurochip",
    "Neurobench",
    "Neurosense",
    "Neurohub",
)


@dataclass(frozen=True)
class ModuleTask:
    module_name: str
    repo_path: Path
    brief_path: Path
    repo_identifier: str
    branch: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Create one Jules session per frontend-bearing submodule for the first "
            "repo-local desktop UI migration task."
        )
    )
    parser.add_argument(
        "--modules",
        nargs="+",
        default=list(DEFAULT_MODULES),
        help="Subset of modules to target. Defaults to all UI-bearing modules.",
    )
    parser.add_argument(
        "--branch",
        default=None,
        help="Override the starting branch for every session. Defaults to each repo's current branch.",
    )
    parser.add_argument(
        "--automation-mode",
        default="AUTO_CREATE_PR",
        help="Jules automation mode. Defaults to AUTO_CREATE_PR.",
    )
    parser.add_argument(
        "--require-plan-approval",
        action="store_true",
        help="Require Jules plan approval before it starts coding.",
    )
    parser.add_argument(
        "--max-workers",
        type=int,
        default=4,
        help="Maximum parallel Jules session creations. Defaults to 4.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the sessions that would be created without calling the Jules API.",
    )
    return parser.parse_args()


def current_branch(repo_path: Path) -> str:
    try:
        branch = subprocess.check_output(
            ["git", "-C", str(repo_path), "branch", "--show-current"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except subprocess.CalledProcessError as exc:
        raise RuntimeError(f"Could not read current branch for {repo_path}") from exc
    if not branch:
        raise RuntimeError(f"Repository at {repo_path} is in detached HEAD state.")
    return branch


def parse_markdown(file_path: Path) -> tuple[str, str]:
    content = file_path.read_text(encoding="utf-8").strip()
    if not content:
        raise ValueError(f"{file_path} is empty.")
    lines = content.splitlines()
    if lines[0].startswith("# "):
        return lines[0][2:].strip(), "\n".join(lines[1:]).strip()
    return file_path.stem, content


def discover_module_tasks(
    module_names: list[str],
    *,
    repo_root: Path = REPO_ROOT,
    branch_override: str | None = None,
) -> list[ModuleTask]:
    tasks: list[ModuleTask] = []
    for module_name in module_names:
        repo_path = repo_root / module_name
        brief_path = repo_path / "UI migration.md"
        if not repo_path.is_dir():
            raise RuntimeError(f"Module path not found: {repo_path}")
        if not brief_path.is_file():
            raise RuntimeError(f"UI migration brief not found: {brief_path}")

        repo_identifier = get_repo_identifier(str(repo_path))
        if not repo_identifier:
            raise RuntimeError(f"Could not determine git remote for {repo_path}")

        branch = branch_override or current_branch(repo_path)
        tasks.append(
            ModuleTask(
                module_name=module_name,
                repo_path=repo_path,
                brief_path=brief_path,
                repo_identifier=repo_identifier,
                branch=branch,
            )
        )
    return tasks


def build_prompt(task: ModuleTask) -> tuple[str, str]:
    brief_title, brief_body = parse_markdown(task.brief_path)
    title = f"{task.module_name}: first desktop UI migration task"
    prompt = "\n".join(
        [
            f"Work only in the {task.module_name} repository.",
            "Before editing, read AGENTS.md plus the relevant ADR and spec files in that repo.",
            "Inspect the local frontend and use the UI migration brief below as context.",
            "Do not modify any other repository.",
            "Important scoping rule: complete only the first remaining repo-local desktop migration task for this module.",
            "If the migration brief is already materially satisfied in this repo, convert this into a verification pass:",
            "- verify the desktop layout, theme wiring, and shared-core usage for this repo",
            "- fix any repo-local regressions you find",
            "- do not invent cross-repo work",
            "Run the repo-local verification commands before finishing.",
            f"Task context: {brief_title}",
            "",
            brief_body,
            "",
            "Success criteria:",
            "- exactly one focused repo-local migration step is completed, or verified complete with repo-local fixes",
            "- edits stay inside this repository",
            "- include verification results in the final Jules summary",
        ]
    )
    return title, prompt


def create_session_for_task(
    task: ModuleTask,
    *,
    api_key: str,
    automation_mode: str,
    require_plan_approval: bool,
    dry_run: bool,
) -> str:
    title, prompt = build_prompt(task)
    client = JulesClient(api_key)
    try:
        resolved_source = client.resolve_source(repo_identifier=task.repo_identifier)
        branch = client.validate_branch(resolved_source, task.branch)

        if dry_run:
            return (
                f"DRY RUN {task.module_name}: source={resolved_source.name} "
                f"repo={task.repo_identifier} branch={branch} title={title}"
            )

        session_payload = client.create_session(
            title=title,
            prompt=prompt,
            source_name=resolved_source.name,
            branch=branch,
            require_plan_approval=require_plan_approval,
            automation_mode=automation_mode,
        )
        session_name = session_payload.get("name", "unknown")
        session_url = session_payload.get("url")
        if session_url:
            return f"CREATED {task.module_name}: {session_name} ({session_url})"
        return f"CREATED {task.module_name}: {session_name}"
    finally:
        client.close()


def main() -> int:
    args = parse_args()
    api_key = os.getenv("JULES_API_KEY")
    if not api_key:
        print("Error: JULES_API_KEY not found in scripts/.env", file=sys.stderr)
        return 1

    try:
        tasks = discover_module_tasks(args.modules, branch_override=args.branch)
    except Exception as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    results: list[str] = []
    max_workers = max(1, min(args.max_workers, len(tasks)))
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = {
            executor.submit(
                create_session_for_task,
                task,
                api_key=api_key,
                automation_mode=args.automation_mode,
                require_plan_approval=args.require_plan_approval,
                dry_run=args.dry_run,
            ): task
            for task in tasks
        }
        for future in as_completed(futures):
            task = futures[future]
            try:
                results.append(future.result())
            except JulesApiError as exc:
                results.append(f"FAILED {task.module_name}: {exc}")
            except Exception as exc:
                results.append(f"FAILED {task.module_name}: {exc}")

    for line in sorted(results):
        print(line)
    return 0 if not any(line.startswith("FAILED ") for line in results) else 2


if __name__ == "__main__":
    raise SystemExit(main())
