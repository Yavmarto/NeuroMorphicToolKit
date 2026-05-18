from __future__ import annotations

import os
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent


def run_command(*args: str, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    merged_env = os.environ.copy()
    if env:
        merged_env.update(env)
    return subprocess.run(
        args,
        cwd=REPO_ROOT,
        text=True,
        capture_output=True,
        check=False,
        env=merged_env,
    )


def test_repo_helper_lists_all_top_level_git_repos() -> None:
    result = run_command(
        "bash",
        "-lc",
        "source scripts/git/repo_helpers.sh && list_managed_repos \"$PWD\"",
    )

    assert result.returncode == 0, result.stderr

    repo_names = {line.split("\t", 1)[0] for line in result.stdout.splitlines() if line.strip()}
    assert {
        "(root)",
        "Neuro-Dream-Hand",
        "Neurobench",
        "Neurochip",
        "Neurohub",
        "Neurosense",
        "Neurosim",
        "neurocnl",
    }.issubset(repo_names)
    assert "ai_safe" not in repo_names
    assert "scripts" not in repo_names
