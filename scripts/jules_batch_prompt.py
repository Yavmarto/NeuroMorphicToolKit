#!/usr/bin/env python3
import os
import subprocess
import sys
import argparse
import requests
import re
from concurrent.futures import ThreadPoolExecutor
from dotenv import load_dotenv

# Search for .env in the script's directory
script_dir = os.path.dirname(os.path.abspath(__file__))
env_path = os.path.join(script_dir, ".env")
load_dotenv(env_path)

API_KEY = os.getenv("JULES_API_KEY")
BASE_URL = "https://jules.googleapis.com/v1alpha"

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

def fetch_sources(api_key):
    """Fetches all Jules sources and returns a mapping from repo identifier to source name."""
    headers = {"x-goog-api-key": api_key}
    try:
        response = requests.get(f"{BASE_URL}/sources", headers=headers)
        response.raise_for_status()
        sources_data = response.json()
        
        mapping = {}
        for source in sources_data.get("sources", []):
            # Extract identifer from the source id or githubRepo owner/repo
            mapping[source.get("id", "")] = source.get("name")
            # Also map owner/repo if available
            gh = source.get("githubRepo", {})
            if gh:
                identifier = f"{gh.get('owner')}/{gh.get('repo')}"
                mapping[identifier] = source.get("name")
                # Also handle with 'github/' prefix if provided in ID
                mapping[f"github/{identifier}"] = source.get("name")
        
        return mapping
    except Exception as e:
        print(f"Error fetching sources: {e}")
        return {}

def trigger_jules_api(repo_path, prompt, branch, source_map, pr_title_prefix="Batch Script"):
    """Triggers a Jules session via the API. Thread-safe: uses git -C instead of os.chdir."""
    repo_id = get_repo_identifier(repo_path)
    if not repo_id:
        return f"[SKIP] Could not determine repository identifier for {repo_path}"

    # Match against Jules source map
    source_name = source_map.get(repo_id) or source_map.get(f"github/{repo_id}")
    if not source_name:
        return f"❌ FAILED: No Jules source found for {repo_id}. Use 'jules remote list --repo' to verify."

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

def main():
    if not API_KEY:
        print("Error: JULES_API_KEY not found in scripts/.env")
        sys.exit(1)

    parser = argparse.ArgumentParser(
        description="Batch trigger Jules sessions across all repos via the Jules API.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python3 scripts/jules_batch_prompt.py --prompt \"Fix all linting errors\"
  python3 scripts/jules_batch_prompt.py --task-file tasks/audit.md
  python3 scripts/jules_batch_prompt.py --task-file tasks/audit.md --branch main --title-prefix \"Audit\"
        """
    )
    parser.add_argument("--branch", default="dev", help="Starting branch (default: dev)")
    parser.add_argument("--prompt", help="Inline prompt/task text for Jules")
    parser.add_argument("--task-file", metavar="FILE", help="Path to a .md file whose contents are used as the prompt")
    parser.add_argument("--title-prefix", default="Batch Script", help="Prefix for the PR title (default: 'Batch Script')")
    
    args = parser.parse_args()

    # 1. Fetch source mapping
    print("Fetching Jules source mapping...")
    source_map = fetch_sources(API_KEY)
    if not source_map:
        print("Error: Could not retrieve source mapping from Jules API.")
        sys.exit(1)

    # 2. Get repos
    repos = get_repos()
    print(f"Found {len(repos)} repositories (including root).")

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

    branch = args.branch
    print(f"Target branch: {branch}")
    print(f"PR Title Prefix: {args.title_prefix}")
    print("\nTriggering sessions in parallel...")

    results = []
    with ThreadPoolExecutor(max_workers=10) as executor:
        futures = [executor.submit(trigger_jules_api, repo, prompt, branch, source_map, args.title_prefix) for repo in repos]
        for future in futures:
            results.append(future.result())

    print("\n--- Summary Results ---")
    for res in results:
        print(res)

    print("\nMonitor progress using 'jules remote list --session'.")

if __name__ == "__main__":
    main()
