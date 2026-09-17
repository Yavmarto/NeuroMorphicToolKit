#!/usr/bin/env python3
"""Fail when a GitHub workflow file cannot be parsed or references a missing job.

GitHub refuses to run a workflow that has a `needs:` entry pointing at a job that
does not exist. The failure is silent: no run appears, so the required-check gate
stops guarding the branch. CEL-306 was exactly this, from a leftover
`test-neurodreamhand` entry. `.github/workflows/ci.yml` runs this so an invalid
workflow fails the `ci-passed` gate instead of disappearing, and the scheduled
runner-health workflow runs it too (the self-referential case where ci.yml itself
is the invalid file).

Checks, per workflow file:
  - the file parses as YAML and has a `jobs:` mapping
  - every `needs:` entry names a job in the same file
  - every `needs.<job>` and `needs.<job>.outputs.<name>` expression names a job
    that exists and declares that output

Exit code 0 when every file is valid, 1 when any file is invalid, 2 on bad usage.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path
from typing import Any, Iterable

try:
    import yaml
except ImportError:  # pragma: no cover - exercised only without PyYAML
    print(
        "error: PyYAML is required (python -m pip install pyyaml)",
        file=sys.stderr,
    )
    raise SystemExit(2)

NEEDS_REF = re.compile(r"needs\.([A-Za-z0-9_-]+)")
OUTPUT_REF = re.compile(r"needs\.([A-Za-z0-9_-]+)\.outputs\.([A-Za-z0-9_-]+)")
DEFAULT_GLOBS = (".github/workflows/*.yml", ".github/workflows/*.yaml")


def iter_strings(value: Any) -> Iterable[str]:
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for item in value.values():
            yield from iter_strings(item)
    elif isinstance(value, list):
        for item in value:
            yield from iter_strings(item)


def normalize_needs(value: Any) -> list[str]:
    if isinstance(value, str):
        return [value]
    if isinstance(value, list):
        return [item for item in value if isinstance(item, str)]
    return []


def line_of(text: str, needle: str) -> int | None:
    for number, line in enumerate(text.splitlines(), start=1):
        if needle in line:
            return number
    return None


def validate_document(path: Path, text: str, document: Any) -> list[str]:
    errors: list[str] = []
    if not isinstance(document, dict):
        return [f"{path}: the file must be a YAML mapping"]

    jobs = document.get("jobs")
    if not isinstance(jobs, dict) or not jobs:
        return [f"{path}: no `jobs:` mapping found"]

    job_ids = set(jobs)

    for job_id, job in jobs.items():
        if not isinstance(job, dict):
            continue
        for dependency in normalize_needs(job.get("needs")):
            if dependency not in job_ids:
                line = line_of(text, dependency)
                where = f"{path}:{line}" if line else f"{path}"
                errors.append(
                    f"{where}: job '{job_id}' needs '{dependency}', "
                    "which is not defined in this file"
                )

    for value in iter_strings(document):
        for dependency in NEEDS_REF.findall(value):
            if dependency not in job_ids:
                line = line_of(text, f"needs.{dependency}")
                where = f"{path}:{line}" if line else f"{path}"
                errors.append(
                    f"{where}: expression references needs.{dependency}, "
                    "which is not defined in this file"
                )
        for job_id, output in OUTPUT_REF.findall(value):
            if job_id not in job_ids:
                continue
            declared = jobs.get(job_id, {})
            outputs = declared.get("outputs") if isinstance(declared, dict) else None
            if not isinstance(outputs, dict) or output not in outputs:
                line = line_of(text, f"needs.{job_id}.outputs.{output}")
                where = f"{path}:{line}" if line else f"{path}"
                errors.append(
                    f"{where}: expression references output "
                    f"'{job_id}.outputs.{output}', which the job does not declare"
                )

    return errors


def collect_files(root: Path, globs: Iterable[str]) -> list[Path]:
    files: list[Path] = []
    for pattern in globs:
        files.extend(sorted(root.glob(pattern)))
    return files


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=".")
    parser.add_argument("--glob", action="append", dest="globs")
    args = parser.parse_args(argv)

    root = Path(args.root)
    globs = tuple(args.globs) if args.globs else DEFAULT_GLOBS
    files = collect_files(root, globs)
    if not files:
        print(f"error: no workflow files matched {globs} under {root}", file=sys.stderr)
        return 2

    errors: list[str] = []
    for path in files:
        text = path.read_text(encoding="utf-8")
        try:
            document = yaml.safe_load(text)
        except yaml.YAMLError as error:
            location = getattr(error, "problem_mark", None)
            where = f"{path}:{location.line + 1}" if location else str(path)
            errors.append(f"{where}: YAML parse error: {error}")
            continue
        errors.extend(validate_document(path, text, document))

    in_actions = os.environ.get("GITHUB_ACTIONS") == "true"
    for error in errors:
        if in_actions:
            parts = error.split(":", 2)
            if len(parts) == 3 and parts[1].isdigit():
                print(f"::error file={parts[0]},line={parts[1]}::{parts[2].strip()}")
                continue
        print(error, file=sys.stderr)

    if errors:
        print(
            f"{len(errors)} workflow error(s) in {len(files)} file(s)", file=sys.stderr
        )
        return 1
    print(f"OK: {len(files)} workflow file(s) valid")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
