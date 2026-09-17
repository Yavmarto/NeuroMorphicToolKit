"""Akida package generation — thin shim over AkidaBackend.

Exposes ``generate_akida_package`` as a module-level function so that
``export.py`` can import it as ``akida_generator`` and tests can patch it at
``neurochip.app.routers.export.akida_generator.generate_akida_package``.
"""

from .akida_backend import generate_akida_package

__all__ = ["generate_akida_package"]
