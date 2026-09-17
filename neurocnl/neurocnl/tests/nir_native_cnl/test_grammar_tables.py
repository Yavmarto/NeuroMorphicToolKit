"""Coverage tests for the NIR-Native CNL grammar tables.

The grammar tables in :mod:`neurocnl.nir_cnl.grammar_tables` are a
contract surface — every Primitive must have exactly one canonical
English noun phrase, every noun phrase must be unique across all
Primitives, and the per-Primitive parameter map must be in lock-step
with the noun phrase map. This module pins those invariants so a
silent table edit (an entry deleted, a phrase duplicated) cannot ship.

_Validates: Requirements 1.2, 2.1_
"""

from __future__ import annotations

from neurocnl.nir_cnl.grammar_tables import (
    noun_phrase_to_primitive,
    parameter_phrases,
    primitive_phrases,
)

# The 18 documented upstream ``nir.*`` Primitives, plus the 4
# CNL-Studio-internal snnTorch neuron extensions
# (Synaptic/RSynaptic/Leaky/RLeaky) added once ``notebook.py`` codegen
# support for them turned out to have no matching CNL grammar entry —
# a canvas-built network using these neurons silently lost them (and
# every edge touching them) on every CNL render. The ``test_*`` names
# below pin this set verbatim so a regression that drops a Primitive
# surfaces as a missing-keys assertion rather than a silent renderer
# fall-through.
_EXPECTED_PRIMITIVES: frozenset[str] = frozenset(
    {
        "Input",
        "Output",
        "IF",
        "LIF",
        "LI",
        "CubaLIF",
        "CubaLI",
        "I",
        "Linear",
        "Affine",
        "Scale",
        "Conv1d",
        "Conv2d",
        "AvgPool2d",
        "SumPool2d",
        "Flatten",
        "Delay",
        "Threshold",
        "Synaptic",
        "RSynaptic",
        "Leaky",
        "RLeaky",
    }
)


def test_primitive_phrases_covers_every_documented_primitive() -> None:
    """``primitive_phrases`` must list exactly the documented Primitives."""
    assert set(primitive_phrases.keys()) == _EXPECTED_PRIMITIVES


def test_primitive_phrases_has_no_duplicate_noun_phrases() -> None:
    """Each Primitive must map to a unique English noun phrase."""
    phrases = list(primitive_phrases.values())
    assert len(set(phrases)) == len(_EXPECTED_PRIMITIVES), (
        f"Duplicate canonical noun phrases found: {[p for p in phrases if phrases.count(p) > 1]}"
    )


def test_parameter_phrases_covers_every_primitive() -> None:
    """``parameter_phrases`` must be keyed by the same Primitives."""
    assert set(parameter_phrases.keys()) == _EXPECTED_PRIMITIVES


def test_noun_phrase_to_primitive_is_inverse_of_primitive_phrases() -> None:
    """The inverse table must map every lower-cased phrase back to its
    Primitive class name."""
    for primitive, phrase in primitive_phrases.items():
        assert noun_phrase_to_primitive[phrase.lower()] == primitive
    # Inverse coverage: the inverse table must have exactly the same
    # number of entries as the forward table.
    assert len(noun_phrase_to_primitive) == len(primitive_phrases)
