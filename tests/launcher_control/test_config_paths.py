"""Launcher control config path tests."""

import os
import tempfile
import unittest
from unittest import mock


class TestConfigPaths(unittest.TestCase):
    def tearDown(self):
        import importlib

        import nmtk.launcher_control.config as cfg

        # Restore module-level constants to their defaults after each test
        for key in ("NMTK_STATE_DIR", "NMTK_DATA_DIR"):
            os.environ.pop(key, None)
        importlib.reload(cfg)

    def test_default_paths_use_repo_root(self):
        """Without env vars set, all paths fall under REPO_ROOT."""
        import importlib

        import nmtk.launcher_control.config as cfg

        # Use empty strings so mock.patch.dict can restore them properly;
        # config.py strips and checks truthiness, so "" falls through to defaults.
        with mock.patch.dict(os.environ, {"NMTK_STATE_DIR": "", "NMTK_DATA_DIR": ""}):
            importlib.reload(cfg)
            assert cfg.STATE_FILE.is_relative_to(cfg.REPO_ROOT)
            assert cfg.SETTINGS_FILE.is_relative_to(cfg.REPO_ROOT)
            assert cfg.WORKSPACE_FILE.is_relative_to(cfg.REPO_ROOT)
            assert cfg.DEPLOYMENT_STATE_FILE.is_relative_to(cfg.REPO_ROOT)
            assert cfg.DEPLOYMENT_SECRET_FILE.is_relative_to(cfg.REPO_ROOT)
            assert cfg.SUITE_API_ENV_ROOT.is_relative_to(cfg.REPO_ROOT)
            assert cfg.MODULES_MANIFEST.is_relative_to(cfg.REPO_ROOT)

    def test_nmtk_state_dir_overrides_state_files(self):
        """NMTK_STATE_DIR redirects the 4 module/workspace/settings state files."""
        import importlib

        import nmtk.launcher_control.config as cfg

        with tempfile.TemporaryDirectory() as state_dir, mock.patch.dict(
            os.environ, {"NMTK_STATE_DIR": state_dir}
        ):
                importlib.reload(cfg)
                assert str(cfg.STATE_FILE).startswith(state_dir)
                assert str(cfg.SETTINGS_FILE).startswith(state_dir)
                assert str(cfg.WORKSPACE_FILE).startswith(state_dir)
                assert str(cfg.DEPLOYMENT_STATE_FILE).startswith(state_dir)

    def test_nmtk_data_dir_overrides_secrets(self):
        """NMTK_DATA_DIR redirects deployment_secrets and suite_api_env."""
        import importlib

        import nmtk.launcher_control.config as cfg

        with tempfile.TemporaryDirectory() as data_dir, mock.patch.dict(
            os.environ, {"NMTK_DATA_DIR": data_dir}
        ):
                importlib.reload(cfg)
                assert str(cfg.DEPLOYMENT_SECRET_FILE).startswith(data_dir)
                assert str(cfg.SUITE_API_ENV_ROOT).startswith(data_dir)
