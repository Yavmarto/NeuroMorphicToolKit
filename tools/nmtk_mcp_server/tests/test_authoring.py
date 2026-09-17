from __future__ import annotations

from tools.nmtk_mcp_server.authoring import build_authoring_guide

GRAMMAR = """# CNL Grammar

Intro text.

## Neuron Rules

Neuron A has tau 10 ms.
Neuron B connects to neuron A.

## Synapse Rules

Synapses declare weights.
"""

SUPPORT = """# Support Matrix

## Nengo

LIF neurons are supported.
Hardware flashing is not described here.

## Akida

Akida export support is scaffolded.
"""


def test_authoring_guide_extracts_matching_heading_excerpts() -> None:
    guide = build_authoring_guide(
        grammar_text=GRAMMAR,
        support_matrix_text=SUPPORT,
        topic="neuron",
    )

    assert guide.topic == "neuron"
    assert len(guide.sections) == 2
    assert guide.sections[0].title == "Neuron Rules"
    assert "Neuron A has tau" in guide.sections[0].excerpt
    assert guide.sections[0].source_uri == "nmtk://cnl/grammar/current"


def test_authoring_guide_falls_back_without_inventing_claims() -> None:
    guide = build_authoring_guide(
        grammar_text=GRAMMAR,
        support_matrix_text=SUPPORT,
        topic="loihi",
        max_chars_per_section=80,
    )

    assert guide.topic == "loihi"
    assert guide.sections
    assert all("loihi" not in section.excerpt.lower() for section in guide.sections)
    assert any(
        section.source_uri == "nmtk://cnl/support-matrix/current"
        for section in guide.sections
    )
    assert guide.caveats == [
        "Guide excerpts are copied from canonical resources only; no backend or hardware support is inferred."
    ]


def test_authoring_guide_preserves_source_resource_uris() -> None:
    guide = build_authoring_guide(
        grammar_text=GRAMMAR,
        support_matrix_text=SUPPORT,
        grammar_uri="custom://grammar",
        support_matrix_uri="custom://support",
    )

    assert {section.source_uri for section in guide.sections} == {
        "custom://grammar",
        "custom://support",
    }
