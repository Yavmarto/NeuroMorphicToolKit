"""Tests for the framework environment registry."""
from __future__ import annotations

from nmtk_env_manager.framework_envs import FRAMEWORK_ENVS, TARGET_TO_KERNEL


def test_all_envs_have_required_keys():
    for env in FRAMEWORK_ENVS:
        assert "slug" in env, f"Missing 'slug' in {env}"
        assert "display" in env, f"Missing 'display' in {env}"
        assert "targets" in env, f"Missing 'targets' in {env}"
        assert env["targets"], f"Empty targets list in {env['slug']}"


def test_slugs_are_unique():
    slugs = [env["slug"] for env in FRAMEWORK_ENVS]
    assert len(slugs) == len(set(slugs)), "Duplicate slugs in FRAMEWORK_ENVS"


def test_slugs_are_nmtk_prefixed():
    for env in FRAMEWORK_ENVS:
        assert env["slug"].startswith("nmtk-"), (
            f"Slug {env['slug']!r} must start with 'nmtk-'"
        )


def test_target_to_kernel_covers_all_targets():
    for env in FRAMEWORK_ENVS:
        for target in env["targets"]:
            assert target in TARGET_TO_KERNEL, (
                f"Target {target!r} from {env['slug']} missing in TARGET_TO_KERNEL"
            )
            assert TARGET_TO_KERNEL[target] == env["slug"]


def test_target_to_kernel_no_unmapped_targets():
    all_targets = {t for env in FRAMEWORK_ENVS for t in env["targets"]}
    assert set(TARGET_TO_KERNEL.keys()) == all_targets


def test_all_envs_have_packages_key():
    for env in FRAMEWORK_ENVS:
        assert "packages" in env, f"Missing 'packages' key in {env['slug']}"
        assert isinstance(env["packages"], list), (
            f"'packages' in {env['slug']} must be a list, got {type(env['packages'])}"
        )
