from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DEPLOYMENT_ASSETS = ROOT / "nmtk" / "neuro_toolkit" / "assets" / "deployment"


def test_remote_deploy_repairs_workspace_volume_before_unprivileged_start() -> None:
    """Remote deploys must not leave launcher workspace state root-owned."""
    remote_override = (ROOT / "docker-compose.remote.yml").read_text()
    install_script = (DEPLOYMENT_ASSETS / "install.sh").read_text()

    assert 'launcher-control:\n    user: "0:0"' not in remote_override
    assert "compose run --rm --no-deps --user 0:0" in install_script
    assert "--cap-add CHOWN" in install_script
    assert "--cap-add FOWNER" not in install_script
    assert "chown -R appuser:appuser /app/state /app/data" in install_script
    assert "continuing because backend deployment is unaffected" in install_script
    assert "compose ps -a" in install_script
    assert "compose logs --tail 200 suite_api launcher-control" in install_script
    assert "Suite API did not become ready; diagnostics captured." in install_script
