"""Shared CNL spec fixtures for backend endpoint smoke testing.

Owning-module home for the smoke spec so it stays in sync with the parser
that must accept it, instead of living in a root-level CLI script.
"""

ENDPOINT_SMOKE_SPEC = (
    "Define a network named endpoint_smoke.\n"
    "Define an input port named input with shape (1,).\n"
    "Define a LIF neuron named relay with time constant 0.02, resistance 1.0, "
    "leak voltage 0.0, and firing threshold 1.0.\n"
    "Define an output port named output with shape (1,).\n"
    "input connects to relay.\n"
    "relay connects to output."
)
