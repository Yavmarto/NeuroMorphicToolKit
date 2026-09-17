#!/usr/bin/env python3
import os
import subprocess
import sys


def find_files():
    """Find all pubspec.yaml and pyproject.toml files in the repository."""
    files = []
    # Identify the root directory (assuming script is in /scripts)
    root_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

    exclude_dirs = {".git", ".venv", "venv", "node_modules", "build", ".dart_tool", ".pytest_cache", ".ruff_cache", "__pycache__"}

    for root, dirs, filenames in os.walk(root_dir):
        # Filter directories in-place to prevent walking into excluded once
        dirs[:] = [d for d in dirs if not d.startswith(".") and d not in exclude_dirs]

        for filename in filenames:
            if filename in ("pubspec.yaml", "pyproject.toml"):
                files.append(os.path.relpath(os.path.join(root, filename), root_dir))
    return files

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 scripts/bump_all.py <version>")
        print("Example: python3 scripts/bump_all.py 1.2.3")
        sys.exit(1)

    version = sys.argv[1]

    # Basic semver check
    import re
    if not re.match(r"^\d+\.\d+\.\d+(-[a-zA-Z0-9.]+)?$", version):
        print(f"Error: '{version}' is not a valid semantic version (x.y.z).")
        sys.exit(1)

    files = find_files()

    if not files:
        print("No pubspec.yaml or pyproject.toml files found.")
        return

    print(f"🚀 Found {len(files)} files to bump to version {version}")

    script_dir = os.path.dirname(os.path.realpath(__file__))
    bump_script = os.path.join(script_dir, "bump_version.py")

    if not os.path.exists(bump_script):
        print(f"Error: Helper script not found at {bump_script}")
        sys.exit(1)

    # Change to root directory to run the bump script with relative paths
    os.chdir(os.path.abspath(os.path.join(script_dir, "..")))

    cmd = ["python3", "scripts/bump_version.py", version] + files
    try:
        subprocess.run(cmd, check=True)
        print(f"\n✅ Successfully bumped all versions to {version}")
    except subprocess.CalledProcessError as e:
        print(f"\n❌ Error during version bumping: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
