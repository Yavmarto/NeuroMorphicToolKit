#!/usr/bin/env python3
"""Sync canonical remote-deployment files into the Flutter asset bundle."""

from __future__ import annotations

import argparse
import filecmp
import hashlib
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DESTINATION = ROOT / "nmtk" / "neuro_toolkit" / "assets" / "deployment"
SOURCES = (
    Path("docker-compose.yml"),
    Path("docker-compose.prod.yml"),
    Path("docker-compose.remote.yml"),
    Path("monitoring/alertmanager/alertmanager.yml"),
    Path("monitoring/loki/loki-config.yml"),
    Path("monitoring/prometheus/alert_rules.yml"),
    Path("monitoring/prometheus/prometheus.yml"),
    Path("monitoring/promtail/promtail-config.yml"),
)
MANIFEST = DESTINATION / "deployment-manifest.json"
BUNDLE_VERSION = 5


def _manifest_payload() -> dict[str, object]:
    bundled_files = {
        relative.as_posix(): hashlib.sha256(
            (ROOT / relative).read_bytes()
        ).hexdigest()
        for relative in SOURCES
    }
    install_script = DESTINATION / "install.sh"
    if install_script.is_file():
        bundled_files["install.sh"] = hashlib.sha256(
            install_script.read_bytes()
        ).hexdigest()
    return {
        "bundleVersion": BUNDLE_VERSION,
        "files": bundled_files,
    }


def _matches() -> bool:
    files_match = all(
        (DESTINATION / relative).is_file()
        and filecmp.cmp(ROOT / relative, DESTINATION / relative, shallow=False)
        for relative in SOURCES
    )
    if not files_match or not MANIFEST.is_file():
        return False
    try:
        return json.loads(MANIFEST.read_text()) == _manifest_payload()
    except (json.JSONDecodeError, OSError):
        return False


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--check",
        action="store_true",
        help="fail when the Flutter deployment bundle is stale",
    )
    args = parser.parse_args()

    if args.check:
        if _matches():
            print("Flutter deployment assets are synchronized.")
            return 0
        print(
            "Flutter deployment assets are stale. Run "
            "python3 scripts/sync_flutter_deployment_assets.py."
        )
        return 1

    for relative in SOURCES:
        destination = DESTINATION / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / relative, destination)
    MANIFEST.write_text(
        json.dumps(_manifest_payload(), indent=2, sort_keys=True) + "\n"
    )
    print(f"Synced {len(SOURCES)} deployment assets into {DESTINATION}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
