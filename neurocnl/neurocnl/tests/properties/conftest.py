"""Conftest for property-based tests."""

from hypothesis import Verbosity, settings

settings.register_profile("ci", max_examples=200, verbosity=Verbosity.normal, derandomize=True)
settings.load_profile("ci")
