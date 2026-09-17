from __future__ import annotations

from pathlib import Path

import pytest
from scripts.jules_push_ui_migration_first_tasks import (
    ModuleTask,
    build_prompt,
    discover_module_tasks,
)


def test_build_prompt_scopes_work_to_single_repo(tmp_path: Path) -> None:
    brief_path = tmp_path / "UI migration.md"
    brief_path.write_text(
        "# UI Core Consolidation Plan\n\n- Update desktop navigation.\n",
        encoding="utf-8",
    )
    task = ModuleTask(
        module_name="Neurochip",
        repo_path=tmp_path,
        brief_path=brief_path,
        repo_identifier="Yavmarto/Neurochip",
        branch="dev",
    )

    title, prompt = build_prompt(task)

    assert title == "Neurochip: first desktop UI migration task"
    assert "Work only in the Neurochip repository." in prompt
    assert "complete only the first remaining repo-local desktop migration task" in prompt
    assert "If the migration brief is already materially satisfied in this repo" in prompt
    assert "UI Core Consolidation Plan" in prompt


def test_discover_module_tasks_uses_current_branch_and_repo_identifier(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    module_path = tmp_path / "Neurohub"
    module_path.mkdir()
    (module_path / "UI migration.md").write_text("# Title\n\nBody\n", encoding="utf-8")

    monkeypatch.setattr(
        "scripts.jules_push_ui_migration_first_tasks.get_repo_identifier",
        lambda _repo_path: "Yavmarto/Neurohub",
    )
    monkeypatch.setattr(
        "scripts.jules_push_ui_migration_first_tasks.current_branch",
        lambda _repo_path: "dev",
    )

    tasks = discover_module_tasks(["Neurohub"], repo_root=tmp_path)

    assert tasks == [
        ModuleTask(
            module_name="Neurohub",
            repo_path=module_path,
            brief_path=module_path / "UI migration.md",
            repo_identifier="Yavmarto/Neurohub",
            branch="dev",
        )
    ]


def test_discover_module_tasks_honors_branch_override(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    module_path = tmp_path / "Neurosense"
    module_path.mkdir()
    (module_path / "UI migration.md").write_text("# Title\n\nBody\n", encoding="utf-8")

    monkeypatch.setattr(
        "scripts.jules_push_ui_migration_first_tasks.get_repo_identifier",
        lambda _repo_path: "Yavmarto/Neurosense",
    )
    monkeypatch.setattr(
        "scripts.jules_push_ui_migration_first_tasks.current_branch",
        lambda _repo_path: "should-not-be-used",
    )

    tasks = discover_module_tasks(
        ["Neurosense"],
        repo_root=tmp_path,
        branch_override="release/ui-desktop",
    )

    assert tasks[0].branch == "release/ui-desktop"
