from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BUNDLE = ROOT / "nmtk" / "neuro_toolkit" / "assets" / "deployment"


def test_install_registers_boot_recovery_before_starting_containers() -> None:
    install_script = (BUNDLE / "install.sh").read_text()

    install_index = install_script.index('nmtk-stack.sh install "$ENGINE"')
    start_index = install_script.index('nmtk-stack.sh start "$ENGINE"')
    assert install_index < start_index
    assert "could not be registered to start automatically" in install_script


def test_stack_helper_enables_verified_user_service_without_resetting_data() -> None:
    helper = (BUNDLE / "nmtk-stack.sh").read_text()

    assert "nmtk-stack.service" in helper
    assert "WantedBy=default.target" in helper
    assert "systemctl --user is-enabled --quiet nmtk-stack.service" in helper
    assert "up -d --no-build --remove-orphans" in helper
    assert "down -v" not in helper


def test_docker_uses_restart_policies_while_podman_uses_the_user_service() -> None:
    compose = (BUNDLE / "docker-compose.yml").read_text()
    helper = (BUNDLE / "nmtk-stack.sh").read_text()

    assert "restart: unless-stopped" in compose
    assert '[ "$ENGINE" = "podman" ] || return 0' in helper
    assert "systemctl --user enable nmtk-stack.service" in helper
