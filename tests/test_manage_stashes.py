from pathlib import Path
import subprocess
import sys
import time

import pytest

from scripts.git.manage_stashes import (
    StashEntry,
    drop_stashes,
    parse_selection_spec,
)


@pytest.fixture
def sample_stashes(tmp_path: Path) -> list[StashEntry]:
    now = int(time.time())
    return [
        StashEntry(
            item_id=1,
            repo_name="repo_a",
            repo_dir=tmp_path / "repo_a",
            stash_ref="stash@{0}",
            stash_idx=0,
            iso_date="2026-09-06 20:00:00 +0000",
            relative_date="2 days ago",
            timestamp=now - 2 * 86400,
            message="WIP on feature A",
        ),
        StashEntry(
            item_id=2,
            repo_name="repo_a",
            repo_dir=tmp_path / "repo_a",
            stash_ref="stash@{1}",
            stash_idx=1,
            iso_date="2026-08-01 10:00:00 +0000",
            relative_date="5 weeks ago",
            timestamp=now - 38 * 86400,
            message="WIP on feature A old",
        ),
        StashEntry(
            item_id=3,
            repo_name="(root)",
            repo_dir=tmp_path,
            stash_ref="stash@{0}",
            stash_idx=0,
            iso_date="2026-09-07 10:00:00 +0000",
            relative_date="1 day ago",
            timestamp=now - 86400,
            message="WIP root fix",
        ),
    ]


def test_parse_selection_spec_numbers(sample_stashes: list[StashEntry]) -> None:
    selected = parse_selection_spec("1, 3", sample_stashes)
    assert [s.item_id for s in selected] == [1, 3]


def test_parse_selection_spec_range(sample_stashes: list[StashEntry]) -> None:
    selected = parse_selection_spec("1-2", sample_stashes)
    assert [s.item_id for s in selected] == [1, 2]


def test_parse_selection_spec_all(sample_stashes: list[StashEntry]) -> None:
    selected = parse_selection_spec("all", sample_stashes)
    assert len(selected) == 3


def test_parse_selection_spec_repo(sample_stashes: list[StashEntry]) -> None:
    selected_a = parse_selection_spec("repo:repo_a", sample_stashes)
    assert [s.item_id for s in selected_a] == [1, 2]

    selected_root = parse_selection_spec("repo:root", sample_stashes)
    assert [s.item_id for s in selected_root] == [3]


def test_parse_selection_spec_older_than(sample_stashes: list[StashEntry]) -> None:
    selected = parse_selection_spec("older:30", sample_stashes)
    assert [s.item_id for s in selected] == [2]


def test_drop_stashes_descending_order(tmp_path: Path) -> None:
    """Verify that git stashes are dropped in descending index order without index shifting bugs."""
    repo = tmp_path / "test_repo"
    repo.mkdir()

    subprocess.check_call(["git", "init"], cwd=repo)
    subprocess.check_call(["git", "config", "user.email", "test@test.com"], cwd=repo)
    subprocess.check_call(["git", "config", "user.name", "Test"], cwd=repo)

    (repo / "f.txt").write_text("v1")
    subprocess.check_call(["git", "add", "f.txt"], cwd=repo)
    subprocess.check_call(["git", "commit", "-m", "init"], cwd=repo)

    # Create 3 stashes: stash@{0}, stash@{1}, stash@{2}
    (repo / "f.txt").write_text("v2")
    subprocess.check_call(["git", "stash", "push", "-m", "s0"], cwd=repo)
    (repo / "f.txt").write_text("v3")
    subprocess.check_call(["git", "stash", "push", "-m", "s1"], cwd=repo)
    (repo / "f.txt").write_text("v4")
    subprocess.check_call(["git", "stash", "push", "-m", "s2"], cwd=repo)

    # In git stash list:
    # stash@{0} is s2
    # stash@{1} is s1
    # stash@{2} is s0
    now = int(time.time())
    stashes = [
        StashEntry(1, "test_repo", repo, "stash@{0}", 0, "", "", now, "s2"),
        StashEntry(2, "test_repo", repo, "stash@{1}", 1, "", "", now, "s1"),
        StashEntry(3, "test_repo", repo, "stash@{2}", 2, "", "", now, "s0"),
    ]

    # Select stash@{2} (s0) and stash@{0} (s2) to drop
    to_drop = [stashes[0], stashes[2]]
    dropped = drop_stashes(to_drop, dry_run=False)
    assert dropped == 2

    # Remaining stash in git should only be stash@{0} with message 's1'
    out = subprocess.check_output(["git", "stash", "list"], cwd=repo, text=True).strip()
    assert "s1" in out
    assert "s0" not in out
    assert "s2" not in out


def test_cli_list_mode() -> None:
    """Test running script in --list mode via CLI."""
    cmd = [sys.executable, "scripts/git/manage-stashes.py", "--list"]
    res = subprocess.run(cmd, capture_output=True, text=True)
    assert res.returncode == 0
    assert "Git Stashes across Managed Repositories" in res.stdout


def test_cli_dry_run_drop_all() -> None:
    """Test running script in --dry-run mode."""
    cmd = [
        sys.executable,
        "scripts/git/manage_stashes.py",
        "--dry-run",
        "--yes",
        "--all",
    ]
    res = subprocess.run(cmd, capture_output=True, text=True)
    assert res.returncode == 0
    assert "Would have dropped" in res.stdout or "No stashes found" in res.stdout
