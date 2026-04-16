import os
import requests
import argparse

import sys
from dotenv import load_dotenv

# --- ENVIRONMENT CONFIGURATION ---
# Load .env from the script's directory
script_dir = os.path.dirname(os.path.abspath(__file__))
env_path = os.path.join(script_dir, ".env")
load_dotenv(env_path)

SERVER_URL = os.getenv("MISSION_CONTROL_SERVER_URL")
API_KEY = os.getenv("MISSION_CONTROL_API_KEY")
PROJECT_NAME = os.getenv("MISSION_CONTROL_PROJECT_NAME", "NTMK")

if not SERVER_URL or not API_KEY:
    print("❌ Error: MISSION_CONTROL_SERVER_URL or MISSION_CONTROL_API_KEY not found in scripts/.env")
    print("Please check your .env file in the 'scripts' directory.")
    sys.exit(1)

HEADERS = {
    "Content-Type": "application/json",
    "x-api-key": API_KEY
}

def parse_markdown(file_path):
    """Reads the markdown file and intelligently extracts a title and description."""
    with open(file_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    if not lines:
        raise ValueError("The markdown file is empty.")

    # If the first line is an H1 tag, use it as the title
    if lines[0].startswith("# "):
        title = lines[0].replace("# ", "").strip()
        description = "".join(lines[1:]).strip()
    else:
        # Fallback: use the filename (without extension) as the title
        title = os.path.splitext(os.path.basename(file_path))[0]
        description = "".join(lines).strip()
        
    return title, description

def create_task(file_path, agent_id=None, dry_run=False, archive=False):
    """Parses a markdown file and pushes it to Mission Control."""
    print(f"📄 Reading '{file_path}'...")
    
    try:
        title, description = parse_markdown(file_path)
    except Exception as e:
        print(f"❌ Failed to read file: {e}")
        return False

    if dry_run:
        print(f"🔍 [DRY RUN] Would create task: '{title}' in project [{PROJECT_NAME}]")
        return True

    # Construct the Mission Control Task Payload
    payload = {
        "title": title,
        "description": description,
        "project": PROJECT_NAME,
        "status": "inbox" # Drop it into the 'inbox' column to be picked up by the daemon
    }
    
    # Optionally assign it directly to a specific agent's queue
    if agent_id:
        payload["assigned_to"] = agent_id

    print(f"🚀 Pushing task '{title}' to project [{PROJECT_NAME}]...")
    
    try:
        res = requests.post(f"{SERVER_URL}/api/tasks", headers=HEADERS, json=payload)
        res.raise_for_status() # Catch HTTP errors
        
        task_data = res.json()
        print(f"✅ Success! Task added with ID: {task_data.get('id', 'Unknown')}")
        
        if archive:
            directory = os.path.dirname(file_path)
            filename = os.path.basename(file_path)
            new_path = os.path.join(directory, f"sent-{filename}")
            try:
                os.rename(file_path, new_path)
                print(f"📦 Archived: {filename} -> sent-{filename}")
            except Exception as e:
                print(f"⚠️ Failed to archive {filename}: {e}")
                
        return True
    except requests.exceptions.RequestException as e:
        print(f"❌ Failed to create task: {e}")
        if hasattr(e, 'response') and e.response is not None:
            print(f"Server response: {e.response.text}")
        return False

def scan_workspace_for_issues():
    """Finds all 'issues' directories in the project root and subdirectories."""
    # Start scanning from the repository root (two levels up from scripts/)
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    print(f"🔍 Scanning workspace root: {repo_root}")
    
    issues_folders = []
    for root, dirs, files in os.walk(repo_root):
        # Skip hidden directories like .git
        dirs[:] = [d for d in dirs if not d.startswith('.')]
        
        if 'issues' in dirs:
            issues_folders.append(os.path.join(root, 'issues'))
            
    return sorted(issues_folders)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Push MD files as tasks to Mission Control.")
    parser.add_argument("path", nargs="?", help="Path to the markdown file or directory")
    parser.add_argument("--all", action="store_true", help="Scan the entire workspace for 'issues' folders")
    parser.add_argument("--agent", help="Optional: Agent ID to directly assign the task to", default=None)
    parser.add_argument("--dry-run", action="store_true", help="Preview tasks without sending them")
    parser.add_argument("--archive", action="store_true", help="Rename files to 'sent-...' after successful posting")
    
    args = parser.parse_args()
    
    if args.all:
        folders = scan_workspace_for_issues()
        if not folders:
            print("ℹ️ No 'issues' folders found in workspace.")
            sys.exit(0)
            
        print(f"📂 Found {len(folders)} issues folders. Processing...")
        total_posted = 0
        for folder in folders:
            # Skip the root scripts/test_tasks if it's there? No, process all 'issues' folders.
            print(f"\n📁 Folder: {os.path.relpath(folder)}")
            files = [f for f in sorted(os.listdir(folder)) if f.endswith(".md") and not f.startswith("sent-")]
            if not files:
                print("  (No new markdown files found)")
                continue
                
            for filename in files:
                full_path = os.path.join(folder, filename)
                if create_task(full_path, args.agent, dry_run=args.dry_run, archive=args.archive):
                    total_posted += 1
        
        print(f"\n✨ Done! Total tasks processed: {total_posted}")

    elif args.path:
        if not os.path.exists(args.path):
            print(f"❌ Error: Path '{args.path}' does not exist.")
        elif os.path.isfile(args.path):
            if args.path.endswith(".md"):
                create_task(args.path, args.agent, dry_run=args.dry_run, archive=args.archive)
            else:
                print(f"⚠️ Warning: '{args.path}' is not a markdown file. Skipping.")
        elif os.path.isdir(args.path):
            print(f"📂 Processing folder: {args.path}")
            # Find all markdown files in the directory (skipping already sent ones)
            files = [f for f in sorted(os.listdir(args.path)) if f.endswith(".md") and not f.startswith("sent-")]
            if not files:
                print(f"ℹ️ No new markdown files found in '{args.path}'.")
            for filename in files:
                full_path = os.path.join(args.path, filename)
                create_task(full_path, args.agent, dry_run=args.dry_run, archive=args.archive)
    else:
        parser.print_help()
        sys.exit(1)
