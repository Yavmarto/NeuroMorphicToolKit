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
    """Returns a list of all repository paths (submodules + root)."""
    try:
        # Get submodules
        output = subprocess.check_output(
            ["git", "submodule", "foreach", "--quiet", "echo $displaypath"],
            text=True
        ).strip()
        submodules = [line.strip() for line in output.split("\n") if line.strip()]
        
        # Absolute paths
        root_dir = os.getcwd()
        repo_paths = [os.path.join(root_dir, sub) for sub in submodules]
        repo_paths.append(root_dir) # Add root
        
        return repo_paths
    except subprocess.CalledProcessError:
        print("Error: Could not list submodules. Are you in a git repository?")
        return [os.getcwd()]

def get_repo_identifier(repo_path):
    """Extracts 'owner/repo' from git remote origin."""
    try:
        os.chdir(repo_path)
        url = subprocess.check_output(
            ["git", "remote", "get-url", "origin"], 
            text=True, stderr=subprocess.DEVNULL
        ).strip()
        
        # Match common git URL formats
        # git@github.com:owner/repo.git
        # https://github.com/owner/repo.git
        match = re.search(r"[:/]([^/:]+/[^/.]+)(\.git)?$", url)
        if match:
            id_str = match.group(1)
            # Normalize owner: Yavmarto -> Completed-Spoon-6
            id_str = id_str.replace("Yavmarto/", "Completed-Spoon-6/")
            
            # Normalize repo name capitalization (e.g. neurocnl -> Neurocnl)
            if "/" in id_str:
                owner, repo = id_str.split("/", 1)
                if repo.lower().startswith("neuro"):
                    repo = repo.capitalize()  # neurocnl -> Neurocnl, neurochip -> Neurochip
                id_str = f"{owner}/{repo}"
            
            return id_str
        return None
    except Exception:
        return None
    finally:
        os.chdir(os.getcwd())

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
    """Triggers a Jules session via the correct API structure."""
    repo_id = get_repo_identifier(repo_path)
    if not repo_id:
        return f"[SKIP] Could not determine repository identifier for {repo_path}"

    # Try to find the matching source name
    source_name = source_map.get(repo_id) or source_map.get(f"github/{repo_id}")
    if not source_name:
        return f"❌ FAILED: No Jules source found for {repo_id}. Use 'jules remote list --repo' to verify."

    original_dir = os.getcwd()
    try:
        os.chdir(repo_path)
        
        # 1. Checkout branch
        # Stash current changes to avoid conflicts during checkout
        has_changes = subprocess.run(["git", "status", "--porcelain"], capture_output=True, text=True).stdout.strip()
        if has_changes:
            subprocess.run(["git", "stash", "push", "-m", "jules_batch_prompt_auto_stash"], capture_output=True)

        # Try to checkout the branch (existing or new from remote)
        result = subprocess.run(["git", "checkout", branch], capture_output=True, text=True)
        if result.returncode != 0:
            # If standard checkout fails, try creating it from origin
            result = subprocess.run(["git", "checkout", "-b", branch, f"origin/{branch}"], capture_output=True, text=True)
            if result.returncode != 0:
                # If both fail, report the error correctly
                error_msg = result.stderr.strip()
                return f"[SKIP] Could not checkout '{branch}' in {repo_id} ({error_msg})"

        # 2. Prepare payload
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

        # 3. POST to /sessions
        response = requests.post(f"{BASE_URL}/sessions", headers=headers, json=payload)
        
        if response.status_code == 200:
            data = response.json()
            session_name = data.get("name", "Unknown Session")
            return f"✅ SUCCESS: {repo_id} -> {session_name}"
        else:
            return f"❌ FAILED: {repo_id} (Status {response.status_code}): {response.text}"

    except Exception as e:
        return f"❌ ERROR: Processing {repo_path}: {e}"
    finally:
        os.chdir(original_dir)

def main():
    if not API_KEY:
        print("Error: JULES_API_KEY not found in scripts/.env")
        sys.exit(1)

    parser = argparse.ArgumentParser(description="Batch trigger Jules sessions across all repos via API (Corrected).")
    parser.add_argument("--branch", default="dev", help="Starting branch (default: dev)")
    parser.add_argument("--prompt", help="The prompt/task for Jules")
    parser.add_argument("--title-prefix", default="Batch Script", help="Prefix for the PR title")
    
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

    # Prompt if not provided
    prompt = args.prompt
    if not prompt:
        prompt = input("Enter the task for Jules: ").strip()
    
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
