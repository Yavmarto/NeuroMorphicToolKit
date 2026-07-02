"""neurocli root CLI — registers all sub-commands."""

from __future__ import annotations

import typer

app = typer.Typer(
    name="neuro",
    help="NMTK command-line interface: scaffold, manage, and share neuromorphic projects.",
    no_args_is_help=True,
    add_completion=False,
)


def _register_subcommands() -> None:
    from neurocli.deploy import deploy_command  # noqa: PLC0415
    from neurocli.hub import hub_app  # noqa: PLC0415
    from neurocli.lifecycle import install_command, run_command, status_command  # noqa: PLC0415
    from neurocli.new import new_command  # noqa: PLC0415
    from neurocli.studio import studio_app  # noqa: PLC0415

    app.command("new")(new_command)
    app.command("deploy")(deploy_command)
    app.command("status")(status_command)
    app.command("install")(install_command)
    app.command("run")(run_command)
    app.add_typer(hub_app, name="hub")
    app.add_typer(studio_app, name="studio")


_register_subcommands()
