"""NeuroCNL → Neuro-Dream-Hand verification handoff.

This thin wrapper module is the NeuroCNL-side entry point for triggering a
runtime verification session against a freshly flashed Teensy.  It delegates
entirely to ``neurodreamhand.toolkit_handoff``, raising
:exc:`DreamHandNotAvailableError` when the package is not installed so that
callers receive a clear diagnostic rather than a bare ``ImportError``.

Example::

    from neurocnl.handoff.dreamhand_verification_hook import (
        DreamHandNotAvailableError,
        run_dreamhand_verification_handoff,
    )

    try:
        report = run_dreamhand_verification_handoff("/dev/ttyACM0")
    except DreamHandNotAvailableError as exc:
        print(exc)
"""

from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from neurodreamhand.toolkit_handoff import VerificationOptions, VerificationReport


# ---------------------------------------------------------------------------
# Exceptions
# ---------------------------------------------------------------------------


class DreamHandNotAvailableError(RuntimeError):
    """Raised when ``neurodreamhand`` is not installed in the current environment.

    Install it with::

        pip install neurodreamhand
    """


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def run_dreamhand_verification_handoff(
    serial_port: str,
    opts: VerificationOptions | None = None,
) -> VerificationReport:
    """Trigger Neuro-Dream-Hand runtime verification after a successful flash.

    Parameters
    ----------
    serial_port:
        OS path to the Teensy serial device (e.g. ``"/dev/ttyACM0"``).
    opts:
        Optional :class:`~neurodreamhand.toolkit_handoff.VerificationOptions`.
        Pass ``None`` to use defaults (``run_demo=True``, ``run_hitl=False``).

    Returns
    -------
    neurodreamhand.toolkit_handoff.VerificationReport

    Raises
    ------
    DreamHandNotAvailableError
        When ``neurodreamhand`` is not installed.
    """
    try:
        from neurodreamhand.toolkit_handoff import verify_post_flash_runtime
    except ImportError as exc:
        raise DreamHandNotAvailableError(
            "neurodreamhand is not installed. "
            "Install it with: pip install neurodreamhand. "
            f"Original error: {exc}"
        ) from exc

    return verify_post_flash_runtime(serial_port, opts)
