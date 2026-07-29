"""`GET /api/suite/health` is the contract the in-app backend update rests on.

The launcher reads `version` from it to decide whether to offer an update, so
the field has to be present and has to fall back to something that means "not a
release" rather than to a version-shaped lie.
"""
import importlib

import suite_api.routers.health as health


def _reload_with_version(monkeypatch, raw: str | None) -> str:
    if raw is None:
        monkeypatch.delenv("NMTK_VERSION", raising=False)
    else:
        monkeypatch.setenv("NMTK_VERSION", raw)
    importlib.reload(health)
    return health.BACKEND_VERSION


def test_unstamped_build_reports_dev(monkeypatch) -> None:
    assert _reload_with_version(monkeypatch, None) == "dev"


def test_release_build_reports_its_tag(monkeypatch) -> None:
    # What .github/workflows/release-docker.yml stamps via the Dockerfile ARG.
    assert _reload_with_version(monkeypatch, "1.2.0") == "1.2.0"


def test_blank_version_falls_back_to_dev(monkeypatch) -> None:
    # An empty build-arg must not read as a release with an empty version —
    # the launcher would then compare "" against a real tag and offer an update
    # against an unknown build.
    assert _reload_with_version(monkeypatch, "   ") == "dev"


def test_health_payload_carries_the_version(monkeypatch) -> None:
    import asyncio

    _reload_with_version(monkeypatch, "1.2.0")
    payload = asyncio.run(health.suite_health())
    assert payload == {
        "status": "ok",
        "service": "suite_api",
        "version": "1.2.0",
    }
    # Restore the module for any test importing it afterwards.
    _reload_with_version(monkeypatch, None)
