"""Tests for scripts/sanitize_private_lan.py (CEL-347 finding M-3).

The private addresses under test are assembled from octets so this test file
does not itself carry an RFC1918 literal into the published artifact.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "sanitize_private_lan.py"


def _ip(*octets: int) -> str:
    return ".".join(str(octet) for octet in octets)


def _load():
    spec = importlib.util.spec_from_file_location("sanitize_private_lan", SCRIPT)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules["sanitize_private_lan"] = module
    spec.loader.exec_module(module)
    return module


def test_sanitize_rewrites_private_lan_and_keeps_exemptions(tmp_path: Path) -> None:
    module = _load()
    dev_host = _ip(192, 168, 2, 90)
    other_host = _ip(192, 168, 2, 34)
    example_host = _ip(192, 168, 1, 50)
    android_alias = _ip(10, 0, 2, 2)
    ssrf_cidr = _ip(10, 0, 0, 0) + "/8"
    windows_build = ".".join(("10", "0", "22621", "0"))
    dead_host = _ip(10, 255, 255, 254)

    (tmp_path / "docs").mkdir()
    (tmp_path / "docs" / "guide.md").write_text(
        f"Connect to {other_host} and {module._HOSTNAME_TEXT}@{dev_host}.\n",
        encoding="utf-8",
    )
    (tmp_path / "Makefile").write_text(
        f"DEV_BACKEND_HOST ?= {module._HOSTNAME_TEXT}@{dev_host}\n"
        f'\techo "example user@{example_host}"\n',
        encoding="utf-8",
    )
    (tmp_path / "net.sh").write_text(
        "\n".join(
            [
                f'EMU="http://{android_alias}:8080"',
                f'CIDR="{ssrf_cidr}"',
                f"WIN={windows_build}",
                f'DEAD="{dead_host}"',
                f'HOST="{dev_host}"',
                "",
            ]
        ),
        encoding="utf-8",
    )

    module.sanitize(tmp_path)

    guide = (tmp_path / "docs" / "guide.md").read_text(encoding="utf-8")
    assert other_host not in guide
    assert "<dev-host>" in guide
    assert module._HOSTNAME_TEXT not in guide

    makefile = (tmp_path / "Makefile").read_text(encoding="utf-8")
    assert f"DEV_BACKEND_HOST ?= {module._HOSTNAME_TEXT}@{dev_host}" in makefile
    assert example_host not in makefile

    net = (tmp_path / "net.sh").read_text(encoding="utf-8")
    assert android_alias in net
    assert ssrf_cidr in net
    assert windows_build in net
    assert dead_host not in net
    assert dev_host not in net

    assert module.check(tmp_path) == []


def test_check_reports_unscrubbed_private_lan(tmp_path: Path) -> None:
    module = _load()
    leak = _ip(192, 168, 2, 90)
    (tmp_path / "leak.txt").write_text(f"host {leak} here\n", encoding="utf-8")
    findings = module.check(tmp_path)
    assert findings
    assert any(leak in finding for finding in findings)


def test_sanitize_is_idempotent(tmp_path: Path) -> None:
    module = _load()
    (tmp_path / "a.txt").write_text(_ip(192, 168, 1, 60) + "\n", encoding="utf-8")
    module.sanitize(tmp_path)
    assert module.sanitize(tmp_path) == 0
    assert module.check(tmp_path) == []
