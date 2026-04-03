#!/usr/bin/env python3
import os
import subprocess
import sys
import argparse

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

def trigger_jules(repo_path, prompt, branch, pr_title_prefix="Batch Script"):
    """Checkouts the branch and triggers a Jules session."""
    original_dir = os.getcwd()
    try:
        os.chdir(repo_path)
        repo_name = os.path.basename(repo_path) if repo_path != original_dir else "(root)"
        
        print(f"\n--- Processing: {repo_name} ---")
        
        # 1. Checkout branch
        print(f"  Checking out '{branch}'...")
        result = subprocess.run(["git", "checkout", branch], capture_output=True, text=True)
        if result.returncode != 0:
            print(f"  [SKIP] Could not checkout '{branch}' in {repo_name}. Does it exist?")
            return None

        # 2. Prepare the prompt for Jules
        # We explicitly instruct Jules to open a PR with the required title.
        full_prompt = (
            f"{prompt}\n\n"
            f"Requirement: When you are finished, open a Pull Request. "
            f"The PR title MUST include the prefix: '{pr_title_prefix}'."
        )

        # 3. Trigger Jules session
        print(f"  Triggering Jules session...")
        # Use jules new "prompt"
        # We use Popen to run in background if we want true parallelism, 
        # but jules new is usually a single submission call.
        cmd = ["jules", "new", full_prompt]
        process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        
        # We don't wait for completion here to allow parallelism, 
        # but we might want to capture the session ID if possible.
        # For now, let's just let it run.
        return process

    except Exception as e:
        print(f"  [ERROR] Failed to process {repo_path}: {e}")
        return None
    finally:
        os.chdir(original_dir)

def main():
    parser = argparse.ArgumentParser(description="Batch trigger Jules sessions across all repos.")
    parser.add_argument("--branch", default="dev", help="Starting branch (default: dev)")
    parser.add_argument("--prompt", help="The prompt/task for Jules")
    parser.add_argument("--title-prefix", default="Batch Script", help="Prefix for the PR title")
    
    args = parser.parse_args()

    # Get repos
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

    processes = []
    for repo in repos:
        proc = trigger_jules(repo, prompt, branch, args.title_prefix)
        if proc:
            processes.append(proc)

    # Wait for all 'jules new' submissions to finish (these are just task submissions)
    print("\nWaiting for all tasks to be submitted...")
    for proc in processes:
        stdout, stderr = proc.communicate()
        if proc.returncode == 0:
            # Try to extract session info from stdout if any
            output_lines = stdout.strip().splitlines()
            if output_lines:
                print(f"  Successfully submitted: {output_lines[-1]}")
            else:
                print(f"  Successfully submitted task")
        else:
            print(f"  Submission failed: {stderr.strip()}")

    print("\nAll tasks submitted to Jules! Monitor progress using 'jules remote list --session'.")

if __name__ == "__main__":
    main()
