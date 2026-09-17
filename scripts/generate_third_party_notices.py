#!/usr/bin/env python3
"""Generate THIRD_PARTY_NOTICES.md for NeuroMorphicToolKit.

Collects the *direct* dependencies declared across the monorepo's Python
(`pyproject.toml`) and Dart (`pubspec.yaml`) manifests, resolves each license
offline from the already-resolved environments (installed Python distributions
and the local pub cache), applies a small curated override map for packages
whose metadata is missing or non-standard, and emits a deterministic,
ecosystem- and license-grouped attribution document.

Usage:
    python3 scripts/generate_third_party_notices.py            # regenerate file
    python3 scripts/generate_third_party_notices.py --check    # fail if stale
    python3 scripts/generate_third_party_notices.py --stdout   # print, no write

The transitive dependency closure is intentionally out of scope; only the
direct dependencies declared in manifests are attributed here.
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

import tomllib

try:
    import yaml
except ImportError:  # pragma: no cover - PyYAML is a dev dependency everywhere
    print(
        "error: PyYAML is required (pip install pyyaml) to parse pubspec.yaml files",
        file=sys.stderr,
    )
    raise SystemExit(2) from None

from importlib import metadata as importlib_metadata

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "THIRD_PARTY_NOTICES.md"

# Dependency names that resolve to first-party packages or SDK stubs and must
# never be attributed as third-party components.
FIRST_PARTY = {
    "neurocnl",
    "neurosim",
    "neurochip",
    "neurohub",
    "neurosense",
    "neurodreamhand",
    "neurobench_wrapper",
    "suite-api",
    "neurocli",
    "neurobench-runner-worker",
    "neurocnl-physics-worker",
    "neurosense-hw-worker",
    "neurochip-hw-worker",
    "sc-neurocore",
    "nmtk_ui_core",
    "nmtk_module_contracts",
    "neuro_toolkit",
    "neurocnl_studio",
    "neurobench_frontend",
    "neurohub_shell_adapter",
    "neurosense_shell_adapter",
    "neurosim_shell_adapter",
    "neurosense_frontend",
}

# Curated, authoritative SPDX map for every direct Python dependency declared in
# the monorepo. This map is the source of truth so the committed
# THIRD_PARTY_NOTICES.md reproduces on any machine (including clean CI runners
# where these packages are not installed). For a dependency that is *not* listed
# here, the generator falls back to installed-distribution metadata; when that
# happens, add a pinned entry below so `--check` stays deterministic.
# Key = normalized package name. Value = (spdx, homepage).
PY_OVERRIDES: dict[str, tuple[str, str]] = {
    # --- Neuromorphic frameworks (non-standard / use-restricted) ---
    "nengo": (
        "Nengo License (free for non-commercial; commercial restricted)",
        "https://www.nengo.ai/",
    ),
    "nengo-loihi": (
        "Nengo License (free for non-commercial; commercial restricted)",
        "https://www.nengo.ai/nengo-loihi/",
    ),
    # --- Proprietary vendor SDKs ---
    "akida": ("BrainChip Akida proprietary EULA", "https://doc.brainchipinc.com/"),
    "akida-models": (
        "BrainChip Akida proprietary EULA",
        "https://doc.brainchipinc.com/",
    ),
    "cnn2snn": ("BrainChip Akida proprietary EULA", "https://doc.brainchipinc.com/"),
    "samna": ("SynSense proprietary EULA", "https://synsense-sys-int.gitlab.io/samna/"),
    "metavision-sdk": (
        "Prophesee Metavision proprietary EULA",
        "https://docs.prophesee.ai/",
    ),
    "pynq": (
        "BSD-3-Clause (with proprietary AMD/Xilinx overlays)",
        "https://github.com/Xilinx/PYNQ",
    ),
    # --- Copyleft (AGPL-compatible, confirm per distribution) ---
    "lava-nc": ("BSD-3-Clause / LGPL-2.1 (Intel Lava)", "https://lava-nc.org/"),
    "sinabs": ("AGPL-3.0", "https://sinabs.readthedocs.io/"),
    "rockpool": ("AGPL-3.0", "https://rockpool.ai/"),
    "brian2": ("CeCILL-2.1", "https://briansimulator.org/"),
    "pynn": ("CeCILL-2.1", "http://neuralensemble.org/PyNN/"),
    "norse": ("LGPL-3.0", "https://norse.github.io/norse/"),
    "py-spinnaker2": ("LGPL-3.0", "https://gitlab.com/spinnaker2/py-spinnaker2"),
    "psycopg2-binary": (
        "LGPL-3.0-or-later (with OpenSSL exception)",
        "https://www.psycopg.org/",
    ),
    "tqdm": ("MPL-2.0 AND MIT", "https://tqdm.github.io/"),
    "hypothesis": ("MPL-2.0", "https://hypothesis.works/"),
    # --- Apache-2.0 ---
    "tensorflow": ("Apache-2.0", "https://www.tensorflow.org/"),
    "mujoco": ("Apache-2.0", "https://mujoco.org/"),
    "requests": ("Apache-2.0", "https://requests.readthedocs.io/"),
    "watchdog": ("Apache-2.0", "https://github.com/gorakhargosh/watchdog"),
    "coverage": ("Apache-2.0", "https://github.com/nedbat/coveragepy"),
    "pytest-asyncio": ("Apache-2.0", "https://github.com/pytest-dev/pytest-asyncio"),
    "python-multipart": ("Apache-2.0", "https://github.com/Kludex/python-multipart"),
    "types-pyyaml": ("Apache-2.0", "https://github.com/python/typeshed"),
    "prometheus-client": ("Apache-2.0", "https://github.com/prometheus/client_python"),
    "nuitka": ("Apache-2.0", "https://nuitka.net/"),
    "boto3": ("Apache-2.0", "https://github.com/boto/boto3"),
    "ffmpeg-python": ("Apache-2.0", "https://github.com/kkroening/ffmpeg-python"),
    "mediapy": ("Apache-2.0", "https://github.com/google/mediapy"),
    "responses": ("Apache-2.0", "https://github.com/getsentry/responses"),
    "neurobench": ("Apache-2.0", "https://github.com/NeuroBench/neurobench"),
    "syrupy": ("Apache-2.0", "https://github.com/syrupy-project/syrupy"),
    # --- BSD ---
    "numpy": ("BSD-3-Clause", "https://numpy.org/"),
    "scipy": ("BSD-3-Clause", "https://scipy.org/"),
    "pandas": ("BSD-3-Clause", "https://pandas.pydata.org/"),
    "h5py": ("BSD-3-Clause", "https://www.h5py.org/"),
    "httpx": ("BSD-3-Clause", "https://github.com/encode/httpx"),
    "jinja2": ("BSD-3-Clause", "https://github.com/pallets/jinja/"),
    "lxml": ("BSD-3-Clause", "https://lxml.de/"),
    "pyserial": ("BSD-3-Clause", "https://github.com/pyserial/pyserial"),
    "ipykernel": ("BSD-3-Clause", "https://ipython.org/"),
    "jupyter-server": ("BSD-3-Clause", "https://jupyter-server.readthedocs.io/"),
    "uvicorn": ("BSD-3-Clause", "https://www.uvicorn.org/"),
    "sse-starlette": ("BSD-3-Clause", "https://github.com/sysid/sse-starlette"),
    "nir": ("BSD-3-Clause", "https://github.com/neuromorphs/NIR"),
    "weasyprint": ("BSD-3-Clause", "https://weasyprint.org/"),
    "torch": ("BSD-3-Clause", "https://pytorch.org/"),
    "passlib": ("BSD-3-Clause", "https://passlib.readthedocs.io/"),
    "python-json-logger": (
        "BSD-2-Clause",
        "https://github.com/madzak/python-json-logger",
    ),
    "mkdocs": ("BSD-2-Clause", "https://www.mkdocs.org/"),
    "pytest-benchmark": ("BSD-2-Clause", "https://github.com/ionelmc/pytest-benchmark"),
    # --- ISC ---
    "mkdocstrings": ("ISC", "https://mkdocstrings.github.io/"),
    "mkdocstrings-python": ("ISC", "https://mkdocstrings.github.io/python/"),
    # --- MIT ---
    "fastapi": ("MIT", "https://github.com/fastapi/fastapi"),
    "pydantic": ("MIT", "https://github.com/pydantic/pydantic"),
    "pydantic-settings": ("MIT", "https://github.com/pydantic/pydantic-settings"),
    "anyio": ("MIT", "https://github.com/agronholm/anyio"),
    "aiosqlite": ("MIT", "https://github.com/omnilib/aiosqlite"),
    "alembic": ("MIT", "https://alembic.sqlalchemy.org/"),
    "sqlalchemy": ("MIT", "https://www.sqlalchemy.org/"),
    "slowapi": ("MIT", "https://github.com/laurents/slowapi"),
    "typer": ("MIT", "https://github.com/fastapi/typer"),
    "python-jose": ("MIT", "https://github.com/mpdavis/python-jose"),
    "pyyaml": ("MIT", "https://pyyaml.org/"),
    "structlog": ("MIT OR Apache-2.0", "https://www.structlog.org/"),
    "snntorch": ("MIT", "https://snntorch.readthedocs.io/"),
    "pdfkit": ("MIT", "https://github.com/JazzCore/python-pdfkit"),
    "brainflow": ("MIT", "https://github.com/brainflow-dev/brainflow"),
    "gymnasium": ("MIT", "https://github.com/Farama-Foundation/Gymnasium"),
    "meilisearch": ("MIT", "https://github.com/meilisearch/meilisearch-python"),
    "redis": ("MIT", "https://github.com/redis/redis-py"),
    "email-validator": (
        "Unlicense",
        "https://github.com/JoshData/python-email-validator",
    ),
    "matplotlib": (
        "Matplotlib License (PSF-based, BSD-compatible)",
        "https://matplotlib.org/",
    ),
    # --- Dev tooling (still distributed in source tree) ---
    "ruff": ("MIT", "https://docs.astral.sh/ruff/"),
    "black": ("MIT", "https://github.com/psf/black"),
    "isort": ("MIT", "https://pycqa.github.io/isort/"),
    "mypy": ("MIT", "https://www.mypy-lang.org/"),
    "pre-commit": ("MIT", "https://pre-commit.com/"),
    "pytest": ("MIT", "https://docs.pytest.org/"),
    "pytest-cov": ("MIT", "https://github.com/pytest-dev/pytest-cov"),
    "pytest-mock": ("MIT", "https://github.com/pytest-dev/pytest-mock"),
    "vcrpy": ("MIT", "https://github.com/kevin1024/vcrpy"),
    "mkdocs-material": ("MIT", "https://squidfunk.github.io/mkdocs-material/"),
}

DART_OVERRIDES: dict[str, tuple[str, str]] = {
    "flutter": ("BSD-3-Clause", "https://flutter.dev/"),
    "cupertino_icons": ("MIT", "https://pub.dev/packages/cupertino_icons"),
    "flutter_inappwebview": (
        "Apache-2.0",
        "https://pub.dev/packages/flutter_inappwebview",
    ),
    "desktop_webview_window": (
        "MIT",
        "https://pub.dev/packages/desktop_webview_window",
    ),
    "flutter_riverpod": ("MIT", "https://pub.dev/packages/flutter_riverpod"),
    "riverpod_annotation": ("MIT", "https://pub.dev/packages/riverpod_annotation"),
    "go_router": ("BSD-3-Clause", "https://pub.dev/packages/go_router"),
    "http": ("BSD-3-Clause", "https://pub.dev/packages/http"),
    "path": ("BSD-3-Clause", "https://pub.dev/packages/path"),
    "path_provider": ("BSD-3-Clause", "https://pub.dev/packages/path_provider"),
    "shared_preferences": (
        "BSD-3-Clause",
        "https://pub.dev/packages/shared_preferences",
    ),
    "package_info_plus": ("BSD-3-Clause", "https://pub.dev/packages/package_info_plus"),
    "url_launcher": ("BSD-3-Clause", "https://pub.dev/packages/url_launcher"),
    "crypto": ("BSD-3-Clause", "https://pub.dev/packages/crypto"),
    "file_picker": ("MIT", "https://pub.dev/packages/file_picker"),
    "intl": ("BSD-3-Clause", "https://pub.dev/packages/intl"),
    "json_annotation": ("BSD-3-Clause", "https://pub.dev/packages/json_annotation"),
    "shimmer": ("BSD-3-Clause", "https://pub.dev/packages/shimmer"),
    "web_socket_channel": (
        "BSD-3-Clause",
        "https://pub.dev/packages/web_socket_channel",
    ),
    "uuid": ("MIT", "https://pub.dev/packages/uuid"),
    "zeta_flutter": ("MIT", "https://pub.dev/packages/zeta_flutter"),
}

# Dependencies that require explicit human review before redistribution.
COMPLIANCE_NOTES = """\
The following direct dependencies require explicit human review before
distributing builds that include them. Auto-detected license ids above are a
starting point, not legal advice.

**Non-standard / use-restricted**

- `nengo`, `nengo-loihi` — Nengo's license is free for academic/personal use but
  restricts commercial use. Confirm redistribution compatibility with AGPL-3.0
  distribution before shipping commercial builds.

**Proprietary vendor SDKs (keep optional; never bundle; record EULA + attribution)**

- `akida`, `akida-models`, `cnn2snn` — BrainChip Akida SDK, proprietary EULA.
- `samna` — SynSense runtime, proprietary EULA.
- `metavision-sdk` — Prophesee Metavision SDK, proprietary EULA.
- `pynq` — BSD-3-Clause Python layer, but ships with proprietary AMD/Xilinx
  bitstreams/overlays that remain under vendor terms.

  These SDKs are declared only as optional extras and are not distributed with
  this project. Do not move them onto unconditional startup paths.

**Copyleft — AGPL-compatible but confirm per distribution**

- `psycopg2-binary` — LGPL-3.0-or-later with OpenSSL exception.
- `sinabs`, `rockpool` — AGPL-3.0 (compatible; preserve their notices).
- `brian2`, `pyNN` — CeCILL-2.1 (GPL-compatible French copyleft).
- `tqdm` — MPL-2.0 (file-level copyleft).
- `norse`, `py-spinnaker2` — LGPL-3.0.
- `flutter_inappwebview` — Apache-2.0; retain its NOTICE file in distributions.

**Verify exact license before relying on auto-detection**

- `snntorch`, `sc-neurocore`, `zeta_flutter`, `desktop_webview_window`,
  `lava-nc` — confirm the resolved license id against the upstream source.
"""

NORMALIZE_RE = re.compile(r"[-_.]+")
# PEP 508: name[extras]<specifier> ; marker  /  or  name @ url
REQ_NAME_RE = re.compile(r"^\s*([A-Za-z0-9][A-Za-z0-9._-]*)")
SPEC_RE = re.compile(r"(===|==|~=|!=|>=|<=|>|<)\s*[^,;\s]+")


def normalize(name: str) -> str:
    return NORMALIZE_RE.sub("-", name).lower()


@dataclass
class Dependency:
    name: str
    spec: str = ""
    optional: bool = False
    ecosystem: str = "python"
    sources: set[str] = field(default_factory=set)


def parse_requirement(req: str) -> tuple[str, str] | None:
    """Return (raw_name, version_spec) for a PEP 508 requirement string."""
    if not req or req.strip().startswith("#"):
        return None
    # Strip environment markers.
    req = req.split(";", 1)[0].strip()
    if not req:
        return None
    # git/url form: "pkg @ git+https://..."
    if "@" in req and "://" in req.split("@", 1)[1]:
        name = req.split("@", 1)[0].strip()
        name = REQ_NAME_RE.match(name).group(1) if REQ_NAME_RE.match(name) else name
        return name, "(vcs/url)"
    match = REQ_NAME_RE.match(req)
    if not match:
        return None
    name = match.group(1)
    specs = ",".join(m.group(0).replace(" ", "") for m in SPEC_RE.finditer(req))
    return name, specs


def poetry_spec(value: object) -> str:
    if isinstance(value, str):
        return value if value != "*" else "(any)"
    if isinstance(value, dict):
        v = value.get("version")
        return v if isinstance(v, str) and v != "*" else "(any)"
    if isinstance(value, list):
        return "(multiple constraints)"
    return "(any)"


def collect_python(deps: dict[str, Dependency]) -> None:
    for path in sorted(ROOT.glob("**/pyproject.toml")):
        if any(
            part in {".venv", "venv", "build", "dist", "node_modules", ".git"}
            for part in path.parts
        ):
            continue
        rel = path.relative_to(ROOT).as_posix()
        try:
            data = tomllib.loads(path.read_text(encoding="utf-8"))
        except (tomllib.TOMLDecodeError, OSError) as exc:
            print(f"warning: skipping {rel}: {exc}", file=sys.stderr)
            continue

        project = data.get("project", {})
        # PEP 621 dependencies
        for req in project.get("dependencies", []) or []:
            _add_python(deps, req, rel, optional=False)
        for reqs in (project.get("optional-dependencies", {}) or {}).values():
            for req in reqs or []:
                _add_python(deps, req, rel, optional=True)

        # Poetry dependencies
        poetry = data.get("tool", {}).get("poetry", {})
        for name, value in (poetry.get("dependencies", {}) or {}).items():
            if name.lower() == "python":
                continue
            optional = isinstance(value, dict) and bool(value.get("optional"))
            _record(deps, name, poetry_spec(value), optional, "python", rel)
        for group in (poetry.get("group", {}) or {}).values():
            for name, value in (group.get("dependencies", {}) or {}).items():
                if name.lower() == "python":
                    continue
                _record(deps, name, poetry_spec(value), True, "python", rel)


def _add_python(
    deps: dict[str, Dependency], req: str, rel: str, *, optional: bool
) -> None:
    parsed = parse_requirement(req)
    if not parsed:
        return
    name, spec = parsed
    _record(deps, name, spec, optional, "python", rel)


def _record(
    deps: dict[str, Dependency],
    name: str,
    spec: str,
    optional: bool,
    ecosystem: str,
    rel: str,
) -> None:
    norm = normalize(name)
    if norm in FIRST_PARTY or name in FIRST_PARTY:
        return
    key = f"{ecosystem}:{norm}"
    existing = deps.get(key)
    if existing is None:
        deps[key] = Dependency(
            name=name,
            spec=spec or "(any)",
            optional=optional,
            ecosystem=ecosystem,
            sources={rel},
        )
    else:
        existing.sources.add(rel)
        # If any manifest needs it unconditionally, it is not optional overall.
        existing.optional = existing.optional and optional
        if existing.spec in {"", "(any)"} and spec not in {"", "(any)"}:
            existing.spec = spec


def collect_dart(deps: dict[str, Dependency]) -> None:
    for path in sorted(ROOT.glob("**/pubspec.yaml")):
        if any(
            part in {"build", ".dart_tool", ".git", "node_modules"}
            for part in path.parts
        ):
            continue
        rel = path.relative_to(ROOT).as_posix()
        try:
            data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
        except yaml.YAMLError as exc:
            print(f"warning: skipping {rel}: {exc}", file=sys.stderr)
            continue
        for name, value in (data.get("dependencies", {}) or {}).items():
            if name == "flutter":
                continue
            if isinstance(value, dict) and ("path" in value or "sdk" in value):
                continue  # local path package or SDK-bundled, not third-party
            spec = value if isinstance(value, str) else "(any)"
            _record(deps, name, str(spec), False, "dart", rel)


def resolve_python_license(name: str) -> tuple[str, str]:
    norm = normalize(name)
    if norm in PY_OVERRIDES:
        return PY_OVERRIDES[norm]
    try:
        meta = importlib_metadata.metadata(name)
    except importlib_metadata.PackageNotFoundError:
        return "UNKNOWN (not installed)", _pypi_url(name)
    spdx = _license_from_metadata(meta)
    home = _homepage_from_metadata(meta) or _pypi_url(name)
    return spdx, home


def _license_from_metadata(meta) -> str:
    expr = meta.get("License-Expression")
    if expr:
        return expr.strip()
    classifiers = meta.get_all("Classifier") or []
    osi = [c.split("::")[-1].strip() for c in classifiers if c.startswith("License ::")]
    if osi:
        return "; ".join(dict.fromkeys(osi))
    lic = (meta.get("License") or "").strip()
    if lic and "\n" not in lic and len(lic) <= 80:
        return lic
    if lic:
        return "see package metadata"
    return "UNKNOWN"


def _homepage_from_metadata(meta) -> str:
    home = meta.get("Home-page")
    if home:
        return home.strip()
    for url in meta.get_all("Project-URL") or []:
        label, _, link = url.partition(",")
        if label.strip().lower() in {"homepage", "repository", "source"}:
            return link.strip()
    for url in meta.get_all("Project-URL") or []:
        _, _, link = url.partition(",")
        if link.strip():
            return link.strip()
    return ""


def _pypi_url(name: str) -> str:
    return f"https://pypi.org/project/{name}/"


def resolve_dart_license(name: str, lock_index: dict[str, dict]) -> tuple[str, str]:
    if name in DART_OVERRIDES:
        return DART_OVERRIDES[name]
    info = lock_index.get(name)
    if info:
        spdx = _detect_license_text(info.get("license_text", ""))
        if spdx != "UNKNOWN":
            return spdx, f"https://pub.dev/packages/{name}"
    return "UNKNOWN (see LICENSE in pub cache)", f"https://pub.dev/packages/{name}"


PUB_CACHE_CANDIDATES = [
    Path.home() / ".pub-cache" / "hosted" / "pub.dev",
    Path.home() / ".pub-cache" / "hosted" / "pub.dartlang.org",
]


def build_dart_lock_index() -> dict[str, dict]:
    """Map package name -> {version, license_text} from any pubspec.lock + pub cache."""
    index: dict[str, dict] = {}
    for lock in ROOT.glob("**/pubspec.lock"):
        if any(part in {"build", ".dart_tool", ".git"} for part in lock.parts):
            continue
        try:
            data = yaml.safe_load(lock.read_text(encoding="utf-8")) or {}
        except yaml.YAMLError:
            continue
        for name, entry in (data.get("packages", {}) or {}).items():
            if name in index or entry.get("source") != "hosted":
                continue
            version = str(entry.get("version", "")).strip()
            text = ""
            for base in PUB_CACHE_CANDIDATES:
                pkg_dir = base / f"{name}-{version}"
                lic = pkg_dir / "LICENSE"
                if lic.is_file():
                    try:
                        text = lic.read_text(encoding="utf-8", errors="replace")
                    except OSError:
                        text = ""
                    break
            index[name] = {"version": version, "license_text": text}
    return index


def _detect_license_text(text: str) -> str:
    if not text:
        return "UNKNOWN"
    head = text[:4000].lower()
    if "apache license" in head and "2.0" in head:
        return "Apache-2.0"
    if "mit license" in head or (
        "permission is hereby granted, free of charge" in head
    ):
        return "MIT"
    if "gnu affero general public license" in head:
        return "AGPL-3.0"
    if "gnu lesser general public license" in head:
        return "LGPL-3.0"
    if "gnu general public license" in head:
        return "GPL-3.0"
    if "mozilla public license" in head and "2.0" in head:
        return "MPL-2.0"
    if "redistribution and use in source and binary forms" in head:
        if "neither the name" in head:
            return "BSD-3-Clause"
        return "BSD-2-Clause"
    if "cecill" in head:
        return "CeCILL-2.1"
    return "UNKNOWN"


def render(deps: dict[str, Dependency]) -> str:
    dart_index = build_dart_lock_index()
    rows_by_eco: dict[str, list[tuple]] = {"python": [], "dart": []}
    for dep in deps.values():
        if dep.ecosystem == "python":
            spdx, home = resolve_python_license(dep.name)
        else:
            spdx, home = resolve_dart_license(dep.name, dart_index)
        rows_by_eco[dep.ecosystem].append(
            (spdx, dep.name, dep.spec, dep.optional, home)
        )

    lines: list[str] = []
    lines.append("# Third-Party Notices")
    lines.append("")
    lines.append(
        "NeuroMorphicToolKit is distributed under the GNU Affero General Public "
        "License v3.0 or later (AGPL-3.0-or-later). It also incorporates the "
        "third-party open-source components listed below, each retaining its own "
        "license."
    )
    lines.append("")
    lines.append(
        "This file is generated by `scripts/generate_third_party_notices.py` and "
        "covers **direct** dependencies declared in the repository's manifests. "
        "Run `make notices` to regenerate it; CI runs `make notices-check` to keep "
        "it current. Do not edit it by hand."
    )
    lines.append("")
    lines.append(
        "Entries marked _optional_ come from optional dependency groups/extras and "
        "are not installed by default."
    )
    lines.append("")

    eco_titles = [
        ("python", "Python Dependencies"),
        ("dart", "Dart / Flutter Dependencies"),
    ]
    for eco, title in eco_titles:
        rows = rows_by_eco[eco]
        if not rows:
            continue
        lines.append(f"## {title}")
        lines.append("")
        # Group by license, deterministic ordering.
        by_license: dict[str, list[tuple]] = {}
        for spdx, name, spec, optional, home in rows:
            by_license.setdefault(spdx, []).append((name, spec, optional, home))
        for spdx in sorted(by_license, key=str.lower):
            lines.append(f"### {spdx}")
            lines.append("")
            lines.append("| Package | Version constraint | Optional | Homepage |")
            lines.append("| --- | --- | --- | --- |")
            for name, spec, optional, home in sorted(
                by_license[spdx], key=lambda r: r[0].lower()
            ):
                opt = "yes" if optional else "no"
                lines.append(f"| `{name}` | `{spec}` | {opt} | {home} |")
            lines.append("")

    lines.append("## Compliance Notes")
    lines.append("")
    lines.append(COMPLIANCE_NOTES.rstrip())
    lines.append("")
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="exit non-zero if the committed file is stale",
    )
    parser.add_argument(
        "--stdout",
        action="store_true",
        help="print to stdout instead of writing the file",
    )
    args = parser.parse_args()

    deps: dict[str, Dependency] = {}
    collect_python(deps)
    collect_dart(deps)
    content = render(deps)

    if args.stdout:
        sys.stdout.write(content)
        return 0

    if args.check:
        current = OUTPUT.read_text(encoding="utf-8") if OUTPUT.exists() else ""
        if current != content:
            print(
                "THIRD_PARTY_NOTICES.md is out of date. Run `make notices` "
                "(or python3 scripts/generate_third_party_notices.py) and commit the result.",
                file=sys.stderr,
            )
            return 1
        print("THIRD_PARTY_NOTICES.md is up to date.")
        return 0

    OUTPUT.write_text(content, encoding="utf-8")
    print(f"Wrote {OUTPUT.relative_to(ROOT)} ({len(deps)} direct dependencies).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
