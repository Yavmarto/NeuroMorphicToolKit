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
    # Diagnostics run through compose_with_timeout so a wedged container runtime
    # cannot turn failure capture into its own hang.
    assert 'compose_with_timeout "$DIAGNOSTICS_TIMEOUT" ps -a' in install_script
    assert (
        'compose_with_timeout "$DIAGNOSTICS_TIMEOUT" \\\n'
        "    logs --tail 200 suite_api launcher-control"
    ) in install_script
    assert "Suite API did not become ready; diagnostics captured." in install_script
    assert "cleanup_runtime docker" in install_script
    assert "cleanup_runtime podman" in install_script
    assert "reconciling_existing_install" in install_script
    assert "Existing %s installation is not accessible" in install_script
    assert 'if [ "$CLEAN_INSTALL" = "true" ]' in install_script
    assert '"$runtime" volume rm -f $volumes' in install_script
    assert "Factory reset removing" in install_script
    assert "Preserving NMTK server data" in install_script


def test_remote_install_bounds_every_registry_and_runtime_step() -> None:
    """No install step may stall the app on an unchanging percentage."""
    install_script = (DEPLOYMENT_ASSETS / "install.sh").read_text()

    # Each long step runs under an explicit timeout instead of waiting forever.
    assert 'compose_with_timeout "$DOWN_TIMEOUT" "${DOWN_ARGS[@]}"' in install_script
    assert 'compose_with_timeout "$PULL_TIMEOUT" pull' in install_script
    assert (
        'timeout --signal=TERM --kill-after=30s "${UP_TIMEOUT}s" \\\n'
        '  bash ./nmtk-stack.sh start "$ENGINE"'
        in install_script
    )
    assert "timeout --signal=TERM --kill-after=30s" in install_script

    # A timeout is reported as an actionable failure, not left as progress.
    assert "Downloading the backend images timed out after" in install_script
    assert "Starting the backend containers timed out after" in install_script
    assert "Stopping the existing NMTK containers timed out after" in install_script
    assert "fail_stage" in install_script

    # The pull republishes its stage so the client can tell slow from dead.
    assert "Pulling backend images ($((SECONDS - pull_started))s elapsed)" in (
        install_script
    )


def test_production_suite_api_has_a_writable_ephemeral_notebook_mirror() -> None:
    """Read-only production Suite API must still support generated notebook execution."""
    prod_override = (ROOT / "docker-compose.prod.yml").read_text()

    assert "- /home/app/notebooks:mode=1777" in prod_override


def test_production_suite_api_persists_writable_application_data() -> None:
    """Uploads and SQLite stores must use the app-owned persistent volume."""
    prod_override = (ROOT / "docker-compose.prod.yml").read_text()
    suite_api_override = prod_override.split("\n  neurosense-hw-worker:", 1)[0]

    assert "- suite_api_data:/home/app/data" in suite_api_override
    assert "\n      - /home/app/data\n" not in suite_api_override
    assert "os.access(data_dir, os.W_OK)" in suite_api_override
    assert "/api/suite/health" in suite_api_override
