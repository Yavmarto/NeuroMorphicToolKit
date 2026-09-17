"""Tests for per-target kernel assignment in notebook generation."""

from __future__ import annotations

import pytest

from backend.app.routers.notebook import (
    _BASE_KERNEL_DISPLAY,
    _BASE_KERNEL_SLUG,
    _FRAMEWORKS,
    _kernelspec_for,
)


@pytest.mark.parametrize(
    "target,expected_slug",
    [
        ("snntorch_sim", "nmtk-snntorch"),
        ("nengo", "nmtk-nengo"),
        ("rockpool", "nmtk-rockpool"),
        ("sinabs", "nmtk-sinabs"),
        ("brian2", "nmtk-brian2"),
        ("lava_sim", "nmtk-lava"),
        ("lava", "nmtk-lava"),
        ("pynn", "nmtk-pynn"),
        ("akida", "nmtk-akida"),
    ],
)
def test_framework_target_gets_framework_kernel(target, expected_slug):
    ks = _kernelspec_for(target)
    assert ks["name"] == expected_slug, (
        f"Target {target!r}: expected kernel {expected_slug!r}, got {ks['name']!r}"
    )
    assert ks["language"] == "python"
    assert ks["display_name"]  # non-empty string


@pytest.mark.parametrize("target", ["sc_neurocore_sim", "sc_neurocore_fpga", "generic"])
def test_base_targets_get_base_kernel(target):
    ks = _kernelspec_for(target)
    assert ks["name"] == _BASE_KERNEL_SLUG


def test_unknown_target_falls_back_to_base():
    ks = _kernelspec_for("totally_unknown_target_xyz")
    assert ks["name"] == _BASE_KERNEL_SLUG
    assert ks["display_name"] == _BASE_KERNEL_DISPLAY


def test_kernelspec_has_required_fields():
    for target in list(_FRAMEWORKS.keys()) + ["generic", "sc_neurocore_sim"]:
        ks = _kernelspec_for(target)
        assert {
            "name",
            "display_name",
            "language",
        } <= ks.keys(), f"Missing kernelspec fields for target {target!r}: {ks}"


def test_all_target_kernel_slugs_are_nmtk_prefixed():
    for target, config in _FRAMEWORKS.items():
        if config.get("kernel") is not None:
            slug, _display = config["kernel"]
            assert slug.startswith("nmtk-"), (
                f"Kernel slug {slug!r} for target {target!r} must start with 'nmtk-'"
            )
