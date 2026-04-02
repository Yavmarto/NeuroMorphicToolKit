"""Render human-readable Markdown previews of migration issues.

Reads each module.json and writes one .md file per issue under
<module>/generated-issues/. Useful for review before publishing.

Usage:
    python scripts/generate_issue_previews.py
    python scripts/generate_issue_previews.py --module neurocnl
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


def slugify(value: str) -> str:
    lowered = value.lower().strip()
    return re.sub(r"[^a-z0-9]+", "-", lowered).strip("-")


def render_issue(module: dict, issue: dict) -> str:
    lines: list[str] = []
    lines.append(f"# {issue['title']}")
    lines.append("")
    lines.append(f"**Module:** {module['module_name']}")
    lines.append(f"**Spec Source:** {', '.join(issue.get('spec_refs', []))}")
    lines.append(f"**Labels:** {', '.join(issue['labels'])}")
    lines.append("")
    lines.append("## Objective")
    lines.append(issue["objective"])
    lines.append("")
    lines.append("## Conversion Steps")
    for item in issue.get("conversion_steps", []):
        lines.append(f"- [ ] {item}")
    lines.append("")
    lines.append("## Contract Targets")
    for item in issue.get("contract_targets", []):
        lines.append(f"- `{item}`")
    lines.append("")
    lines.append("## Property Targets")
    for item in issue.get("property_targets", []):
        lines.append(f"- `{item}`")
    lines.append("")
    lines.append("## Acceptance Checks")
    for item in issue.get("acceptance_checks", []):
        lines.append(f"- [ ] {item}")
    if issue.get("workflow_updates"):
        lines.append("")
        lines.append("## Workflow Updates")
        for item in issue["workflow_updates"]:
            lines.append(f"- [ ] {item}")
    if issue.get("depends_on"):
        lines.append("")
        lines.append("## Dependencies")
        for item in issue["depends_on"]:
            lines.append(f"- blocked-by: `{item}`")
    lines.append("")
    return "\n".join(lines)


def iter_module_configs(root: Path, selected: set[str] | None) -> list[Path]:
    configs: list[Path] = []
    for path in sorted(root.glob("*/module.json")):
        if selected and path.parent.name not in selected:
            continue
        configs.append(path)
    return configs


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate Markdown previews of CDD-PBT migration issues.",
    )
    parser.add_argument(
        "--root",
        default=Path(__file__).resolve().parents[1],
        type=Path,
        help="Path to unified-dev-pipeline directory",
    )
    parser.add_argument("--module", action="append", default=[])
    args = parser.parse_args()

    selected = set(args.module) if args.module else None
    for config_path in iter_module_configs(args.root, selected):
        module = json.loads(config_path.read_text())
        output_dir = config_path.parent / "generated-issues"
        output_dir.mkdir(parents=True, exist_ok=True)
        for index, issue in enumerate(module["migration_issues"], start=1):
            file_name = f"{index:02d}-{slugify(issue['title'])}.md"
            (output_dir / file_name).write_text(render_issue(module, issue))
        print(f"Rendered issue previews for {module['module_name']} -> {output_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
