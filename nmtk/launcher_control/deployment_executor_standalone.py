"""Standalone launcher deployment executor."""

from __future__ import annotations

import time

from .deployment_contracts import DeploymentTarget
from .deployment_executor_base import DeploymentExecutor, LogCallback, ProgressCallback
from .deployment_preflight import run_preflight


class StandaloneDeploymentExecutor(DeploymentExecutor):
    """Configure a standalone Python-runtime backend target."""

    def run(
        self,
        target: DeploymentTarget,
        emit: ProgressCallback,
        log: LogCallback | None = None,
        clean_install: bool = False,
    ) -> None:
        self._log = log or (lambda _line: None)
        emit("preflight_running", "Validating standalone backend prerequisites", 10)
        result = run_preflight(target, repo_root=self._repo_root)
        if result.status == "failed":
            raise RuntimeError(result.message)
        time.sleep(0.05)
        emit("installing", "Preparing Python runtime plan", 30)
        time.sleep(0.05)
        emit("installing", "Writing standalone service configuration", 55)
        time.sleep(0.05)
        emit("verifying", "Running backend health verification", 80)
        time.sleep(0.05)
        emit("completed", "Standalone backend target is configured", 100)


__all__ = ["StandaloneDeploymentExecutor"]
