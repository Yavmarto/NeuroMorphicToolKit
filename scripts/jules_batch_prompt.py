#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any

from dotenv import load_dotenv

try:
    from scripts.jules_api import JulesClient, JulesApiError, get_repo_identifier
except ImportError:
    from jules_api import JulesClient, JulesApiError, get_repo_identifier


SCRIPT_DIR = Path(__file__).resolve().parent
ENV_PATH = SCRIPT_DIR / ".env"
load_dotenv(ENV_PATH)

API_KEY = os.getenv("JULES_API_KEY")
API_KEY_F = os.getenv("JULES_API_KEY_F")
MAX_SESSIONS_PER_ACCOUNT = 15


def get_repos() -> list[str]:
    """Returns all valid repository paths (submodules with URLs plus the root repo)."""
    root_dir = os.getcwd()
    repo_paths: list[str] = []

<<<<<<< Updated upstream
    try:
        paths_output = subprocess.check_output(
            ["git", "config", "--file", ".gitmodules", "--get-regexp", r"submodule\..*\.path"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()

        for line in paths_output.splitlines():
            parts = line.split()
            if len(parts) != 2:
                continue
            key, sub_path = parts
            sub_name = key.split(".")[1]

            url_check = subprocess.run(
                ["git", "config", "--file", ".gitmodules", f"submodule.{sub_name}.url"],
                capture_output=True,
                text=True,
            )
            if url_check.returncode != 0 or not url_check.stdout.strip():
                print(f"  [SKIP] Submodule '{sub_path}' has no URL in .gitmodules — skipping.")
                continue

            full_path = os.path.join(root_dir, sub_path)
            if os.path.isdir(full_path):
                repo_paths.append(full_path)
            else:
                print(f"  [SKIP] Submodule path '{sub_path}' does not exist locally — skipping.")

    except subprocess.CalledProcessError:
        print("  [WARN] Could not read .gitmodules — only the root repo will be used.")

    repo_paths.append(root_dir)
    return repo_paths
=======
def get_repos():
    """Returns a list of all valid repository paths (submodules with URLs + root)."""
    root_dir = os.getcwd()
    repo_paths = []

    try:
        # Parse submodule paths directly from .gitmodules via git config.
        # This avoids 'git submodule foreach' which aborts on broken entries (e.g. NeuroDash).
        paths_output = subprocess.check_output(
            ["git", "config", "--file", ".gitmodules", "--get-regexp", r"submodule\..*\.path"],
            text=True, stderr=subprocess.DEVNULL
        ).strip()

        for line in paths_output.splitlines():
            # line format: submodule.<name>.path <path>
            parts = line.split()
            if len(parts) != 2:
                continue
            key, sub_path = parts
            sub_name = key.split(".")[1]

            # Skip submodules with no URL registered
            url_check = subprocess.run(
                ["git", "config", "--file", ".gitmodules", f"submodule.{sub_name}.url"],
                capture_output=True, text=True
            )
            if url_check.returncode != 0 or not url_check.stdout.strip():
                print(f"  [SKIP] Submodule '{sub_path}' has no URL in .gitmodules — skipping.")
                continue

            full_path = os.path.join(root_dir, sub_path)
            if os.path.isdir(full_path):
                repo_paths.append(full_path)
            else:
                print(f"  [SKIP] Submodule path '{sub_path}' does not exist locally — skipping.")

    except subprocess.CalledProcessError:
        print("  [WARN] Could not read .gitmodules — only the root repo will be used.")

    repo_paths.append(root_dir)  # Always include root last
    return repo_paths

def get_repo_identifier(repo_path):
    """Extracts 'owner/repo' from git remote origin — thread-safe, no chdir."""
    try:
        url = subprocess.check_output(
            ["git", "-C", repo_path, "remote", "get-url", "origin"],
            text=True, stderr=subprocess.DEVNULL
        ).strip()

        # Match common git URL formats:
        #   git@github.com:owner/repo.git
        #   https://github.com/owner/repo.git
        match = re.search(r"[:/]([^/:]+/[^/.]+)(\.git)?$", url)
        if not match:
            return None

        id_str = match.group(1)

        # Normalize owner alias: Yavmarto mirrors -> Completed-Spoon-6
        id_str = id_str.replace("Yavmarto/", "Completed-Spoon-6/")

        # Normalize repo name: only uppercase the first character if it starts
        # with 'neuro' (case-insensitive), preserving all other original casing.
        # e.g. neurocnl -> Neurocnl,  NeuroMorphicToolKit stays NeuroMorphicToolKit
        if "/" in id_str:
            owner, repo = id_str.split("/", 1)
            if repo.lower().startswith("neuro") and repo[0].islower():
                repo = repo[0].upper() + repo[1:]  # only flip first char
            id_str = f"{owner}/{repo}"

        return id_str
    except Exception:
        return None
>>>>>>> Stashed changes


def fetch_sources(api_key: str) -> dict[str, str]:
    client = JulesClient(api_key)
    try:
        return client.build_source_map()
    except JulesApiError as exc:
        print(f"Error fetching sources: {exc}")
        return {}
    finally:
        client.close()

<<<<<<< Updated upstream

def reserve_api_key(session_counter: list[int], counter_lock: Any) -> tuple[str | None, str | None]:
    with counter_lock:
        current_count = session_counter[0]
        if current_count < MAX_SESSIONS_PER_ACCOUNT:
            session_counter[0] += 1
            return API_KEY, "A"
        if API_KEY_F:
            return API_KEY_F, "F"
    return None, None


def release_api_key(account_label: str | None, session_counter: list[int], counter_lock: Any) -> None:
    if account_label != "A":
        return
    with counter_lock:
        session_counter[0] = max(session_counter[0] - 1, 0)


def create_jules_session(
    *,
    api_key: str,
    title: str,
    prompt: str,
    source_name: str,
    branch: str,
) -> dict[str, Any]:
    client = JulesClient(api_key)
    try:
        return client.create_session(
            title=title,
            prompt=prompt,
            source_name=source_name,
            branch=branch,
            automation_mode="AUTO_CREATE_PR",
        )
    finally:
        client.close()


def send_issues_for_repo(
    repo_path: str,
    branch: str,
    source_map: dict[str, str],
    pr_title_prefix: str,
    session_counter: list[int],
    counter_lock: Any,
) -> list[str]:
    repo_id = get_repo_identifier(repo_path)
    if not repo_id:
        return [f"[SKIP] Could not identify repo at {repo_path}"]

    source_name = source_map.get(repo_id) or source_map.get(f"github/{repo_id}")
    if not source_name:
        return [f"❌ FAILED: No Jules source found for {repo_id}"]

    issues_dir = os.path.join(repo_path, "issues")
    if not os.path.isdir(issues_dir):
        return [f"[SKIP] No issues/ folder in {repo_id}"]

    md_files = sorted(
        file_name
        for file_name in os.listdir(issues_dir)
        if file_name.endswith(".md") and not file_name.startswith("sent-")
    )
    if not md_files:
        return [f"[SKIP] No unsent issues in {repo_id}/issues/"]

    archive_dir = os.path.join(repo_path, "issues-archive")
    os.makedirs(archive_dir, exist_ok=True)

    results: list[str] = []
    for filename in md_files:
        filepath = os.path.join(issues_dir, filename)
        with open(filepath, "r", encoding="utf-8") as handle:
            content = handle.read().strip()

        if not content:
            results.append(f"[SKIP] {repo_id}/issues/{filename} is empty")
            continue

        active_key, account_label = reserve_api_key(session_counter, counter_lock)
        if not active_key or not account_label:
            results.append(
                f"❌ SKIPPED: {repo_id}/issues/{filename} — "
                f"account A is full ({MAX_SESSIONS_PER_ACCOUNT} sessions) and no account F key set."
            )
            continue

        full_prompt = (
            f"{content}\n\n"
            f"Requirement: The PR title MUST include the prefix: '{pr_title_prefix}'."
        )
        try:
            session_payload = create_jules_session(
                api_key=active_key,
                title=f"Issue: {os.path.splitext(filename)[0][:60]}",
                prompt=full_prompt,
                source_name=source_name,
                branch=branch,
            )
            session_name = session_payload.get("name", "Unknown Session")
            archive_path = os.path.join(archive_dir, f"sent-{filename}")
            os.rename(filepath, archive_path)
            results.append(
                f"✅ SENT [{account_label}]: {repo_id}/issues/{filename} → {session_name}"
            )
        except Exception as exc:
            release_api_key(account_label, session_counter, counter_lock)
            results.append(f"❌ ERROR: {repo_id}/issues/{filename}: {exc}")

    return results


def trigger_jules_api(
    repo_path: str,
    prompt: str,
    branch: str,
    source_map: dict[str, str],
    pr_title_prefix: str,
    session_counter: list[int],
    counter_lock: Any,
) -> str:
=======
def trigger_jules_api(repo_path, prompt, branch, source_map, pr_title_prefix="Batch Script"):
    """Triggers a Jules session via the API. Thread-safe: uses git -C instead of os.chdir."""
>>>>>>> Stashed changes
    repo_id = get_repo_identifier(repo_path)
    if not repo_id:
        return f"[SKIP] Could not determine repository identifier for {repo_path}"

<<<<<<< Updated upstream
=======
    # Match against Jules source map
>>>>>>> Stashed changes
    source_name = source_map.get(repo_id) or source_map.get(f"github/{repo_id}")
    if not source_name:
        return f"❌ FAILED: No Jules source found for {repo_id}. Use 'jules remote list --repo' to verify."

<<<<<<< Updated upstream
    active_key, account_label = reserve_api_key(session_counter, counter_lock)
    if not active_key or not account_label:
        return (
            f"❌ SKIPPED: {repo_id} — "
            f"account A is full ({MAX_SESSIONS_PER_ACCOUNT} sessions) and no account F key set."
        )

    status = subprocess.run(
        ["git", "-C", repo_path, "status", "--porcelain"],
        capture_output=True,
        text=True,
    ).stdout.strip()
    if status:
        subprocess.run(
            ["git", "-C", repo_path, "stash", "push", "-m", "jules_batch_prompt_auto_stash"],
            capture_output=True,
        )

    result = subprocess.run(
        ["git", "-C", repo_path, "checkout", branch],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        result = subprocess.run(
            ["git", "-C", repo_path, "checkout", "-b", branch, f"origin/{branch}"],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            release_api_key(account_label, session_counter, counter_lock)
            error_msg = (result.stderr or result.stdout).strip()
            return f"[SKIP] Could not checkout '{branch}' in {repo_id} ({error_msg})"

    full_prompt = (
        f"{prompt}\n\n"
        f"Requirement: The PR title MUST include the prefix: '{pr_title_prefix}'."
    )
    try:
        session_payload = create_jules_session(
            api_key=active_key,
            title=f"Batch: {prompt[:50]}...",
            prompt=full_prompt,
            source_name=source_name,
            branch=branch,
        )
        session_name = session_payload.get("name", "Unknown Session")
        return f"✅ SUCCESS [{account_label}]: {repo_id} -> {session_name}"
    except Exception as exc:
        release_api_key(account_label, session_counter, counter_lock)
        return f"❌ ERROR: {repo_id}: {exc}"
=======
    # ── 1. Checkout branch (thread-safe via git -C) ──────────────────────────
    # Stash uncommitted changes so checkout doesn't fail
    status = subprocess.run(
        ["git", "-C", repo_path, "status", "--porcelain"],
        capture_output=True, text=True
    ).stdout.strip()
    if status:
        subprocess.run(
            ["git", "-C", repo_path, "stash", "push", "-m", "jules_batch_prompt_auto_stash"],
            capture_output=True
        )

    # Try plain checkout first (branch already exists locally)
    result = subprocess.run(
        ["git", "-C", repo_path, "checkout", branch],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        # Branch may only exist on remote — try to create from origin
        result = subprocess.run(
            ["git", "-C", repo_path, "checkout", "-b", branch, f"origin/{branch}"],
            capture_output=True, text=True
        )
        if result.returncode != 0:
            error_msg = (result.stderr or result.stdout).strip()
            return f"[SKIP] Could not checkout '{branch}' in {repo_id} ({error_msg})"

    # ── 2. Build payload ─────────────────────────────────────────────────────
    full_prompt = (
        f"{prompt}\n\n"
        f"Requirement: The PR title MUST include the prefix: '{pr_title_prefix}'."
    )

    headers = {"x-goog-api-key": API_KEY}
    payload = {
        "title": f"Batch: {prompt[:50]}...",
        "prompt": full_prompt,
        "sourceContext": {
            "source": source_name,
            "githubRepoContext": {
                "startingBranch": branch
            }
        },
        "automationMode": "AUTO_CREATE_PR"
        }

    # ── 3. POST to /sessions ──────────────────────────────────────────────────
    try:
        response = requests.post(f"{BASE_URL}/sessions", headers=headers, json=payload)
        if response.status_code == 200:
            session_name = response.json().get("name", "Unknown Session")
            return f"✅ SUCCESS: {repo_id} -> {session_name}"
        else:
            return f"❌ FAILED: {repo_id} (Status {response.status_code}): {response.text}"
    except Exception as e:
        return f"❌ ERROR: {repo_id}: {e}"
>>>>>>> Stashed changes


def main() -> None:
    if not API_KEY:
        print("Error: JULES_API_KEY not found in scripts/.env")
        sys.exit(1)

    parser = argparse.ArgumentParser(
        description="Batch trigger Jules sessions across all repos via the Jules API.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
<<<<<<< Updated upstream
  python3 scripts/jules_batch_prompt.py --prompt "Fix all linting errors"
  python3 scripts/jules_batch_prompt.py --task-file tasks/audit.md
  python3 scripts/jules_batch_prompt.py --task-file tasks/audit.md --branch main --title-prefix "Audit"
        """,
    )
    parser.add_argument("--branch", default="dev", help="Starting branch (default: dev)")
    parser.add_argument("--prompt", help="Inline prompt/task text for Jules")
    parser.add_argument(
        "--task-file",
        metavar="FILE",
        help="Path to a .md file whose contents are used as the prompt",
    )
    parser.add_argument(
        "--send-issues",
        action="store_true",
        help="Scan each repo's issues/ folder and send each .md as a Jules session; renames sent files to 'sent-<name>.md'",
    )
    parser.add_argument(
        "--title-prefix",
        default="Batch Script",
        help="Prefix for the PR title (default: 'Batch Script')",
    )

=======
  python3 scripts/jules_batch_prompt.py --prompt \"Fix all linting errors\"
  python3 scripts/jules_batch_prompt.py --task-file tasks/audit.md
  python3 scripts/jules_batch_prompt.py --task-file tasks/audit.md --branch main --title-prefix \"Audit\"
        """
    )
    parser.add_argument("--branch", default="dev", help="Starting branch (default: dev)")
    parser.add_argument("--prompt", help="Inline prompt/task text for Jules")
    parser.add_argument("--task-file", metavar="FILE", help="Path to a .md file whose contents are used as the prompt")
    parser.add_argument("--title-prefix", default="Batch Script", help="Prefix for the PR title (default: 'Batch Script')")
    
>>>>>>> Stashed changes
    args = parser.parse_args()

    print("Fetching Jules source mapping...")
    source_map = fetch_sources(API_KEY)
    if not source_map:
        print("Error: Could not retrieve source mapping from Jules API.")
        sys.exit(1)

    repos = get_repos()
    print(f"Found {len(repos)} repositories (including root).")

<<<<<<< Updated upstream
    prompt: str | None = None
    if not args.send_issues:
        if args.task_file:
            task_path = os.path.abspath(args.task_file)
            if not os.path.isfile(task_path):
                print(f"Error: Task file not found: {task_path}")
                sys.exit(1)
            with open(task_path, "r", encoding="utf-8") as handle:
                prompt = handle.read().strip()
            print(f"Task loaded from: {task_path} ({len(prompt)} chars)")
        elif args.prompt:
            prompt = args.prompt.strip()
        else:
            try:
                prompt = input("Enter the task for Jules (or Ctrl+C to abort): ").strip()
            except KeyboardInterrupt:
                print("\nAborted.")
                sys.exit(0)
=======
    # Resolve prompt: --task-file takes priority, then --prompt, then interactive input
    prompt = None

    if args.task_file:
        task_path = os.path.abspath(args.task_file)
        if not os.path.isfile(task_path):
            print(f"Error: Task file not found: {task_path}")
            sys.exit(1)
        with open(task_path, "r", encoding="utf-8") as f:
            prompt = f.read().strip()
        print(f"Task loaded from: {task_path} ({len(prompt)} chars)")
    elif args.prompt:
        prompt = args.prompt.strip()
    else:
        prompt = input("Enter the task for Jules (or Ctrl+C to abort): ").strip()

    if not prompt:
        print("Error: Prompt is required.")
        sys.exit(1)
>>>>>>> Stashed changes

        if not prompt:
            print("Error: Prompt is required for batch mode.")
            sys.exit(1)

    print(f"Target branch: {args.branch}")
    print(f"PR Title Prefix: {args.title_prefix}")

    import threading

    session_counter = [0]
    counter_lock = threading.Lock()

    if args.send_issues:
        print("\nMode: sending issues/ files to Jules in parallel...")
        all_results: list[str] = []
        with ThreadPoolExecutor(max_workers=10) as executor:
            futures = [
                executor.submit(
                    send_issues_for_repo,
                    repo,
                    args.branch,
                    source_map,
                    args.title_prefix,
                    session_counter,
                    counter_lock,
                )
                for repo in repos
            ]
            for future in futures:
                all_results.extend(future.result())

        print("\n--- Summary Results ---")
        for result in all_results:
            print(result)
        print("\nMonitor progress using 'jules remote list --session'.")
        return

    print("\nMode: sending batch prompt to everything in parallel...")
    results: list[str] = []
    with ThreadPoolExecutor(max_workers=10) as executor:
        futures = [
            executor.submit(
                trigger_jules_api,
                repo,
                prompt,
                args.branch,
                source_map,
                args.title_prefix,
                session_counter,
                counter_lock,
            )
            for repo in repos
        ]
        for future in futures:
            results.append(future.result())

    print("\n--- Summary Results ---")
    for result in results:
        print(result)
    print("\nMonitor progress using 'jules remote list --session'.")


if __name__ == "__main__":
    main()
