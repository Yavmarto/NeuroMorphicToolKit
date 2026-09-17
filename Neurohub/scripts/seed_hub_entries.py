#!/usr/bin/env python3
"""Neurohub Hub Seed Script.

Seeds the 10 first hub entries into a running Neurohub instance:
  - 12 CNL spec assets  (10 templates + 2 Dream Hand)
  - 6  benchmark definition assets
  - 2  encoding preset assets
  - 6  projects linking assets together via ProjectLinks

The actual entries live as declarative JSON documents in `seed_data/`
(`cnl_assets.json`, `benchmark_assets.json`, `encoding_presets.json`,
`studio_workspaces.json`, `projects.json`), validated against the models in
`seed_data/models.py`. This script only resolves source files, copies/writes
them into `shared_assets/`, and POSTs the resulting payloads — it is a
loader, not the catalog.

Usage (run from Neurohub/ directory):
    python scripts/seed_hub_entries.py
    python scripts/seed_hub_entries.py --base-url http://localhost:9000
    python scripts/seed_hub_entries.py --dry-run       # prints payload, no HTTP
    python scripts/seed_hub_entries.py --api-key mykey # use X-API-Key header

Requirements:
    pip install httpx pydantic
    Neurohub backend must be running with NEUROHUB_AUTH_ENABLED=false (default)
    Run from the Neurohub/ directory so relative paths resolve correctly.

Exit codes:
    0  All assets and projects seeded (or already existed)
    1  Missing source files, invalid seed documents, or server unreachable
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import sys
from datetime import datetime, UTC
from pathlib import Path
from typing import TypeVar

# ── Optional httpx import ────────────────────────────────────────────────────

try:
    import httpx
except ImportError:
    print("ERROR: httpx not installed. Run: pip install httpx")
    sys.exit(1)

from pydantic import ValidationError

sys.path.insert(0, str(Path(__file__).resolve().parent))
from seed_data.models import (  # noqa: E402
    BenchmarkAssetSeed,
    CnlAssetSeed,
    EncodingPresetSeed,
    ProjectSeed,
    SourceRef,
    StudioWorkspaceSeed,
)

# ── Path resolution ──────────────────────────────────────────────────────────


def _find_roots() -> tuple[Path, Path]:
    """Return (NEUROHUB_ROOT, NMTK_ROOT) regardless of CWD."""
    cwd = Path.cwd().resolve()

    # Running from Neurohub/
    if (cwd / "neurohub").is_dir() and (cwd / "neurohub_spec.md").exists():
        return cwd, cwd.parent

    # Running from NMTK root
    if (cwd / "Neurohub").is_dir() and (cwd / "neurocnl").is_dir():
        return cwd / "Neurohub", cwd

    # Try script's own location
    script_dir = Path(__file__).resolve().parent
    neurohub_root = script_dir.parent
    if (neurohub_root / "neurohub").is_dir():
        return neurohub_root, neurohub_root.parent

    print(
        "ERROR: Cannot find NMTK root. " "Run this script from Neurohub/ or NeuroMorphicToolKit/."
    )
    sys.exit(1)


NEUROHUB_ROOT, NMTK_ROOT = _find_roots()
SHARED_ASSETS_DIR = NEUROHUB_ROOT / "shared_assets"
SEED_DATA_DIR = Path(__file__).resolve().parent / "seed_data"

_SRC_ROOTS: dict[str, Path] = {
    "cnl_templates": NMTK_ROOT / "neurocnl" / "backend" / "app" / "templates",
    "benchmarks": NMTK_ROOT / "Neurobench" / "neurobench" / "benchmarks" / "builtin",
    "dream_hand": NMTK_ROOT / "Neuro-Dream-Hand" / "cnl-specs",
}


def _resolve_src(ref: SourceRef) -> Path:
    root: str = ref.root
    file: str = ref.file
    return _SRC_ROOTS[root] / file


# ── Helpers ──────────────────────────────────────────────────────────────────


def sha256_file(path: Path) -> str:
    """Return the hex-encoded SHA-256 digest of the file at `path`."""
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65_536), b""):
            h.update(chunk)
    return h.hexdigest()


def copy_to_storage(
    src: Path, asset_type: str, dest_name: str | None = None
) -> tuple[str, int, str]:
    """Copy *src* into shared_assets/{asset_type}/.

    *dest_name* overrides the destination filename (use to avoid collisions when
    two source files have the same basename, e.g. reflex_arc.cnl from two modules).

    Returns (relative_path, size_bytes, sha256).
    """
    dest_dir = SHARED_ASSETS_DIR / asset_type
    dest_dir.mkdir(parents=True, exist_ok=True)
    filename = dest_name or src.name
    dest = dest_dir / filename
    shutil.copy2(src, dest)
    sha = sha256_file(dest)
    return f"shared_assets/{asset_type}/{filename}", dest.stat().st_size, sha


def write_json_to_storage(filename: str, asset_type: str, data: dict) -> tuple[str, int, str]:
    """Write *data* as JSON into shared_assets/{asset_type}/{filename}.

    Returns (relative_path, size_bytes, sha256).
    """
    dest_dir = SHARED_ASSETS_DIR / asset_type
    dest_dir.mkdir(parents=True, exist_ok=True)
    dest = dest_dir / filename
    content = json.dumps(data, indent=2).encode()
    dest.write_bytes(content)
    sha = hashlib.sha256(content).hexdigest()
    return f"shared_assets/{asset_type}/{filename}", len(content), sha


# The Braille RNN dataset ships in NIR's vendored `paper/` tree, which is
# gitignored and only materializes once `tools/reference_assets.py fetch` has
# run. Seeded Studio workspaces must not depend on that: copy the file into
# Neurohub's own shared_assets/ once at seed time (same pattern already used
# for every other asset type below) so `selectedDatasetPath` is a durable
# Neurohub-owned path instead of a legacy vendor-tree reference.
BRAILLE_DS_TEST_SOURCE = NMTK_ROOT / "paper" / "03_rnn" / "data" / "ds_test.pt"
BRAILLE_DATASET_SENTINEL = "__BRAILLE_DATASET_PATH__"


def _copy_braille_dataset() -> str | None:
    """Copy the Braille ds_test dataset into shared_assets/, returning its path.

    Returns None (leaving selectedDatasetPath unset) if the legacy `paper/`
    tree hasn't been fetched on this machine.
    """
    if not BRAILLE_DS_TEST_SOURCE.exists():
        print(f"  ⚠ Missing source: {BRAILLE_DS_TEST_SOURCE} — selectedDatasetPath left unset")
        return None
    rel_path, _size, _sha = copy_to_storage(BRAILLE_DS_TEST_SOURCE, "dataset")
    return rel_path


NOW = datetime.now(UTC).isoformat()
SEED_AUTHOR = "neurohub-seed"


# ── Seed document loading ────────────────────────────────────────────────────


_SeedModel = TypeVar("_SeedModel")


def _load_seed_documents(filename: str, model: type[_SeedModel]) -> list[_SeedModel]:
    """Load and validate a JSON array of seed documents from `seed_data/`."""
    path = SEED_DATA_DIR / filename
    raw = json.loads(path.read_text())
    try:
        return [model(**item) for item in raw]
    except ValidationError as exc:
        print(f"ERROR: invalid seed document in {path}:\n{exc}")
        sys.exit(1)


# ── Payload builders ─────────────────────────────────────────────────────────


def build_cnl_asset(entry: CnlAssetSeed) -> dict | None:
    """Prepare a SharedAsset payload for a CNL spec file."""
    src = _resolve_src(entry.src)
    if not src.exists():
        print(f"  ⚠ Missing source: {src} — skipping {entry.slug}")
        return None

    rel_path, size, sha = copy_to_storage(src, "cnl_spec", dest_name=entry.dest_name)
    return {
        "id": entry.id,
        "name": entry.name,
        "description": entry.description,
        "type": "cnl_spec",
        "version": 1,
        "author": SEED_AUTHOR,
        "tags": entry.tags,
        "created_at": NOW,
        "file_path": rel_path,
        "file_size_bytes": size,
        "sha256": sha,
        "metadata": entry.metadata,
    }


def build_benchmark_asset(entry: BenchmarkAssetSeed) -> dict | None:
    """Prepare a SharedAsset payload for a benchmark JSON file."""
    src = _resolve_src(entry.src)
    if not src.exists():
        print(f"  ⚠ Missing source: {src} — skipping {entry.slug}")
        return None

    # Extract name and description directly from the benchmark JSON.
    raw = json.loads(src.read_text())
    name = raw.get("name", entry.slug)
    description = raw.get("description", "")

    rel_path, size, sha = copy_to_storage(src, "benchmark_definition")
    return {
        "id": entry.id,
        "name": name,
        "description": description,
        "type": "benchmark_definition",
        "version": 1,
        "author": SEED_AUTHOR,
        "tags": entry.tags,
        "created_at": NOW,
        "file_path": rel_path,
        "file_size_bytes": size,
        "sha256": sha,
        "metadata": {"benchmark_id": raw.get("id"), "task_type": raw.get("task_type")},
    }


def build_encoding_preset_asset(entry: EncodingPresetSeed) -> dict:
    """Prepare a SharedAsset payload for an encoding preset (written inline)."""
    rel_path, size, sha = write_json_to_storage(entry.filename, "encoding_preset", entry.data)
    return {
        "id": entry.id,
        "name": entry.name,
        "description": entry.description,
        "type": "encoding_preset",
        "version": 1,
        "author": SEED_AUTHOR,
        "tags": entry.tags,
        "created_at": NOW,
        "file_path": rel_path,
        "file_size_bytes": size,
        "sha256": sha,
        "metadata": {"encoding_method": entry.data["method"]},
    }


def _needs_braille_dataset(entry: StudioWorkspaceSeed) -> bool:
    return bool(entry.data.get("selectedDatasetPath") == BRAILLE_DATASET_SENTINEL)


def build_studio_workspace_asset(
    entry: StudioWorkspaceSeed, braille_dataset_path: str | None
) -> dict:
    """Prepare a SharedAsset payload for a CNLStudio workspace (written inline)."""
    data = dict(entry.data)
    if _needs_braille_dataset(entry):
        data["selectedDatasetPath"] = braille_dataset_path

    rel_path, size, sha = write_json_to_storage(entry.filename, "studio_workspace", data)
    return {
        "id": entry.id,
        "name": entry.name,
        "description": entry.description,
        "type": "studio_workspace",
        "version": 1,
        "author": SEED_AUTHOR,
        "tags": entry.tags,
        "created_at": NOW,
        "file_path": rel_path,
        "file_size_bytes": size,
        "sha256": sha,
        "metadata": entry.metadata,
    }


def build_project(entry: ProjectSeed, sha_map: dict[str, str]) -> dict:
    """Prepare a Project payload, resolving `cnl_spec_slug` to its computed sha256."""
    links = entry.links
    cnl_spec_hash = sha_map.get(links.cnl_spec_slug) if links.cnl_spec_slug else None
    return {
        "id": entry.id,
        "name": entry.name,
        "description": entry.description,
        "created_at": NOW,
        "updated_at": NOW,
        "owner": entry.owner,
        "members": entry.members,
        "status": entry.status,
        "tags": entry.tags,
        "links": {
            "neurobench_benchmark_ids": links.neurobench_benchmark_ids,
            "cnl_spec_hash": cnl_spec_hash,
            "neurochip_deployment_ids": links.neurochip_deployment_ids,
            "neurobench_baseline_ids": links.neurobench_baseline_ids,
            "neurosense_session_ids": links.neurosense_session_ids,
        },
    }


# ── HTTP helpers ──────────────────────────────────────────────────────────────


def _headers(api_key: str | None) -> dict[str, str]:
    if api_key:
        return {"X-API-Key": api_key}
    return {}


def _post(
    client: httpx.Client,
    url: str,
    payload: dict,
    label: str,
    dry_run: bool,
) -> bool:
    """POST *payload* to *url*.  Returns True on success (201/200) or already-exists (400/409)."""
    if dry_run:
        print(f"  [DRY RUN] POST {url}")
        print(f"  {json.dumps(payload, indent=2)[:300]}...")
        return True

    try:
        r = client.post(url, json=payload, timeout=15)
    except httpx.RequestError as exc:
        print(f"  ✗ {label}: connection error – {exc}")
        return False

    if r.status_code in (200, 201):
        print(f"  ✓ {label}")
        return True
    if r.status_code in (400, 409):
        detail = r.json().get("detail", r.text)
        if "already exists" in str(detail).lower() or "integrity" in str(detail).lower():
            print(f"  ↩ {label} (already exists — skipped)")
            return True
        print(f"  ✗ {label}: {r.status_code} {detail}")
        return False

    print(f"  ✗ {label}: {r.status_code} {r.text[:200]}")
    return False


# ── Core logic ────────────────────────────────────────────────────────────────


def run(base_url: str, api_key: str | None, dry_run: bool) -> int:
    """Main seed routine. Returns exit code (0 = success)."""
    assets_url = f"{base_url}/api/neurohub/assets"
    projects_url = f"{base_url}/api/neurohub/projects"

    # ── 1. Health check ───────────────────────────────────────────────────────
    print(f"\n[1/4] Checking Neurohub at {base_url} …")
    if not dry_run:
        try:
            r = httpx.get(f"{base_url}/health", timeout=5)
            if r.status_code != 200:
                print(f"  ✗ /health returned {r.status_code} — is the server running?")
                return 1
            print("  ✓ Server healthy")
        except httpx.RequestError as exc:
            print(f"  ✗ Cannot reach {base_url}: {exc}")
            print("  Start Neurohub with: cd Neurohub && uvicorn neurohub.app.main:app --port 8005")
            return 1

    # ── 2. Build payloads + copy files ────────────────────────────────────────
    print("\n[2/4] Preparing assets (copying source files to shared_assets/) …")

    payloads: list[dict] = []
    sha_map: dict[str, str] = {}  # slug → sha256

    # CNL specs (main templates + Dream Hand, same document — missing source
    # only warns for either, never fails the run).
    for entry in _load_seed_documents("cnl_assets.json", CnlAssetSeed):
        payload = build_cnl_asset(entry)
        if payload:
            payloads.append(payload)
            sha_map[entry.slug] = payload["sha256"]

    # Benchmark definitions
    for entry in _load_seed_documents("benchmark_assets.json", BenchmarkAssetSeed):
        payload = build_benchmark_asset(entry)
        if payload:
            payloads.append(payload)
            sha_map[entry.slug] = payload["sha256"]

    # Encoding presets (generated inline)
    for entry in _load_seed_documents("encoding_presets.json", EncodingPresetSeed):
        payload = build_encoding_preset_asset(entry)
        payloads.append(payload)
        sha_map[entry.slug] = payload["sha256"]

    # Studio workspaces (generated inline). Only copy the Braille dataset once,
    # regardless of how many workspaces reference it.
    workspace_entries = _load_seed_documents("studio_workspaces.json", StudioWorkspaceSeed)
    any_braille = any(_needs_braille_dataset(e) for e in workspace_entries)
    braille_dataset_path = _copy_braille_dataset() if any_braille else None
    for entry in workspace_entries:
        payload = build_studio_workspace_asset(entry, braille_dataset_path)
        payloads.append(payload)
        sha_map[entry.slug] = payload["sha256"]

    print(f"  Prepared {len(payloads)} asset(s)")

    # ── 3. POST assets ────────────────────────────────────────────────────────
    print("\n[3/4] Seeding assets …")
    failures = 0
    projects = [
        build_project(entry, sha_map)
        for entry in _load_seed_documents("projects.json", ProjectSeed)
    ]
    with httpx.Client(headers=_headers(api_key)) as client:
        for p in payloads:
            ok = _post(client, assets_url, p, p["name"], dry_run)
            if not ok:
                failures += 1

        # ── 4. POST projects ──────────────────────────────────────────────────
        print("\n[4/4] Seeding projects …")
        for proj in projects:
            ok = _post(client, projects_url, proj, proj["name"], dry_run)
            if not ok:
                failures += 1

    # ── Summary ───────────────────────────────────────────────────────────────
    total = len(payloads) + len(projects)
    print(f"\n{'[DRY RUN] ' if dry_run else ''}Done: {total - failures}/{total} items OK")
    if failures:
        print(f"  {failures} item(s) failed — check output above")
        return 1
    return 0


# ── CLI ───────────────────────────────────────────────────────────────────────


def main() -> None:
    """Parse CLI args and seed the hub entries into the target Neurohub instance."""
    parser = argparse.ArgumentParser(
        description="Seed the 10 first Neurohub hub entries.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "--base-url",
        default=os.environ.get("NEUROHUB_BASE_URL", "http://localhost:8005"),
        help="Neurohub base URL (default: http://localhost:8005 or $NEUROHUB_BASE_URL)",
    )
    parser.add_argument(
        "--api-key",
        default=os.environ.get("NEUROHUB_ADMIN_API_KEY"),
        help="Admin API key (not needed when NEUROHUB_AUTH_ENABLED=false)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print payloads without making any HTTP requests",
    )
    args = parser.parse_args()

    sys.exit(run(args.base_url, args.api_key, args.dry_run))


if __name__ == "__main__":
    main()
