"""Tests for Layer 2 Cross-Sentence Consistency Validator."""

import re

from neurocnl.cnl.types import ParsedSentence
from neurocnl.layers.layer2_validator import validate_cross_sentence

# ---------------------------------------------------------------------------
# Minimal biological sentence fixture builder (replaces deleted cnl_parser.parse)
# ---------------------------------------------------------------------------

_FLOAT_PAT = r"[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?"


def _parse_bio_sentence(sentence: str) -> ParsedSentence:
    """Build a minimal ParsedSentence-compatible dict from a biological CNL sentence.

    Handles the sentence forms used by the layer2 validator tests without
    depending on the deleted cnl_parser module.
    """
    s = sentence.strip()
    result: ParsedSentence = {
        "concept": "",
        "subject": "",
        "action": "",
        "verb": "",
        "negated": False,
        "condition": None,
        "raw": s,
    }

    # "The network MUST contain a/an <kind> <name> population of <n> neurons"
    m = re.match(
        r"The network MUST contain an? (\w+)\s+([\w ]+?)\s+population of ([-\d]+) neurons",
        s,
        re.IGNORECASE,
    )
    if m:
        result["concept"] = "population_coding"
        result["subject"] = m.group(2).strip() + " population"
        result["action"] = "contain"
        result["verb"] = "MUST"
        result["condition"] = m.group(3)
        return result

    # "The <subject> MUST NOT fire DURING the refractory period of <val> seconds"
    m = re.match(
        r"The (.+?) MUST NOT fire DURING the refractory period of ("
        + _FLOAT_PAT
        + r")",
        s,
        re.IGNORECASE,
    )
    if m:
        result["concept"] = "refractory_period"
        result["subject"] = m.group(1).strip()
        result["action"] = "fire"
        result["verb"] = "MUST NOT"
        result["negated"] = True
        result["condition"] = m.group(2)
        return result

    # "The <subject> membrane potential MUST decay WITH time constant of <val> seconds"
    m = re.match(
        r"The (.+?) membrane potential MUST decay WITH time constant of ("
        + _FLOAT_PAT
        + r")",
        s,
        re.IGNORECASE,
    )
    if m:
        result["concept"] = "membrane_potential_decay"
        result["subject"] = m.group(1).strip() + " membrane potential"
        result["action"] = "decay"
        result["verb"] = "MUST"
        result["condition"] = m.group(2)
        return result

    # "The <subject> MUST fire ONLY IF membrane potential exceeds <val>"
    m = re.match(
        r"The (.+?) MUST (?:fire|emit a spike) ONLY IF membrane potential exceeds ("
        + _FLOAT_PAT
        + r")",
        s,
        re.IGNORECASE,
    )
    if m:
        result["concept"] = "threshold_firing"
        result["subject"] = m.group(1).strip()
        result["action"] = "fire"
        result["verb"] = "MUST"
        result["condition"] = "exceeds " + m.group(2)
        return result

    # "The <subject> population MUST encode input using <n> neurons."
    m = re.match(
        r"The (.+?) population MUST encode input using ([\d]+) neurons",
        s,
        re.IGNORECASE,
    )
    if m:
        result["concept"] = "population_coding"
        result["subject"] = m.group(1).strip() + " population"
        result["action"] = "encode"
        result["verb"] = "MUST"
        result["condition"] = m.group(2)
        return result

    # "The connection from <src> to <dst> MUST have WITH synaptic weight of <val>"
    m = re.match(
        r"The connection from (.+?) to (.+?) MUST have WITH synaptic weight of ("
        + _FLOAT_PAT
        + r")",
        s,
        re.IGNORECASE,
    )
    if m:
        result["concept"] = "synaptic_weight"
        result["subject"] = (
            f"connection from {m.group(1).strip()} to {m.group(2).strip()}"
        )
        result["action"] = "have"
        result["verb"] = "MUST"
        result["condition"] = m.group(3)
        return result

    # "The connection from <src> to <dst> MUST be inhibitory with weight of <val>."
    m = re.match(
        r"The connection from (.+?) to (.+?) MUST be inhibitory(?:\s+with weight of ("
        + _FLOAT_PAT
        + r"))?",
        s,
        re.IGNORECASE,
    )
    if m:
        result["concept"] = "inhibitory_connection"
        result["subject"] = (
            f"connection from {m.group(1).strip()} to {m.group(2).strip()}"
        )
        result["action"] = "inhibit"
        result["verb"] = "MUST"
        result["condition"] = m.group(3)
        return result

    # "The connection from <src> to <dst> MUST be inhibitory."
    m = re.match(
        r"The connection from (.+?) to (.+?) MUST be inhibitory\.",
        s,
        re.IGNORECASE,
    )
    if m:
        result["concept"] = "inhibitory_connection"
        result["subject"] = (
            f"connection from {m.group(1).strip()} to {m.group(2).strip()}"
        )
        result["action"] = "inhibit"
        result["verb"] = "MUST"
        result["condition"] = None
        return result

    # "The <src> MUST project to <dst>"
    m = re.match(
        r"The (.+?) MUST (?:project|connect) to (?:both )?(.+?)(?:\s+AND\s+(.+))?$",
        s,
        re.IGNORECASE,
    )
    if m:
        targets = [m.group(2).strip()]
        if m.group(3):
            targets.append(m.group(3).strip())
        result["concept"] = "projection"
        result["subject"] = m.group(1).strip()
        result["action"] = "project"
        result["verb"] = "MUST"
        result["condition"] = " AND ".join(targets)
        return result

    # Fallback: unknown sentence
    result["concept"] = "unknown"
    result["subject"] = s
    return result


def _parse_specs(sentences: list[str]) -> list[ParsedSentence]:
    res = []
    for i, s in enumerate(sentences):
        parsed = _parse_bio_sentence(s)
        parsed["line"] = i + 1
        res.append(parsed)
    return res


# === Consistent Specs ===


def test_consistent_reflex_arc() -> None:
    """A well-formed reflex arc should pass all checks."""
    specs = _parse_specs(
        [
            "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0",
            "The sensory neuron MUST NOT fire DURING the refractory period of 0.002 seconds",
            "The sensory neuron membrane potential MUST decay WITH time constant of 0.02 seconds",
            "The motor neuron MUST fire ONLY IF membrane potential exceeds 0.8",
            "The connection from sensory neuron to motor neuron MUST have WITH synaptic weight of 1.0",
        ]
    )
    report = validate_cross_sentence(specs)
    assert report["overall"] is True
    assert len(report["checks_failed"]) == 0
    assert "no_dangling_connections" in report["checks_passed"]
    assert "no_contradictory_params" in report["checks_passed"]


def test_neurons_found() -> None:
    """Should extract all neuron names from specs."""
    specs = _parse_specs(
        [
            "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0",
            "The motor neuron MUST fire ONLY IF membrane potential exceeds 0.8",
        ]
    )
    report = validate_cross_sentence(specs)
    assert "sensory" in report["neurons_found"]
    assert "motor" in report["neurons_found"]


def test_connections_found() -> None:
    """Should extract connection endpoints."""
    specs = _parse_specs(
        [
            "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0",
            "The motor neuron MUST fire ONLY IF membrane potential exceeds 0.8",
            "The connection from sensory neuron to motor neuron MUST have WITH synaptic weight of 1.0",
        ]
    )
    report = validate_cross_sentence(specs)
    assert ("sensory", "motor") in report["connections_found"]


# === Dangling Connection Detection ===


def test_dangling_source() -> None:
    """Connection with undefined source should fail."""
    specs = _parse_specs(
        [
            "The motor neuron MUST fire ONLY IF membrane potential exceeds 0.8",
            "The connection from sensory neuron to motor neuron MUST have WITH synaptic weight of 1.0",
        ]
    )
    report = validate_cross_sentence(specs)
    assert report["overall"] is False
    failed_checks = [f["check"] for f in report["checks_failed"]]
    assert "dangling_connection_source" in failed_checks


def test_dangling_target() -> None:
    """Connection with undefined target should fail."""
    specs = _parse_specs(
        [
            "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0",
            "The connection from sensory neuron to motor neuron MUST have WITH synaptic weight of 1.0",
        ]
    )
    report = validate_cross_sentence(specs)
    assert report["overall"] is False
    failed_checks = [f["check"] for f in report["checks_failed"]]
    assert "dangling_connection_target" in failed_checks


def test_dangling_inhibitory() -> None:
    """Inhibitory connection with undefined endpoint should fail."""
    specs = _parse_specs(
        [
            "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0",
            "The connection from interneuron to sensory neuron MUST be inhibitory.",
        ]
    )
    report = validate_cross_sentence(specs)
    assert report["overall"] is False
    failed_checks = [f["check"] for f in report["checks_failed"]]
    assert "dangling_connection_source" in failed_checks


# === Contradictory Parameters ===


def test_contradictory_threshold() -> None:
    """Same neuron with two different thresholds should fail."""
    specs = _parse_specs(
        [
            "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0",
            "The sensory neuron MUST fire ONLY IF membrane potential exceeds 2.0",
        ]
    )
    report = validate_cross_sentence(specs)
    assert report["overall"] is False
    failed_checks = [f["check"] for f in report["checks_failed"]]
    assert "contradictory_params" in failed_checks


def test_same_threshold_no_contradiction() -> None:
    """Same neuron with identical thresholds is fine."""
    specs = _parse_specs(
        [
            "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0",
            "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0",
        ]
    )
    report = validate_cross_sentence(specs)
    assert "no_contradictory_params" in report["checks_passed"]


def test_different_neurons_no_contradiction() -> None:
    """Different neurons can have different thresholds."""
    specs = _parse_specs(
        [
            "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0",
            "The motor neuron MUST fire ONLY IF membrane potential exceeds 2.0",
        ]
    )
    report = validate_cross_sentence(specs)
    assert "no_contradictory_params" in report["checks_passed"]


# === Report Structure ===


def test_report_structure() -> None:
    """Report should have the expected keys."""
    specs = _parse_specs(
        [
            "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0",
        ]
    )
    report = validate_cross_sentence(specs)
    assert "checks_passed" in report
    assert "checks_failed" in report
    assert "neurons_found" in report
    assert "connections_found" in report
    assert "overall" in report


# === Edge Cases ===


def test_empty_network_fails() -> None:
    """Empty network should fail empty_network check."""
    report = validate_cross_sentence([])
    assert report["overall"] is False
    failed_checks = [f["check"] for f in report["checks_failed"]]
    assert "empty_network" in failed_checks


def test_single_node_network_fails() -> None:
    """Network with only one neuron should fail single_node_network check."""
    specs = _parse_specs(
        ["The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0"]
    )
    report = validate_cross_sentence(specs)
    assert report["overall"] is False
    failed_checks = [f["check"] for f in report["checks_failed"]]
    assert "single_node_network" in failed_checks


def test_zero_edge_network_fails() -> None:
    """Network with neurons but no connections should fail zero_edge_network check."""
    specs = _parse_specs(
        [
            "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0",
            "The motor neuron MUST fire ONLY IF membrane potential exceeds 1.0",
        ]
    )
    report = validate_cross_sentence(specs)
    assert report["overall"] is False
    failed_checks = [f["check"] for f in report["checks_failed"]]
    assert "zero_edge_network" in failed_checks


def test_layer2_failure_includes_normalized_fields() -> None:
    specs = _parse_specs(
        [
            "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0",
            "The motor neuron MUST fire ONLY IF membrane potential exceeds 1.0",
            "The connection from sensory neuron to motor neuron MUST have WITH synaptic weight of 0.0",
        ]
    )
    report = validate_cross_sentence(specs)

    zero_weight = next(
        f for f in report["checks_failed"] if f["check"] == "zero_weight_synapse"
    )
    assert zero_weight["code"] == "zero_weight_synapse"
    assert zero_weight["message"] == zero_weight["detail"]
    assert zero_weight["lines"] == [3]


def test_population_defines_neuron() -> None:
    """Population coding spec should define a neuron for connection checks."""
    specs = _parse_specs(
        [
            "The sensory population MUST encode input using 100 neurons.",
            "The motor neuron MUST fire ONLY IF membrane potential exceeds 1.0",
            "The connection from sensory population to motor neuron MUST be inhibitory.",
        ]
    )
    report = validate_cross_sentence(specs)
    assert report["overall"] is True


def test_population_and_neuron_suffixes_match_for_template_style_specs() -> None:
    """Population declarations and neuron-like endpoint names compare by role name."""
    specs = _parse_specs(
        [
            "The network MUST contain an excitatory sensory population of 1 neurons",
            "The network MUST contain an excitatory interneuron population of 60 neurons",
            "The network MUST contain an excitatory motor population of 1 neurons",
            "The sensory population MUST fire ONLY IF membrane potential exceeds 0.8",
            "The interneuron population MUST fire ONLY IF membrane potential exceeds 0.55",
            "The motor population MUST emit a spike ONLY IF membrane potential exceeds 0.6",
            "The sensory population MUST project to interneuron population",
            "The interneuron population MUST project to motor population",
            "The sensory population MUST project to motor population",
            "The connection from sensory population to interneuron population MUST have WITH synaptic weight of 1.5",
            "The connection from interneuron population to motor population MUST have WITH synaptic weight of 1.2",
            "The connection from sensory population to motor population MUST have WITH synaptic weight of 0.5",
        ]
    )

    report = validate_cross_sentence(specs)

    assert report["overall"] is True
    assert "no_orphan_populations" in report["checks_passed"]


# === Network Topology Tests ===


def test_network_topology_not_dangling() -> None:
    """Declared populations should not trigger dangling connection errors."""
    specs = _parse_specs(
        [
            "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0",
            "The network MUST contain an inhibitory interneuron population of 30 neurons",
            "The connection from sensory neuron to interneuron MUST have WITH synaptic weight of 0.5",
        ]
    )
    report = validate_cross_sentence(specs)
    # interneuron should be recognized as a declared population
    dangling_checks = [
        f["check"] for f in report["checks_failed"] if f["check"].startswith("dangling")
    ]
    assert len(dangling_checks) == 0


def test_orphan_population_detected() -> None:
    """A population declared but never connected should trigger orphan check."""
    specs = _parse_specs(
        [
            "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0",
            "The network MUST contain an inhibitory interneuron population of 30 neurons",
            # No connection involving interneuron
        ]
    )
    report = validate_cross_sentence(specs)
    orphan_checks = [
        f for f in report["checks_failed"] if f["check"] == "orphan_population"
    ]
    assert len(orphan_checks) == 1
    assert "interneuron" in orphan_checks[0]["detail"]


def test_no_orphan_when_connected() -> None:
    """A declared population with a connection should not be orphan."""
    specs = _parse_specs(
        [
            "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0",
            "The network MUST contain an inhibitory interneuron population of 30 neurons",
            "The connection from interneuron to sensory neuron MUST be inhibitory.",
        ]
    )
    report = validate_cross_sentence(specs)
    orphan_checks = [
        f for f in report["checks_failed"] if f["check"] == "orphan_population"
    ]
    assert len(orphan_checks) == 0


def test_no_orphan_when_projected() -> None:
    """A declared population targeted by a projection should not be orphan."""
    specs = _parse_specs(
        [
            "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0",
            "The network MUST contain an excitatory relay population of 50 neurons",
            "The sensory neuron MUST project to both relay AND motor neuron",
        ]
    )
    report = validate_cross_sentence(specs)
    orphan_checks = [
        f for f in report["checks_failed"] if f["check"] == "orphan_population"
    ]
    # relay is targeted by projection, should not be orphan
    assert len(orphan_checks) == 0


def test_network_topology_neuron_extracted() -> None:
    """Network topology populations should appear in neurons_found."""
    specs = _parse_specs(
        [
            "The network MUST contain an inhibitory interneuron population of 30 neurons",
        ]
    )
    report = validate_cross_sentence(specs)
    assert "interneuron" in report["neurons_found"]


# === New Edge-Case Invariants ===


def test_negative_threshold_without_inhibition_fails() -> None:
    """Neuron with negative threshold must be marked as inhibitory."""
    specs = _parse_specs(
        [
            "The sensory neuron MUST fire ONLY IF membrane potential exceeds -1.0",
        ]
    )
    report = validate_cross_sentence(specs)
    assert report["overall"] is False
    failed_checks = [f["check"] for f in report["checks_failed"]]
    assert "negative_threshold_without_inhibition" in failed_checks


def test_negative_threshold_with_inhibition_passes() -> None:
    """Inhibitory population can have negative threshold."""
    specs = _parse_specs(
        [
            "The network MUST contain an inhibitory interneuron population of 30 neurons",
            "The interneuron MUST fire ONLY IF membrane potential exceeds -1.0",
        ]
    )
    report = validate_cross_sentence(specs)
    # interneuron is inhibitory, so negative threshold is allowed
    failed_checks = [f["check"] for f in report["checks_failed"]]
    assert "negative_threshold_without_inhibition" not in failed_checks


def test_zero_synaptic_weight_fails() -> None:
    """Synaptic weight of 0.0 should fail."""
    specs = _parse_specs(
        [
            "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0",
            "The motor neuron MUST fire ONLY IF membrane potential exceeds 0.8",
            "The connection from sensory neuron to motor neuron MUST have WITH synaptic weight of 0.0",
        ]
    )
    report = validate_cross_sentence(specs)
    assert report["overall"] is False
    failed_checks = [f["check"] for f in report["checks_failed"]]
    assert "zero_weight_synapse" in failed_checks


def test_zero_inhibitory_weight_fails() -> None:
    """Inhibitory weight of 0.0 should fail."""
    specs = _parse_specs(
        [
            "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0",
            "The motor neuron MUST fire ONLY IF membrane potential exceeds 0.8",
            "The connection from sensory neuron to motor neuron MUST be inhibitory with weight of 0.0.",
        ]
    )
    report = validate_cross_sentence(specs)
    assert report["overall"] is False
    failed_checks = [f["check"] for f in report["checks_failed"]]
    assert "zero_weight_synapse" in failed_checks


def test_self_referencing_connection_fails() -> None:
    """Neuron connecting to itself should fail."""
    specs = _parse_specs(
        [
            "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0",
            "The connection from sensory neuron to sensory neuron MUST have WITH synaptic weight of 1.0",
        ]
    )
    report = validate_cross_sentence(specs)
    assert report["overall"] is False
    failed_checks = [f["check"] for f in report["checks_failed"]]
    assert "self_referencing_connection" in failed_checks
