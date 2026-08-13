from suite_api.domains.jupyter.router import _env_manager_path


def test_env_manager_path_rewrites_public_jupyter_prefix() -> None:
    assert _env_manager_path("/api/jupyter/executions") == "/nmtk-envs/api/executions"
    assert _env_manager_path("/api/jupyter/jobs/abc123") == "/nmtk-envs/api/jobs/abc123"
    assert (
        _env_manager_path("/api/jupyter/environments/nmtk-snntorch/packages")
        == "/nmtk-envs/api/environments/nmtk-snntorch/packages"
    )


def test_doctor_path_rewrites_to_worker_extension() -> None:
    assert _env_manager_path("/api/jupyter/doctor") == "/nmtk-envs/api/doctor"
