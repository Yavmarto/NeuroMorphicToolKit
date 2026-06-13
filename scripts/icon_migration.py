#!/usr/bin/env python3
"""Material Icons → ZetaIcons migration script.

Three-tier sweep:
  Tier A: Mechanical normalisation (5 rules)
  Tier B: Curated semantic mapping
  Tier C1: Annotate remaining with ZETA-MIGRATION-EXEMPT markers

Usage:
  python3 scripts/icon_migration.py [--dry-run] [--tier A|B|C1|all] [--package <name>]
"""

import argparse
import os
import re
import sys
from pathlib import Path
from typing import Optional

REPO_ROOT = Path(__file__).resolve().parent.parent

PACKAGES = [
    "neurocnl/frontend",
    "nmtk/neuro_toolkit",
    "Neurohub/frontend",
    "Neurosense/frontend",
    "nmtk_ui_core",
    "Neurobench/frontend",
]

ZETA_ICONS_PATHS = [
    Path.home() / ".pub-cache/hosted/pub.dev/zeta_icons-1.9.4/lib/src/icons.g.dart",
    Path.home() / ".pub-cache/hosted/pub.dev/zeta_icons-1.9.3/lib/src/icons.g.dart",
]

ZETA_IMPORT = "import 'package:zeta_flutter/zeta_flutter.dart';"
MATERIAL_IMPORT = "import 'package:flutter/material.dart';"
EXEMPT_MARKER_REGEX = re.compile(r'ZETA-MIGRATION-EXEMPT:\s*\S')
ICONS_REF_REGEX = re.compile(r'\bIcons\.([a-z_0-9]+)\b')


def load_zeta_icons_names() -> set[str]:
    for path in ZETA_ICONS_PATHS:
        if path.exists():
            names = set()
            content = path.read_text()
            for match in re.finditer(r'static const IconData ([a-z_0-9]+)', content):
                names.add(match.group(1))
            return names
    print("ERROR: Could not find ZetaIcons source file in pub cache", file=sys.stderr)
    sys.exit(1)


TIER_B_MAP = {
    "play_arrow": "play",
    "play_arrow_rounded": "play",
    "play_arrow_outlined": "play",
    "play_circle_outline": "play_circle",
    "play_circle_outline_rounded": "play_circle",
    "play_circle_fill": "play_circle",
    "play_circle_fill_rounded": "play_circle",
    "pause_circle_outline": "pause_circle",
    "pause_circle_outline_rounded": "pause_circle",
    "replay_circle_filled_rounded": "replay",
    "arrow_back_ios_new_rounded": "arrow_back",
    "arrow_forward_ios": "arrow_forward",
    "arrow_drop_down": "arrow_down",
    "keyboard_arrow_down": "arrow_down",
    "keyboard_arrow_up": "arrow_up",
    "keyboard_arrow_left": "arrow_back",
    "keyboard_arrow_right": "arrow_forward",
    "keyboard_tab": "arrow_forward",
    "more_vert": "more_vertical",
    "info_outline": "info",
    "info_outline_rounded": "info",
    "circle_outlined": "radio_button_unchecked",
    "circle": "radio_button_checked",
    "check": "check_circle",
    "open_in_new": "open_in_new_window",
    "open_in_new_rounded": "open_in_new_window",
    "open_in_browser": "open_in_new_window",
    "description": "note",
    "description_outlined": "note",
    "save_as_rounded": "save",
    "folder_open_outlined": "folder_outline",
    "folder_open_rounded": "folder_outline",
    "file_open_outlined": "file",
    "insert_drive_file_outlined": "file",
    "attach_file_rounded": "attachment",
    "download_for_offline_outlined": "download",
    "fiber_manual_record": "radio_button_checked",
    "fiber_manual_record_rounded": "radio_button_checked",
    "unfold_more": "unfold_more",
    "view_stream": "list",
    "show_chart": "chart_bar",
    "multiline_chart_rounded": "chart_bar",
    "bar_chart_rounded": "chart_bar",
    "bar_chart": "chart_bar",
    "bar_chart_outlined": "chart_bar",
    "data_usage_rounded": "chart_doughnut",
    "equalizer": "chart_bar",
    "graphic_eq_rounded": "activity",
    "linear_scale": "minus",
    "square_rounded": "stop",
    "panorama_horizontal_outlined": "image",
    "videocam_off_outlined": "video_off",
    "usb_off_rounded": "usb",
    "wifi_find_rounded": "wifi",
    "cloud_off": "cloud_off",
    "cloud_upload_outlined": "cloud_upload",
    "cloud_download_outlined": "cloud_download",
    "do_not_disturb_alt_outlined": "block",
    "block": "block",
    "web": "globe",
    "web_outlined": "globe",
    "web_rounded": "globe",
    "language_outlined": "globe",
    "notes_rounded": "text_snippet",
    "sticky_note_2_outlined": "note",
    "text_snippet_outlined": "text_snippet",
    "article": "text_snippet",
    "article_outlined": "text_snippet",
    "system_update": "upgrade",
    "sync_problem": "sync_disabled",
    "link_off": "link",
    "search_off": "search",
    "search_off_rounded": "search",
    "filter_alt_off_rounded": "filter",
    "filter_none": "crop",
    "warning_amber_rounded": "warning_outline",
    "warning_amber_outlined": "warning_outline",
    "stop_circle_outlined": "stop_circle",
}


def tier_a_normalize(name: str, zeta_names: set[str]) -> Optional[str]:
    candidates = [name]

    r1 = re.sub(r'_outlined$', '_outline', name)
    if r1 != name:
        candidates.append(r1)

    r2 = re.sub(r'_rounded$', '', name)
    if r2 != name:
        candidates.append(r2)

    r3 = re.sub(r'_amber', '', name)
    if r3 != name:
        candidates.append(r3)

    base = re.sub(r'_rounded$', '', re.sub(r'_outlined$', '_outline', name))
    r4 = base + '_round'
    if r4 != name:
        candidates.append(r4)

    r5 = re.sub(r'_outlined$', '', name)
    if r5 != name:
        candidates.append(r5)

    for candidate in candidates:
        if candidate in zeta_names:
            return candidate
    return None


def get_lib_dir(package: str) -> Path:
    return REPO_ROOT / package / "lib"


def find_dart_files(lib_dir: Path) -> list[Path]:
    if not lib_dir.exists():
        return []
    return sorted(lib_dir.rglob("*.dart"))


def has_zeta_import(content: str) -> bool:
    return ('package:zeta_flutter/' in content or
            'package:nmtk_ui_core/' in content or
            'package:zeta_icons/' in content)


def has_material_import(content: str) -> bool:
    return 'package:flutter/material.dart' in content


def add_zeta_import(content: str) -> str:
    lines = content.split('\n')
    last_import_idx = -1
    for i, line in enumerate(lines):
        if line.strip().startswith('import '):
            last_import_idx = i

    if last_import_idx >= 0:
        lines.insert(last_import_idx + 1, ZETA_IMPORT)
    else:
        lines.insert(0, ZETA_IMPORT)
        lines.insert(1, '')

    return '\n'.join(lines)


class MigrationStats:
    def __init__(self):
        self.tier_a_replacements = 0
        self.tier_b_replacements = 0
        self.tier_c1_markers_added = 0
        self.imports_added = 0
        self.files_modified = 0
        self.files_scanned = 0
        self.total_icons_found = 0
        self.already_migrated = 0
        self.per_icon_tier_a: dict[str, int] = {}
        self.per_icon_tier_b: dict[str, int] = {}
        self.per_icon_tier_c1: dict[str, int] = {}


def process_file(
    filepath: Path,
    zeta_names: set[str],
    tier_b_map: dict[str, str],
    tier: str,
    dry_run: bool,
    stats: MigrationStats,
) -> None:
    stats.files_scanned += 1
    content = filepath.read_text()
    original_content = content

    icons_refs = ICONS_REF_REGEX.findall(content)
    if not icons_refs:
        return

    stats.total_icons_found += len(icons_refs)

    needs_zeta = False
    lines = content.split('\n')
    modified_lines = []

    for i, line in enumerate(lines):
        trimmed = line.strip()

        if trimmed.startswith('//') or trimmed.startswith('///'):
            if EXEMPT_MARKER_REGEX.search(line):
                pass
            modified_lines.append(line)
            continue

        if EXEMPT_MARKER_REGEX.search(line):
            modified_lines.append(line)
            continue

        if i > 0 and EXEMPT_MARKER_REGEX.search(lines[i - 1]):
            modified_lines.append(line)
            continue

        new_line = line
        line_icons = ICONS_REF_REGEX.findall(line)

        for icon_name in line_icons:
            full_ref = f"Icons.{icon_name}"
            replacement = None
            replacement_tier = None

            if tier in ("A", "all"):
                zeta_match = tier_a_normalize(icon_name, zeta_names)
                if zeta_match:
                    replacement = f"ZetaIcons.{zeta_match}"
                    replacement_tier = "A"

            if replacement is None and tier in ("B", "all"):
                if icon_name in tier_b_map:
                    zeta_target = tier_b_map[icon_name]
                    if zeta_target in zeta_names:
                        replacement = f"ZetaIcons.{zeta_target}"
                        replacement_tier = "B"

            if replacement:
                new_line = new_line.replace(full_ref, replacement)
                needs_zeta = True
                if replacement_tier == "A":
                    stats.tier_a_replacements += 1
                    stats.per_icon_tier_a[icon_name] = stats.per_icon_tier_a.get(icon_name, 0) + 1
                else:
                    stats.tier_b_replacements += 1
                    stats.per_icon_tier_b[icon_name] = stats.per_icon_tier_b.get(icon_name, 0) + 1
            elif tier in ("C1", "all") and full_ref in new_line:
                marker = f" // ZETA-MIGRATION-EXEMPT: no Zeta equivalent"
                if not EXEMPT_MARKER_REGEX.search(new_line):
                    new_line = new_line.rstrip() + marker
                    stats.tier_c1_markers_added += 1
                    stats.per_icon_tier_c1[icon_name] = stats.per_icon_tier_c1.get(icon_name, 0) + 1

        modified_lines.append(new_line)

    content = '\n'.join(modified_lines)

    if needs_zeta and not has_zeta_import(content):
        content = add_zeta_import(content)
        stats.imports_added += 1

    if content != original_content:
        stats.files_modified += 1
        if not dry_run:
            filepath.write_text(content)


def process_package(
    package: str,
    zeta_names: set[str],
    tier_b_map: dict[str, str],
    tier: str,
    dry_run: bool,
    stats: MigrationStats,
) -> None:
    lib_dir = get_lib_dir(package)
    dart_files = find_dart_files(lib_dir)

    print(f"\n{'='*60}")
    print(f"Package: {package}")
    print(f"  lib dir: {lib_dir}")
    print(f"  dart files: {len(dart_files)}")
    print(f"{'='*60}")

    for filepath in dart_files:
        process_file(filepath, zeta_names, tier_b_map, tier, dry_run, stats)


def print_report(stats: MigrationStats, tier: str, dry_run: bool) -> None:
    mode = "DRY RUN" if dry_run else "APPLIED"
    print(f"\n{'='*60}")
    print(f"MIGRATION REPORT ({mode})")
    print(f"{'='*60}")
    print(f"Files scanned:       {stats.files_scanned}")
    print(f"Files modified:      {stats.files_modified}")
    print(f"Total Icons.* found: {stats.total_icons_found}")

    if tier in ("A", "all"):
        print(f"\nTier A replacements: {stats.tier_a_replacements}")
        if stats.per_icon_tier_a:
            top = sorted(stats.per_icon_tier_a.items(), key=lambda x: -x[1])[:15]
            print("  Top 15 Tier A icons:")
            for name, count in top:
                print(f"    {name}: {count}")

    if tier in ("B", "all"):
        print(f"\nTier B replacements: {stats.tier_b_replacements}")
        if stats.per_icon_tier_b:
            top = sorted(stats.per_icon_tier_b.items(), key=lambda x: -x[1])[:15]
            print("  Top 15 Tier B icons:")
            for name, count in top:
                print(f"    {name}: {count}")

    if tier in ("C1", "all"):
        print(f"\nTier C1 markers added: {stats.tier_c1_markers_added}")
        if stats.per_icon_tier_c1:
            top = sorted(stats.per_icon_tier_c1.items(), key=lambda x: -x[1])[:15]
            print("  Top 15 Tier C1 icons:")
            for name, count in top:
                print(f"    {name}: {count}")

    print(f"\nZeta imports added: {stats.imports_added}")
    print(f"{'='*60}")


def main():
    parser = argparse.ArgumentParser(description="Material Icons → ZetaIcons migration")
    parser.add_argument("--dry-run", action="store_true", help="Show what would change without modifying files")
    parser.add_argument("--tier", choices=["A", "B", "C1", "all"], default="all",
                        help="Which tier(s) to apply (default: all)")
    parser.add_argument("--package", type=str, default=None,
                        help="Only process a specific package (e.g. 'neurocnl/frontend')")
    args = parser.parse_args()

    zeta_names = load_zeta_icons_names()
    print(f"Loaded {len(zeta_names)} ZetaIcons names")

    verified_tier_b = {}
    for material_name, zeta_name in TIER_B_MAP.items():
        if zeta_name in zeta_names:
            verified_tier_b[material_name] = zeta_name
        else:
            print(f"  WARN: Tier B target '{zeta_name}' for '{material_name}' not in ZetaIcons — skipping")

    print(f"Tier B mappings (verified): {len(verified_tier_b)} / {len(TIER_B_MAP)}")

    packages = [args.package] if args.package else PACKAGES
    stats = MigrationStats()

    for package in packages:
        process_package(package, zeta_names, verified_tier_b, args.tier, args.dry_run, stats)

    print_report(stats, args.tier, args.dry_run)


if __name__ == "__main__":
    main()
