#!/usr/bin/env python3
import os
import re
import sys


def bump_pyproject(filepath, version):
    with open(filepath, "r") as f:
        content = f.read()

    # Update project.version = "..."
    new_content = re.sub(
        r'(^version\s*=\s*)"[^"]+"', rf'\1"{version}"', content, flags=re.MULTILINE
    )

    # Also handle some projects that might use [project] section
    if "version =" not in new_content:
        new_content = re.sub(
            r'(\[project\]\n(?:.*\n)*?version\s*=\s*)"[^"]+"',
            rf'\1"{version}"',
            content,
            flags=re.MULTILINE,
        )

    with open(filepath, "w") as f:
        f.write(new_content)
    print(f"Updated {filepath} to version {version}")


def bump_pubspec(filepath, version):
    with open(filepath, "r") as f:
        content = f.read()

    # Flutter version is usually x.y.z+build
    # If version doesn't have +, we increment existing build count or default to 1
    if "+" not in version:
        match = re.search(
            r"^version:\s*([0-9.]+)\+([0-9]+)", content, flags=re.MULTILINE
        )
        if match:
            build = int(match.group(2)) + 1
            version = f"{version}+{build}"
        else:
            version = f"{version}+1"

    new_content = re.search(r"^version:.*", content, flags=re.MULTILINE)
    if new_content:
        new_content = re.sub(
            r"^version:.*", f"version: {version}", content, flags=re.MULTILINE
        )
    else:
        # Fallback if version: not found at start of line
        new_content = re.sub(r"version:.*", f"version: {version}", content)

    with open(filepath, "w") as f:
        f.write(new_content)
    print(f"Updated {filepath} to version {version}")


def main():
    if len(sys.argv) < 3:
        print("Usage: bump_version.py <version> <file1> [file2...]")
        sys.exit(1)

    version = sys.argv[1]
    files = sys.argv[2:]

    for filepath in files:
        if not os.path.exists(filepath):
            print(f"Warning: File not found: {filepath}")
            continue

        if filepath.endswith("pyproject.toml"):
            bump_pyproject(filepath, version)
        elif filepath.endswith("pubspec.yaml"):
            bump_pubspec(filepath, version)
        else:
            print(f"Warning: Unsupported file type: {filepath}")


if __name__ == "__main__":
    main()
