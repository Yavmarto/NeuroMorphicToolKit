"""Shared fixture base for the launcher control service test subpackage."""

import json
import tempfile
import unittest
from pathlib import Path
from typing import Any
from unittest import mock
import nmtk.launcher_control.server as launcher_server
import nmtk.launcher_control.runtime_shared as launcher_runtime_shared
import nmtk.launcher_control.settings_service as launcher_settings_service
import nmtk.launcher_control.module_environment as launcher_module_environment
import nmtk.launcher_control.module_lifecycle as launcher_module_lifecycle
import nmtk.launcher_control.module_install as launcher_module_install


PROJECT_ROOT = Path(__file__).resolve().parents[2]


def _stage_overlay_package(staging_dir: Path) -> None:
    staging_dir.mkdir(parents=True, exist_ok=True)
    (staging_dir / "snn_overlay.bit").write_bytes(b"bitstream")
    (staging_dir / "snn_overlay.hwh").write_text("<hwh/>", encoding="utf-8")
    (staging_dir / "overlay_manifest.json").write_text(
        json.dumps(
            {
                "overlay_id": "snn_overlay_v2",
                "overlay_version": "2.0.0",
                "target_part": "xc7z020clg400-1",
                "supported_neuron_models": ["LIF"],
                "supported_weight_bit_widths": [8],
                "max_neurons": 4096,
                "max_neurons_per_layer": 1024,
                "max_synapses": 262144,
                "max_populations": 4,
                "max_layers": 4,
                "dma_ip_name": "axi_dma_0",
                "snn_ip_name": "snn_engine_0",
                "register_map": {
                    "resolved_from_hwh": True,
                    "base_address": 1073741824,
                    "control_reg_offset": 0,
                    "global_interrupt_enable_offset": 4,
                    "interrupt_enable_offset": 8,
                    "interrupt_status_offset": 12,
                    "weights_ptr_offset": 16,
                    "layer_config_ptr_offset": 28,
                    "layer_count_offset": 40,
                    "weight_count_offset": 48,
                    "timestep_count_offset": 56,
                    "dma_channel": "axi_dma_0",
                    "timestep_us": 1000,
                },
                "weight_layout": {
                    "format": "int8_dense_row_major_ddr",
                    "storage": "dma_ddr",
                    "element_bytes": 1,
                    "max_entries": 262144,
                    "matrix_order": "post_by_pre",
                },
                "layer_config_layout": {
                    "format": "uint32_words",
                    "storage": "dma_ddr",
                    "words_per_layer": 8,
                    "max_layers": 4,
                    "fields": {
                        "input_size": 0,
                        "output_size": 1,
                        "weight_offset": 2,
                        "threshold": 3,
                        "leak_shift": 4,
                        "refractory": 5,
                    },
                },
            },
            indent=2,
        ),
        encoding="utf-8",
    )


class LauncherControlServiceTestBase(unittest.TestCase):
    def setUp(self) -> None:
        self._tempdir = tempfile.TemporaryDirectory()
        self.repo_root = Path(self._tempdir.name) / "repo"
        assets_dir = self.repo_root / "nmtk" / "neuro_toolkit" / "assets"
        assets_dir.mkdir(parents=True, exist_ok=True)
        (self.repo_root / "dummy_module").mkdir(parents=True, exist_ok=True)
        self._resolved_versions: dict[str, str | None] = {"dummy": None}
        self._resolver_calls: list[str] = []

        (assets_dir / "modules.json").write_text(
            json.dumps(
                [
                    {
                        "id": "dummy",
                        "name": "Dummy Module",
                        "description": "Used for launcher control tests",
                        "icon": "extension",
                        "port": 8123,
                        "installPath": "dummy_module",
                        "sourcePath": ".",
                        "runPath": ".",
                        "uvicornTarget": "app.main:app",
                        "hasFrontend": True,
                        "frontendStatus": "Yes",
                        "requiresMuJoCo": False,
                        "version": "1.0.0",
                        "remoteUrl": "https://api.github.com/repos/example/dummy",
                        "akidaRuntime": {
                            "supportedPlatforms": ["linux", "windows"],
                            "pythonRange": ">=3.10,<3.13",
                            "requiredPackages": [
                                "tensorflow==2.19.*",
                                "akida==2.19.1",
                                "cnn2snn==2.19.1",
                                "quantizeml==1.2.4",
                                "onnx>=1.17,<2",
                                "akida-models==1.13.1",
                            ],
                            "docsUrl": "https://doc.brainchipinc.com/installation.html",
                            "localModeFallback": "simulator_only",
                        },
                    }
                ]
            ),
            encoding="utf-8",
        )

        self._patches = [
            mock.patch.object(launcher_server, "REPO_ROOT", self.repo_root),
            mock.patch.object(
                launcher_server,
                "MODULES_MANIFEST",
                assets_dir / "modules.json",
            ),
            mock.patch.object(launcher_runtime_shared, "REPO_ROOT", self.repo_root),
            mock.patch.object(
                launcher_runtime_shared,
                "MODULES_MANIFEST",
                assets_dir / "modules.json",
            ),
            mock.patch.object(launcher_module_environment, "REPO_ROOT", self.repo_root),
            mock.patch.object(launcher_module_install, "REPO_ROOT", self.repo_root),
            mock.patch.object(
                launcher_module_lifecycle,
                "MODULES_MANIFEST",
                assets_dir / "modules.json",
            ),
            mock.patch.object(
                launcher_server,
                "STATE_FILE",
                self.repo_root / "nmtk" / "neuro_toolkit" / "module_states.json",
            ),
            mock.patch.object(
                launcher_module_lifecycle,
                "STATE_FILE",
                self.repo_root / "nmtk" / "neuro_toolkit" / "module_states.json",
            ),
            mock.patch.object(
                launcher_server,
                "SETTINGS_FILE",
                self.repo_root / "nmtk" / "neuro_toolkit" / "launcher_settings.json",
            ),
            mock.patch.object(
                launcher_settings_service,
                "SETTINGS_FILE",
                self.repo_root / "nmtk" / "neuro_toolkit" / "launcher_settings.json",
            ),
            mock.patch.object(
                launcher_server,
                "WORKSPACE_FILE",
                self.repo_root / "nmtk" / "neuro_toolkit" / "workspace_state.json",
            ),
            mock.patch.object(
                launcher_server,
                "DEPLOYMENT_STATE_FILE",
                self.repo_root / "nmtk" / "neuro_toolkit" / "deployment_state.json",
            ),
            mock.patch.object(
                launcher_server,
                "DEPLOYMENT_SECRET_FILE",
                self.repo_root / ".nmtk" / "deployment_secrets.json",
            ),
        ]
        for patcher in self._patches:
            patcher.start()
            self.addCleanup(patcher.stop)

        self.state = launcher_server.LauncherControlState(
            remote_version_resolver=self._resolve_remote_version
        )
        self._fake_venv_python = self._create_fake_venv_python()

    def tearDown(self) -> None:
        self.state.shutdown()
        self._tempdir.cleanup()

    def _create_fake_venv_python(self) -> Path:
        python_path = self.repo_root / "dummy_module" / "venv" / "bin" / "python"
        python_path.parent.mkdir(parents=True, exist_ok=True)
        python_path.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        python_path.chmod(0o755)
        return python_path

    def _create_fake_poetry_python(self) -> Path:
        python_path = self.repo_root / ".poetry-envs" / "dummy" / "bin" / "python"
        python_path.parent.mkdir(parents=True, exist_ok=True)
        python_path.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        python_path.chmod(0o755)
        return python_path

    def _write_poetry_pyproject(self) -> None:
        pyproject = self.repo_root / "dummy_module" / "pyproject.toml"
        pyproject.write_text(
            "\n".join(
                [
                    "[tool.poetry]",
                    'name = "dummy"',
                    'version = "0.1.0"',
                    "",
                    "[build-system]",
                    'requires = ["poetry-core>=1.0.0"]',
                    'build-backend = "poetry.core.masonry.api"',
                ]
            ),
            encoding="utf-8",
        )

    def _create_fake_inproject_poetry_python_symlink(self) -> tuple[Path, Path]:
        python_path = self.repo_root / "dummy_module" / ".venv" / "bin" / "python"
        base_python = self.repo_root / "python-base" / "bin" / "python"
        python_path.parent.mkdir(parents=True, exist_ok=True)
        base_python.parent.mkdir(parents=True, exist_ok=True)
        base_python.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        base_python.chmod(0o755)
        python_path.symlink_to(base_python)
        return python_path, base_python

    def _resolve_remote_version(self, module: dict[str, Any]) -> str | None:
        module_id = str(module["id"])
        self._resolver_calls.append(module_id)
        return self._resolved_versions.get(module_id)

    def _reload_state_with_modules(self, modules: list[dict[str, Any]]) -> None:
        manifest_path = (
            self.repo_root / "nmtk" / "neuro_toolkit" / "assets" / "modules.json"
        )
        manifest_path.write_text(json.dumps(modules), encoding="utf-8")
        self.state.shutdown()
        self.state = launcher_server.LauncherControlState(
            remote_version_resolver=self._resolve_remote_version
        )
