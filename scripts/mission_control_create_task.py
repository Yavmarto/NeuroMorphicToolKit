from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path
from typing import Any

import requests
from dotenv import load_dotenv

try:
    from scripts.jules_api import normalize_repo_identifier
except ImportError:
    from jules_api import normalize_repo_identifier

# --- ENVIRONMENT CONFIGURATION ---
SCRIPT_DIR = Path(__file__).resolve().parent
ENV_PATH = SCRIPT_DIR / ".env"
load_dotenv(ENV_PATH)

SERVER_URL = (os.getenv("MISSION_CONTROL_SERVER_URL") or "").rstrip("/")
API_KEY = os.getenv("MISSION_CONTROL_API_KEY") or ""
PROJECT_NAME = os.getenv("MISSION_CONTROL_PROJECT_NAME", "NTMK")
NUMERIC_AGENT_NAME_RE = re.compile(r"^\d+$")
REQUEST_TIMEOUT_SECONDS = 10


def build_headers(api_key: str) -> dict[str, str]:
    return {
        "Content-Type": "application/json",
        "x-api-key": api_key,
    }


def validate_configuration(server_url: str, api_key: str) -> None:
    if server_url and api_key:
        return
    print("❌ Error: MISSION_CONTROL_SERVER_URL or MISSION_CONTROL_API_KEY not found in scripts/.env")
    print("Please check your .env file in the 'scripts' directory.")
    sys.exit(1)


def validate_agent_name(agent_name: str | None) -> str | None:
    if agent_name is None:
        return None
    normalized = agent_name.strip()
    if not normalized:
        return None
    if NUMERIC_AGENT_NAME_RE.fullmatch(normalized):
        raise ValueError(
            "Mission Control now expects --agent to be an agent name, not a numeric agent ID."
        )
    return normalized


def optional_trimmed(value: str | None) -> str | None:
    if value is None:
        return None
    normalized = value.strip()
    return normalized or None


def build_jules_metadata(
    *,
    repo: str | None = None,
    branch: str | None = None,
    source: str | None = None,
    require_plan_approval: bool = False,
) -> dict[str, Any] | None:
    request: dict[str, Any] = {}

    normalized_repo = optional_trimmed(repo)
    if normalized_repo:
        request["repo"] = normalize_repo_identifier(normalized_repo)

    normalized_branch = optional_trimmed(branch)
    if normalized_branch:
        request["branch"] = normalized_branch

    normalized_source = optional_trimmed(source)
    if normalized_source:
        request["source"] = normalized_source

    if require_plan_approval:
        request["requirePlanApproval"] = True

    if not request:
        return None
    return {
        "mission_control_jules": {
            "request": request,
        }
    }


def parse_markdown(file_path: str) -> tuple[str, str]:
    """Reads the markdown file and intelligently extracts a title and description."""
    with open(file_path, "r", encoding="utf-8") as handle:
        lines = handle.readlines()

    if not lines:
        raise ValueError("The markdown file is empty.")

    if lines[0].startswith("# "):
        title = lines[0].replace("# ", "").strip()
        description = "".join(lines[1:]).strip()
    else:
        title = os.path.splitext(os.path.basename(file_path))[0]
        description = "".join(lines).strip()

    return title, description


def create_task(
    file_path: str,
    agent_name: str | None = None,
    jules_repo: str | None = None,
    jules_branch: str | None = None,
    jules_source: str | None = None,
    jules_require_plan_approval: bool = False,
    dry_run: bool = False,
    archive: bool = False,
    session: requests.Session | Any | None = None,
    server_url: str | None = None,
    api_key: str | None = None,
    project_name: str | None = None,
) -> bool:
    """Parses a markdown file and pushes it to Mission Control."""
    effective_server_url = (server_url or SERVER_URL).rstrip("/")
    effective_api_key = api_key or API_KEY
    effective_project_name = project_name or PROJECT_NAME
    validate_configuration(effective_server_url, effective_api_key)

    print(f"📄 Reading '{file_path}'...")

    try:
        title, description = parse_markdown(file_path)
    except Exception as exc:
        print(f"❌ Failed to read file: {exc}")
        return False

    if dry_run:
        print(f"🔍 [DRY RUN] Would create task: '{title}' in project [{effective_project_name}]")
        return True

    payload: dict[str, Any] = {
        "title": title,
        "description": description,
        "project": effective_project_name,
        "status": "inbox",
    }
    if agent_name:
        payload["assigned_to"] = agent_name
    jules_metadata = build_jules_metadata(
        repo=jules_repo,
        branch=jules_branch,
        source=jules_source,
        require_plan_approval=jules_require_plan_approval,
    )
    if jules_metadata:
        payload["metadata"] = jules_metadata

    print(f"🚀 Pushing task '{title}' to project [{effective_project_name}]...")
    client = session or requests.Session()
    owns_session = session is None
    try:
        response = client.post(
            f"{effective_server_url}/api/tasks",
            headers=build_headers(effective_api_key),
            json=payload,
            timeout=REQUEST_TIMEOUT_SECONDS,
        )
        response.raise_for_status()

        task_data = response.json()
        task = task_data.get("task", {})
        task_id = task.get("id", task_data.get("id", "Unknown"))
        print(f"✅ Success! Task added with ID: {task_id}")

        if archive:
            directory = os.path.dirname(file_path)
            filename = os.path.basename(file_path)
            new_path = os.path.join(directory, f"sent-{filename}")
            try:
                os.rename(file_path, new_path)
                print(f"📦 Archived: {filename} -> sent-{filename}")
            except Exception as exc:
                print(f"⚠️ Failed to archive {filename}: {exc}")
        return True
    except requests.exceptions.RequestException as exc:
        print(f"❌ Failed to create task: {exc}")
        if hasattr(exc, "response") and exc.response is not None:
            print(f"Server response: {exc.response.text}")
        return False
    finally:
        if owns_session:
            client.close()


def scan_workspace_for_issues() -> list[str]:
    """Finds all 'issues' directories in the project root and subdirectories."""
    repo_root = Path(__file__).resolve().parents[1]
    print(f"🔍 Scanning workspace root: {repo_root}")

    issues_folders: list[str] = []
    for root, dirs, _files in os.walk(repo_root):
        dirs[:] = [directory for directory in dirs if not directory.startswith(".")]
        if "issues" in dirs:
            issues_folders.append(os.path.join(root, "issues"))

    return sorted(issues_folders)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Push Markdown files as tasks to Mission Control."
    )
    parser.add_argument("path", nargs="?", help="Path to the Markdown file or directory")
    parser.add_argument("--all", action="store_true", help="Scan the entire workspace for 'issues' folders")
    parser.add_argument("--agent", help="Optional: agent name to assign the task to", default=None)
    parser.add_argument(
        "--repo",
        help="Optional: Jules repo identifier (owner/repo) stored in metadata.mission_control_jules.request.repo",
        default=None,
    )
    parser.add_argument(
        "--branch",
        help="Optional: Jules starting branch stored in metadata.mission_control_jules.request.branch",
        default=None,
    )
    parser.add_argument(
        "--jules-source",
        help="Optional: Jules source resource name stored in metadata.mission_control_jules.request.source",
        default=None,
    )
    parser.add_argument(
        "--jules-require-plan-approval",
        action="store_true",
        help="Set metadata.mission_control_jules.request.requirePlanApproval=true",
    )
    parser.add_argument("--dry-run", action="store_true", help="Preview tasks without sending them")
    parser.add_argument("--archive", action="store_true", help="Rename files to 'sent-...' after successful posting")

    args = parser.parse_args()
    validate_configuration(SERVER_URL, API_KEY)

    try:
        agent_name = validate_agent_name(args.agent)
    except ValueError as exc:
        print(f"❌ {exc}")
        return 1

    if args.all:
        folders = scan_workspace_for_issues()
        if not folders:
            print("ℹ️ No 'issues' folders found in workspace.")
            return 0

        print(f"📂 Found {len(folders)} issues folders. Processing...")
        total_posted = 0
        for folder in folders:
            print(f"\n📁 Folder: {os.path.relpath(folder)}")
            files = [
                file_name
                for file_name in sorted(os.listdir(folder))
                if file_name.endswith(".md") and not file_name.startswith("sent-")
            ]
            if not files:
                print("  (No new Markdown files found)")
                continue

            for file_name in files:
                full_path = os.path.join(folder, file_name)
                if create_task(
                    full_path,
                    agent_name=agent_name,
                    jules_repo=args.repo,
                    jules_branch=args.branch,
                    jules_source=args.jules_source,
                    jules_require_plan_approval=args.jules_require_plan_approval,
                    dry_run=args.dry_run,
                    archive=args.archive,
                ):
                    total_posted += 1

        print(f"\n✨ Done! Total tasks processed: {total_posted}")
        return 0

    if args.path:
        if not os.path.exists(args.path):
            print(f"❌ Error: Path '{args.path}' does not exist.")
            return 1

        if os.path.isfile(args.path):
            if args.path.endswith(".md"):
                return 0 if create_task(
                    args.path,
                    agent_name=agent_name,
                    jules_repo=args.repo,
                    jules_branch=args.branch,
                    jules_source=args.jules_source,
                    jules_require_plan_approval=args.jules_require_plan_approval,
                    dry_run=args.dry_run,
                    archive=args.archive,
                ) else 1
            print(f"⚠️ Warning: '{args.path}' is not a Markdown file. Skipping.")
            return 1

        if os.path.isdir(args.path):
            print(f"📂 Processing folder: {args.path}")
            files = [
                file_name
                for file_name in sorted(os.listdir(args.path))
                if file_name.endswith(".md") and not file_name.startswith("sent-")
            ]
            if not files:
                print(f"ℹ️ No new Markdown files found in '{args.path}'.")
            for file_name in files:
                full_path = os.path.join(args.path, file_name)
                create_task(
                    full_path,
                    agent_name=agent_name,
                    jules_repo=args.repo,
                    jules_branch=args.branch,
                    jules_source=args.jules_source,
                    jules_require_plan_approval=args.jules_require_plan_approval,
                    dry_run=args.dry_run,
                    archive=args.archive,
                )
            return 0

    parser.print_help()
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
