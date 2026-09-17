#!/usr/bin/env python3
"""Manage git stashes across root and all submodule repositories.

Lists stashes with timestamps and relative dates, and provides batch removal
capabilities via interactive selection or CLI flags.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
import re
import subprocess
import sys
import time
from typing import Sequence

# ANSI Colors
USE_COLOR = sys.stdout.isatty()


def _color(code: str, text: str) -> str:
    return f"\033[{code}m{text}\033[0m" if USE_COLOR else text


def cyan(text: str) -> str:
    return _color("36", text)


def green(text: str) -> str:
    return _color("32", text)


def yellow(text: str) -> str:
    return _color("33", text)


def red(text: str) -> str:
    return _color("31", text)


def bold(text: str) -> str:
    return _color("1", text)


def dim(text: str) -> str:
    return _color("2", text)


@dataclass
class StashEntry:
    item_id: int
    repo_name: str
    repo_dir: Path
    stash_ref: str
    stash_idx: int
    iso_date: str
    relative_date: str
    timestamp: int
    message: str


def find_git_root() -> Path:
    """Find the root of the current git repository."""
    try:
        out = subprocess.check_output(
            ["git", "rev-parse", "--show-toplevel"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
        return Path(out).resolve()
    except subprocess.CalledProcessError:
        print(red("Error: Not inside a git repository."), file=sys.stderr)
        sys.exit(1)


def discover_repos(root_dir: Path) -> list[tuple[str, Path]]:
    """Discover all managed git repositories (submodules + root)."""
    repos: list[tuple[str, Path]] = []

    # Check child directories that are git repositories (matching repo_helpers.sh)
    for child in sorted(root_dir.iterdir()):
        if not child.is_dir():
            continue
        try:
            top_level = subprocess.check_output(
                ["git", "-C", str(child), "rev-parse", "--show-toplevel"],
                text=True,
                stderr=subprocess.DEVNULL,
            ).strip()
            if Path(top_level).resolve() == child.resolve():
                repos.append((child.name, child))
        except (subprocess.CalledProcessError, FileNotFoundError):
            continue

    # Always include (root)
    repos.append(("(root)", root_dir))
    return repos


def get_stashes_for_repo(
    repo_name: str, repo_dir: Path, start_id: int
) -> list[StashEntry]:
    """Retrieve all stashes from a single repository."""
    entries: list[StashEntry] = []
    # %gd = stash@{N}, %ci = ISO date, %cr = relative date, %ct = timestamp, %gs = subject
    cmd = [
        "git",
        "-C",
        str(repo_dir),
        "stash",
        "list",
        "--format=%gd\x1f%ci\x1f%cr\x1f%ct\x1f%gs",
    ]
    try:
        output = subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL)
    except subprocess.CalledProcessError:
        return entries

    curr_id = start_id
    for line in output.strip().splitlines():
        if not line:
            continue
        parts = line.split("\x1f")
        if len(parts) < 5:
            continue
        stash_ref, iso_date, relative_date, timestamp_str, message = (
            parts[0],
            parts[1],
            parts[2],
            parts[3],
            parts[4],
        )

        match = re.search(r"@\{(\d+)\}", stash_ref)
        stash_idx = int(match.group(1)) if match else 0
        try:
            timestamp = int(timestamp_str)
        except ValueError:
            timestamp = 0

        entries.append(
            StashEntry(
                item_id=curr_id,
                repo_name=repo_name,
                repo_dir=repo_dir,
                stash_ref=stash_ref,
                stash_idx=stash_idx,
                iso_date=iso_date,
                relative_date=relative_date,
                timestamp=timestamp,
                message=message,
            )
        )
        curr_id += 1

    return entries


def collect_all_stashes(repos: list[tuple[str, Path]]) -> list[StashEntry]:
    """Collect all stashes across all repositories."""
    all_stashes: list[StashEntry] = []
    for repo_name, repo_dir in repos:
        stashes = get_stashes_for_repo(
            repo_name, repo_dir, start_id=len(all_stashes) + 1
        )
        all_stashes.extend(stashes)
    return all_stashes


def print_stash_table(stashes: Sequence[StashEntry]) -> None:
    """Print a formatted table of all stashes."""
    if not stashes:
        print(green("No stashes found across any repositories."))
        return

    unique_repos = {s.repo_name for s in stashes}
    print("=" * 88)
    print(
        bold(
            f"  Git Stashes across Managed Repositories ({len(stashes)} stash{'es' if len(stashes) != 1 else ''} in {len(unique_repos)} repo{'s' if len(unique_repos) != 1 else ''})"
        )
    )
    print("=" * 88)

    # Header (pad raw text before styling)
    h_idx = bold(f"{'#':<5}")
    h_repo = bold(f"{'REPO':<14}")
    h_ref = bold(f"{'STASH REF':<11}")
    h_date = bold(f"{'DATE (RELATIVE)':<30}")
    h_msg = bold("MESSAGE")
    print(f"{h_idx} {h_repo} {h_ref} {h_date} {h_msg}")
    print(dim("─" * 88))

    for s in stashes:
        raw_idx = f"[{s.item_id}]".ljust(5)
        raw_repo = s.repo_name[:14].ljust(14)
        raw_ref = s.stash_ref.ljust(11)
        short_date = s.iso_date[:16]
        date_combined = f"{short_date} ({s.relative_date})".ljust(30)

        idx_str = cyan(raw_idx)
        repo_str = yellow(raw_repo)
        ref_str = raw_ref
        date_str = green(date_combined)
        msg_str = s.message

        print(f"{idx_str} {repo_str} {ref_str} {date_str} {msg_str}")

    print(dim("─" * 88))


def parse_selection_spec(spec: str, stashes: list[StashEntry]) -> list[StashEntry]:
    """Parse selection string (indices, ranges, 'all', 'repo:<name>', 'older:<days>').

    Supports:
      - 'all'
      - '1,3,5'
      - '2-4'
      - 'repo:neurocnl'
      - 'older:30'
    """
    spec = spec.strip()
    if not spec:
        return []

    id_map = {s.item_id: s for s in stashes}
    selected_set: set[int] = set()

    tokens = [t.strip() for t in re.split(r"[\s,]+", spec) if t.strip()]

    now_ts = int(time.time())

    for token in tokens:
        token_lower = token.lower()
        if token_lower == "all":
            return list(stashes)

        if token_lower.startswith("repo:"):
            target_repo = token[5:].strip().lower()
            for s in stashes:
                s_repo = s.repo_name.lower()
                # allow "root" to match "(root)"
                if s_repo == target_repo or s_repo.strip("()") == target_repo:
                    selected_set.add(s.item_id)
            continue

        if token_lower.startswith("older:"):
            days_str = token[6:].strip()
            try:
                days = float(days_str)
                cutoff_ts = now_ts - int(days * 86400)
                for s in stashes:
                    if s.timestamp > 0 and s.timestamp < cutoff_ts:
                        selected_set.add(s.item_id)
            except ValueError:
                print(
                    red(
                        f"Invalid 'older:' format: '{token}'. Expected a number of days."
                    ),
                    file=sys.stderr,
                )
            continue

        # Range check: e.g. "2-5"
        range_match = re.match(r"^(\d+)\s*-\s*(\d+)$", token)
        if range_match:
            start, end = int(range_match.group(1)), int(range_match.group(2))
            if start > end:
                start, end = end, start
            for i in range(start, end + 1):
                if i in id_map:
                    selected_set.add(i)
                else:
                    print(
                        yellow(
                            f"Warning: Index [{i}] is out of range (1-{len(stashes)})."
                        ),
                        file=sys.stderr,
                    )
            continue

        # Single number check
        if token.isdigit():
            i = int(token)
            if i in id_map:
                selected_set.add(i)
            else:
                print(
                    yellow(f"Warning: Index [{i}] is out of range (1-{len(stashes)})."),
                    file=sys.stderr,
                )
            continue

        print(
            yellow(f"Warning: Unrecognized selector '{token}'. Skipped."),
            file=sys.stderr,
        )

    return [id_map[i] for i in sorted(selected_set)]


def drop_stashes(stashes_to_drop: list[StashEntry], dry_run: bool = False) -> int:
    """Drop specified stashes safely in descending order per repository.

    Returns the number of successfully dropped stashes.
    """
    if not stashes_to_drop:
        print("No stashes selected to drop.")
        return 0

    # Group by repository directory
    by_repo: dict[Path, list[StashEntry]] = {}
    for s in stashes_to_drop:
        by_repo.setdefault(s.repo_dir, []).append(s)

    dropped_count = 0

    for repo_dir, entries in by_repo.items():
        repo_name = entries[0].repo_name

        # Crucial: Drop from highest index to lowest index so index shifting does not break subsequent drops!
        sorted_entries = sorted(entries, key=lambda s: s.stash_idx, reverse=True)

        for entry in sorted_entries:
            target_ref = f"stash@{{{entry.stash_idx}}}"
            if dry_run:
                print(
                    dim(
                        f"  [DRY-RUN] Would drop in {repo_name}: {target_ref} (Date: {entry.iso_date[:16]}) - {entry.message}"
                    )
                )
                dropped_count += 1
                continue

            cmd = ["git", "-C", str(repo_dir), "stash", "drop", target_ref]
            res = subprocess.run(cmd, capture_output=True, text=True)
            if res.returncode == 0:
                print(
                    green(f"  ✔ Dropped in {repo_name}: {target_ref}")
                    + f" - {dim(entry.message[:50])}"
                )
                dropped_count += 1
            else:
                err_msg = res.stderr.strip() or res.stdout.strip()
                print(
                    red(f"  ✘ Failed to drop in {repo_name} {target_ref}: {err_msg}"),
                    file=sys.stderr,
                )

    return dropped_count


def prompt_confirmation(stashes_to_drop: list[StashEntry]) -> bool:
    """Prompt user for confirmation before dropping."""
    print(
        bold(
            f"\nSelected {len(stashes_to_drop)} stash{'es' if len(stashes_to_drop) != 1 else ''} for removal:"
        )
    )
    for s in stashes_to_drop:
        print(
            f"  • {cyan(f'[{s.item_id}]')} {yellow(s.repo_name)}: {s.stash_ref} ({green(s.iso_date[:16])}) - {s.message}"
        )

    try:
        answer = (
            input(bold("\nAre you sure you want to drop these stashes? [y/N]: "))
            .strip()
            .lower()
        )
        return answer in ("y", "yes")
    except (KeyboardInterrupt, EOFError):
        print("\nAborted.")
        return False


def run_interactive(stashes: list[StashEntry], dry_run: bool = False) -> None:
    """Run interactive menu for batch stash selection."""
    print_stash_table(stashes)
    if not stashes:
        return

    print("\n" + bold("Batch Drop Options:"))
    print(f"  • Stash indices/ranges : {cyan('1')}, {cyan('1,3,5')}, or {cyan('2-4')}")
    print(f"  • All stashes          : {cyan('all')}")
    print(
        f"  • By repository        : {cyan('repo:<name>')} (e.g. {cyan('repo:neurocnl')} or {cyan('repo:root')})"
    )
    print(
        f"  • By age               : {cyan('older:<days>')} (e.g. {cyan('older:14')})"
    )
    print(f"  • Quit without changes : press {dim('Enter')} or {dim('q')}")

    try:
        user_input = input(bold("\nEnter selection: ")).strip()
    except (KeyboardInterrupt, EOFError):
        print("\nAborted.")
        return

    if not user_input or user_input.lower() in ("q", "quit", "exit"):
        print("No changes made.")
        return

    selected = parse_selection_spec(user_input, stashes)
    if not selected:
        print("No matching stashes found for selection.")
        return

    if not dry_run:
        if not prompt_confirmation(selected):
            print("Operation cancelled. No stashes were dropped.")
            return

    count = drop_stashes(selected, dry_run=dry_run)
    action_word = "Would have dropped" if dry_run else "Successfully dropped"
    print(bold(f"\n{action_word} {count} stash{'es' if count != 1 else ''}."))


def main() -> None:
    parser = argparse.ArgumentParser(
        description="List and batch-drop git stashes across root and all submodules."
    )
    parser.add_argument(
        "-l",
        "--list",
        action="store_true",
        help="List all stashes and exit without modifying anything.",
    )
    parser.add_argument(
        "-d",
        "--drop",
        metavar="SPEC",
        type=str,
        help="Drop stashes matching specification (e.g. '1,3,5', '2-4', 'all', 'repo:neurocnl', 'older:30').",
    )
    parser.add_argument(
        "-a",
        "--all",
        action="store_true",
        help="Drop all stashes across all repositories.",
    )
    parser.add_argument(
        "-r",
        "--repo",
        metavar="NAME",
        type=str,
        help="Drop all stashes in specified repository (e.g. 'neurocnl' or 'root').",
    )
    parser.add_argument(
        "--older-than",
        metavar="DAYS",
        type=float,
        help="Drop stashes older than N days.",
    )
    parser.add_argument(
        "-n",
        "--dry-run",
        action="store_true",
        help="Show which stashes would be dropped without actually deleting them.",
    )
    parser.add_argument(
        "-y",
        "--yes",
        action="store_true",
        help="Skip confirmation prompt before dropping.",
    )
    parser.add_argument(
        "-i",
        "--interactive",
        action="store_true",
        help="Launch interactive prompt even if input/output is not a TTY.",
    )
    parser.add_argument(
        "--no-color",
        action="store_true",
        help="Disable color output.",
    )

    args = parser.parse_args()

    global USE_COLOR
    if args.no_color:
        USE_COLOR = False

    root_dir = find_git_root()
    repos = discover_repos(root_dir)
    stashes = collect_all_stashes(repos)

    # If --list requested:
    if args.list:
        print_stash_table(stashes)
        return

    # Check for CLI drop actions
    has_action = (
        args.drop is not None
        or args.all
        or args.repo is not None
        or args.older_than is not None
    )

    if not has_action:
        # If no specific drop flag was supplied, run interactive if TTY or --interactive
        if sys.stdin.isatty() or args.interactive:
            run_interactive(stashes, dry_run=args.dry_run)
            return
        else:
            # Non-interactive default without action flags: just list
            print_stash_table(stashes)
            return

    # Non-interactive / CLI flag specified
    if not stashes:
        print(green("No stashes found across any repositories."))
        return

    selected_stashes: list[StashEntry] = []

    if args.all:
        selected_stashes = list(stashes)
    elif args.repo:
        selected_stashes = parse_selection_spec(f"repo:{args.repo}", stashes)
    elif args.older_than is not None:
        selected_stashes = parse_selection_spec(f"older:{args.older_than}", stashes)
    elif args.drop:
        selected_stashes = parse_selection_spec(args.drop, stashes)

    if not selected_stashes:
        print("No stashes matched the criteria.")
        return

    if not args.dry_run and not args.yes:
        if not prompt_confirmation(selected_stashes):
            print("Operation cancelled. No stashes were dropped.")
            return

    count = drop_stashes(selected_stashes, dry_run=args.dry_run)
    action_word = "Would have dropped" if args.dry_run else "Successfully dropped"
    print(bold(f"\n{action_word} {count} stash{'es' if count != 1 else ''}."))


if __name__ == "__main__":
    main()
