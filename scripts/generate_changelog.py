#!/usr/bin/env python3
import subprocess
import sys
from datetime import date

def get_commits(since_tag=None):
    if since_tag:
        cmd = ["git", "log", f"{since_tag}..HEAD", "--oneline", "--format=%s"]
    else:
        cmd = ["git", "log", "--oneline", "--format=%s"]

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        return result.stdout.strip().split('\n')
    except subprocess.CalledProcessError:
        return []

def get_latest_tag():
    try:
        result = subprocess.run(["git", "describe", "--tags", "--abbrev=0"], capture_output=True, text=True, check=True)
        return result.stdout.strip()
    except subprocess.CalledProcessError:
        return None

def parse_commits(commits):
    categories = {
        "Added": [],
        "Fixed": [],
        "Changed": [],
        "Removed": [],
        "Security": [],
    }

    for msg in commits:
        if not msg: continue

        if msg.startswith('feat'):
            categories["Added"].append(msg)
        elif msg.startswith('fix'):
            categories["Fixed"].append(msg)
        elif msg.startswith('chore') or msg.startswith('refactor') or msg.startswith('style'):
            categories["Changed"].append(msg)
        elif msg.startswith('docs'):
            categories["Changed"].append(msg)
        else:
            # Default category
            categories["Changed"].append(msg)

    return categories

def format_changelog(version, categories):
    today = date.today().isoformat()
    lines = [f"## [{version}] - {today}", ""]

    empty = True
    for cat, items in categories.items():
        if items:
            empty = False
            lines.append(f"### {cat}")
            lines.append("")
            for item in items:
                # Clean up conventional commit prefix if needed
                lines.append(f"- {item}")
            lines.append("")

    if empty:
        lines.append("No notable changes.")
        lines.append("")

    return "\n".join(lines)

def update_changelog_file(filepath, new_section):
    if not os.path.exists(filepath):
        # Create new if doesn't exist
        with open(filepath, 'w') as f:
            f.write("# Changelog\n\nAll notable changes to this project will be documented in this file.\n\n")
            f.write(new_section)
            f.write("\n")
        return

    with open(filepath, 'r') as f:
        content = f.read()

    # Insert after the header
    header_end = content.find('\n\n')
    if header_end == -1:
         header_end = 0
    else:
         header_end += 2

    # Check if version already exists to avoid duplicates
    version_header = new_section.split('\n')[0]
    if version_header in content:
        print(f"Version {version_header} already in {filepath}, skipping update.")
        return

    updated_content = content[:header_end] + new_section + "\n" + content[header_end:]
    with open(filepath, 'w') as f:
        f.write(updated_content)

import os

def main():
    if len(sys.argv) < 2:
        print("Usage: generate_changelog.py <version> [repo_path]")
        sys.exit(1)

    version = sys.argv[1]
    repo_path = sys.argv[2] if len(sys.argv) > 2 else "."

    os.chdir(repo_path)

    latest_tag = get_latest_tag()
    commits = get_commits(latest_tag)
    categories = parse_commits(commits)
    new_section = format_changelog(version, categories)

    update_changelog_file("CHANGELOG.md", new_section)
    print(f"Updated CHANGELOG.md in {repo_path}")

if __name__ == "__main__":
    main()
