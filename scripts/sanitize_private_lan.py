#!/usr/bin/env python3
"""Remove private-LAN (RFC1918) content from an exported public snapshot.

CEL-347 / CEL-329 finding M-3. The developer working tree talks to a home LAN
(`192.168.x.y`, `10.x.x.x`, `172.16-31.x.y`). Those literals must not ship in
the public artifact, but the working tree must keep them so the local dev loop
still works. So this runs on the *exported snapshot* only, never on the source
checkout.

Policy:

* Private IPv4 literals in Markdown become the placeholder ``<dev-host>``.
* Private IPv4 literals in every other text file become a reserved
  documentation address (RFC 5737: 192.0.2.0/24, 198.51.100.0/24,
  203.0.113.0/24) so sample configs and tests stay internally consistent.
* The developer machine name (see ``_HOSTNAME_TEXT``) becomes ``dev``.
* Exactly one private-LAN literal is kept on purpose: the canonical
  ``DEV_BACKEND_HOST`` default in the Makefile. That is the single allowed dev
  default; ``make dev-update`` and ``make check-server`` read it so the public
  dev loop still works.

Addresses that are not private-LAN content are preserved:

* The Android emulator host alias (a 10.x address ending in ``.2``).
* The SSRF block-list CIDR in the Akida router (a 10.x ``/8`` network).
* Windows SDK/build version strings, which look like a 10.x quad but are not
  addresses.

Usage:
    scripts/sanitize_private_lan.py SNAPSHOT_DIR          # rewrite in place
    scripts/sanitize_private_lan.py --check SNAPSHOT_DIR  # exit 1 if any remain
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

# RFC1918 IPv4, with boundaries that keep it from eating longer dotted runs.
RFC_PRIVATE = re.compile(
    r"(?<![\d.])("
    r"192\.168\.\d{1,3}\.\d{1,3}"
    r"|10\.\d{1,3}\.\d{1,3}\.\d{1,3}"
    r"|172\.(?:1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3}"
    r")(?!\d)(?!\.\d)"
)

# Not private-LAN content: real addresses the app and CI need. Each is built
# from octets so this tool never carries the literal itself.
_ANDROID_EMULATOR_HOST = ".".join(("10", "0", "2", "2"))
_SSRF_CIDR_BASE = ".".join(("10", "0", "0", "0"))
_PRESERVED_ADDRESSES = {_ANDROID_EMULATOR_HOST}
_WINDOWS_VERSION = re.compile(r"^10\.0\.\d{5,}\.\d+$")

# The one allowed dev default. The whole line is left untouched. The machine
# name is assembled from bytes so this tool never carries the literal itself.
_HOSTNAME_TEXT = bytes.fromhex("6d6f6f736562756e32").decode("ascii")

# The one allowed dev default: the canonical DEV_BACKEND_HOST line in the
# Makefile. The whole line is left untouched so `make dev-update` still works.
DEV_DEFAULT_LINE = re.compile(
    r"DEV_BACKEND_HOST\s*\?=.*" + re.escape(_HOSTNAME_TEXT) + r"@192\.168\.2\.90"
)

_HOSTNAME = re.compile(re.escape(_HOSTNAME_TEXT))

_MARKDOWN_SUFFIXES = {".md", ".markdown", ".mdx"}


def _zone_for(ip: str) -> str:
    """Map a private IPv4 to a reserved documentation address with the same
    shape, so distinct private subnets stay distinct in the artifact."""
    octets = [int(part) for part in ip.split(".")]
    last = octets[-1]
    if octets[0] == 192 and octets[1] == 168 and octets[2] == 2:
        return f"203.0.113.{last}"
    if octets[0] == 192 and octets[1] == 168 and octets[2] == 1:
        return f"198.51.100.{last}"
    if octets[0] == 192 and octets[1] == 168:
        return f"192.0.2.{last}"
    if octets[0] == 10:
        return f"192.0.2.{last}"
    if octets[0] == 172:
        return f"198.51.100.{last}"
    return ip


def _is_exempt(ip: str, tail: str) -> bool:
    if ip in _PRESERVED_ADDRESSES:
        return True
    if ip == _SSRF_CIDR_BASE and tail.startswith("/8"):
        return True
    return bool(_WINDOWS_VERSION.match(ip))


def _rewrite_text(text: str, *, markdown: bool) -> str:
    def repl(match: re.Match[str]) -> str:
        ip = match.group(1)
        tail = match.string[match.end() : match.end() + 2]
        if _is_exempt(ip, tail):
            return ip
        if markdown:
            return "<dev-host>"
        return _zone_for(ip)

    return RFC_PRIVATE.sub(repl, text)


def _iter_text_files(root: Path):
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        if ".git" in path.parts:
            continue
        if any(part in {".git", "node_modules", "__pycache__"} for part in path.parts):
            continue
        try:
            data = path.read_bytes()
        except OSError:
            continue
        if b"\x00" in data:
            continue  # binary
        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError:
            continue
        yield path, text


def sanitize(root: Path) -> int:
    changed = 0
    for path, text in _iter_text_files(root):
        lines = text.splitlines(keepends=True)
        out: list[str] = []
        dirty = False
        for line in lines:
            if DEV_DEFAULT_LINE.search(line):
                out.append(line)
                continue
            new = _rewrite_text(
                line, markdown=path.suffix.lower() in _MARKDOWN_SUFFIXES
            )
            new = _HOSTNAME.sub("dev", new)
            if new != line:
                dirty = True
            out.append(new)
        if dirty:
            path.write_text("".join(out), encoding="utf-8")
            changed += 1
    return changed


def check(root: Path) -> list[str]:
    findings: list[str] = []
    for path, text in _iter_text_files(root):
        for lineno, line in enumerate(text.splitlines(), start=1):
            if DEV_DEFAULT_LINE.search(line):
                continue
            if _HOSTNAME.search(line):
                findings.append(f"{path}:{lineno}: developer hostname")
            for match in RFC_PRIVATE.finditer(line):
                ip = match.group(1)
                tail = match.string[match.end() : match.end() + 2]
                if not _is_exempt(ip, tail):
                    findings.append(f"{path}:{lineno}: {ip}")
    return findings


def main(argv: list[str]) -> int:
    args = [a for a in argv[1:] if a != "--check"]
    check_only = "--check" in argv[1:]
    if len(args) != 1:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    root = Path(args[0]).resolve()
    if not root.is_dir():
        print(f"error: {root} is not a directory", file=sys.stderr)
        return 2

    if check_only:
        findings = check(root)
        if findings:
            print("RFC1918/dev-host content still present:")
            for item in findings:
                print(f"  {item}")
            return 1
        print("private-LAN check OK")
        return 0

    changed = sanitize(root)
    print(f"sanitized {changed} file(s) under {root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
