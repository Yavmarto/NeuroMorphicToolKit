"""Layer 2 Validator — Cross-Sentence Consistency.

Validates that a set of parsed CNL specifications are internally consistent:
- Referenced neurons exist (mentioned in at least one behavioral spec)
- No contradictory parameter values for the same neuron
- Connection graph has no dangling references
"""

import re
from collections import defaultdict
from typing import Any

from neurocnl.cnl.types import ParsedSentence
from neurocnl.nir_cnl.ir_types import NetworkContainer, NIREdgeRecord, NIRNodeRecord


def _population_name(subject: str) -> str:
    """Normalize CNL population/neuron labels for cross-sentence comparison."""
    name = " ".join(subject.strip().lower().split())
    if name.endswith(" membrane potential"):
        name = name[: -len(" membrane potential")]
    for suffix in (" neurons", " neuron", " populations", " population"):
        if name.endswith(suffix):
            name = name[: -len(suffix)]
            break
    return name


def _connection_endpoints_from_subject(subject: str) -> tuple[str, str] | None:
    """Return normalized endpoints from a connection-like subject."""
    normalized_subject = subject.strip()
    if normalized_subject.lower().startswith("connection from "):
        normalized_subject = normalized_subject[len("connection from ") :]
    match = re.match(
        r"(.+?)\s+to\s+(.+)",
        normalized_subject,
        re.IGNORECASE,
    )
    if match is None:
        return None
    return _population_name(match.group(1)), _population_name(match.group(2))


def _connection_endpoints_match(subject: str, source: str, target: str) -> bool:
    endpoints = _connection_endpoints_from_subject(subject)
    return endpoints == (source, target)


def _make_failure(
    code: str,
    message: str,
    *,
    spec: ParsedSentence | None = None,
    specs: list[ParsedSentence] | None = None,
    field: str | None = None,
    value: object | None = None,
) -> dict[str, Any]:
    """Create a normalized Layer 2 failure payload."""
    candidates = specs or ([spec] if spec is not None else [])
    lines = sorted(
        {
            int(candidate["line"])
            for candidate in candidates
            if candidate is not None and candidate.get("line") is not None
        }
    )
    detail: dict[str, Any] = {
        "check": code,
        "detail": message,
        "code": code,
        "message": message,
        "source": "layer2",
        "lines": lines,
    }
    if field is not None:
        detail["field"] = field
    if value is not None:
        detail["value"] = value
    if spec is not None and spec.get("raw"):
        detail["raw"] = spec["raw"]
    return detail


def _extract_neuron_names(parsed_specs: list[ParsedSentence]) -> set[str]:
    """Extract all neuron/population names mentioned in specs."""
    names = set()
    for spec in parsed_specs:
        subject = spec.get("subject", "")
        concept = spec["concept"]

        if (
            concept
            in (
                "threshold_firing",
                "refractory_period",
            )
            or concept == "membrane_potential_decay"
        ):
            names.add(_population_name(subject))
        elif concept in ("synaptic_weight", "axonal_delay"):
            # Subject may be "X to Y" or "connection from X to Y"
            endpoints = _connection_endpoints_from_subject(subject)
            if endpoints is not None:
                names.update(endpoints)
        elif concept == "inhibitory_connection":
            # Subject is "X to Y"
            parts = subject.split(" to ", 1)
            for p in parts:
                names.add(_population_name(p))
        elif concept == "population_coding":
            names.add(_population_name(subject))
        elif concept == "network_topology":
            if "population of" in (spec.get("condition") or ""):
                names.add(_population_name(subject))
        elif concept == "stdp_learning":
            endpoints = _connection_endpoints_from_subject(subject)
            if endpoints is not None:
                names.update(endpoints)

    return names


def _extract_connection_endpoints(
    parsed_specs: list[ParsedSentence],
) -> list[tuple[str, str]]:
    """Extract (source, target) pairs from connection specs."""
    connections = []
    for spec in parsed_specs:
        concept = spec["concept"]
        subject = spec.get("subject", "")

        if concept in ("synaptic_weight", "axonal_delay", "inhibitory_connection"):
            # Subject is "sensory neuron to motor neuron" (no "connection from")
            # or "connection from X to Y" — handle both forms
            endpoints = _connection_endpoints_from_subject(subject)
            if endpoints is not None:
                connections.append(endpoints)
        elif concept == "stdp_learning":
            endpoints = _connection_endpoints_from_subject(subject)
            if endpoints is not None:
                connections.append(endpoints)
        elif concept == "network_topology" and "projects to" in (
            spec.get("condition") or ""
        ):
            source = _population_name(subject)
            targets_str = (spec["condition"] or "").replace("projects to ", "")
            for target in targets_str.split(", "):
                connections.append((source, _population_name(target)))
        elif concept == "projection":
            source = _population_name(subject)
            for target in str(spec.get("condition") or "").split(" AND "):
                if target:
                    connections.append((source, _population_name(target)))

    return connections


def _check_dangling_connections(
    parsed_specs: list[ParsedSentence],
) -> list[dict[str, Any]]:
    """Check that connection endpoints reference defined neurons."""
    failures = []
    # Neurons defined by behavioral specs (threshold, refractory, decay, population, network_topology)
    behavioral_neurons = set()
    for spec in parsed_specs:
        if (
            spec["concept"]
            in (
                "threshold_firing",
                "refractory_period",
                "population_coding",
            )
            or spec["concept"] == "membrane_potential_decay"
        ):
            behavioral_neurons.add(_population_name(spec["subject"]))
        elif spec["concept"] == "network_topology":
            if "population of" in (spec.get("condition") or ""):
                behavioral_neurons.add(_population_name(spec["subject"]))

    connections = _extract_connection_endpoints(parsed_specs)
    for src, tgt in connections:
        matching_specs = [
            spec
            for spec in parsed_specs
            if spec["concept"]
            in (
                "synaptic_weight",
                "axonal_delay",
                "inhibitory_connection",
                "stdp_learning",
                "network_topology",
            )
            and (
                _connection_endpoints_from_subject(spec.get("subject", "")) is not None
                or " to " in spec.get("subject", "")
            )
        ]
        matched_spec = next(
            (
                candidate
                for candidate in matching_specs
                if _connection_endpoints_match(candidate.get("subject", ""), src, tgt)
            ),
            None,
        )
        if src not in behavioral_neurons:
            failures.append(
                _make_failure(
                    "dangling_connection_source",
                    (
                        f"Connection source '{src}' is not defined by any "
                        f"behavioral spec (threshold/refractory/decay/population). "
                        f"Defined neurons: {sorted(behavioral_neurons)}"
                    ),
                    spec=matched_spec,
                    field="subject",
                    value=src,
                )
            )
        if tgt not in behavioral_neurons:
            failures.append(
                _make_failure(
                    "dangling_connection_target",
                    (
                        f"Connection target '{tgt}' is not defined by any "
                        f"behavioral spec. Defined neurons: {sorted(behavioral_neurons)}"
                    ),
                    spec=matched_spec,
                    field="subject",
                    value=tgt,
                )
            )

    return failures


def _check_negative_threshold_without_inhibition(
    parsed_specs: list[ParsedSentence],
) -> list[dict[str, Any]]:
    """Check for negative thresholds on neurons not marked as inhibitory."""
    failures = []
    inhibitory_neurons = set()
    for spec in parsed_specs:
        if spec["concept"] in ("network_topology", "population_coding"):
            raw = str(spec.get("raw", "")).lower()
            cond = str(spec.get("condition", "")).lower()
            if "inhibitory" in raw or cond.startswith("inhibitory population"):
                inhibitory_neurons.add(_population_name(spec["subject"]))

    for spec in parsed_specs:
        if spec["concept"] == "threshold_firing":
            neuron = _population_name(spec["subject"])
            cond = spec.get("condition") or ""
            if cond:
                # Extract numeric value from condition (e.g., "exceeds 1.0" or "is below -0.5")
                m = re.search(r"(-?\d+(?:\.\d+)?)", cond)
                if m:
                    val = float(m.group(1))
                    if val < 0 and neuron not in inhibitory_neurons:
                        failures.append(
                            _make_failure(
                                "negative_threshold_without_inhibition",
                                (
                                    f"Neuron '{neuron}' has negative threshold {val} "
                                    f"but is not marked as inhibitory."
                                ),
                                spec=spec,
                                field="threshold",
                                value=val,
                            )
                        )
    return failures


def _check_zero_weight_synapses(
    parsed_specs: list[ParsedSentence],
) -> list[dict[str, Any]]:
    """Check for zero-weight synapses."""
    failures = []
    for spec in parsed_specs:
        if spec["concept"] in ("synaptic_weight", "inhibitory_connection"):
            cond = spec.get("condition", "")
            if cond:
                m = re.search(r"(-?\d+(?:\.\d+)?)", cond)
                if m:
                    val = float(m.group(1))
                    if val == 0.0:
                        failures.append(
                            _make_failure(
                                "zero_weight_synapse",
                                (
                                    f"Connection '{spec['subject']}' has zero weight. "
                                    f"Zero weights have no effect and should be avoided."
                                ),
                                spec=spec,
                                field="synaptic_weight",
                                value=val,
                            )
                        )
    return failures


def _check_self_referencing_connections(
    parsed_specs: list[ParsedSentence],
) -> list[dict[str, Any]]:
    """Check for neurons connecting to themselves."""
    failures = []
    connections = _extract_connection_endpoints(parsed_specs)
    for src, tgt in connections:
        if src == tgt:
            spec = next(
                (
                    candidate
                    for candidate in parsed_specs
                    if " to " in candidate.get("subject", "")
                    and _connection_endpoints_match(
                        candidate.get("subject", ""), src, tgt
                    )
                ),
                None,
            )
            failures.append(
                _make_failure(
                    "self_referencing_connection",
                    (
                        f"Neuron '{src}' has a self-referencing connection. "
                        f"Self-loops are not supported in this architecture."
                    ),
                    spec=spec,
                    field="subject",
                    value=src,
                )
            )
    return failures


def _check_contradictory_params(
    parsed_specs: list[ParsedSentence],
) -> list[dict[str, Any]]:
    """Check for contradictory parameter specs on the same neuron.

    E.g., two different thresholds for the same neuron.
    """
    failures = []

    # Group specs by (neuron, concept)
    param_specs: dict[tuple[str, str], list[ParsedSentence]] = defaultdict(list)
    for spec in parsed_specs:
        if (
            spec["concept"]
            in (
                "threshold_firing",
                "refractory_period",
            )
            or spec["concept"] == "membrane_potential_decay"
        ):
            key = (_population_name(spec["subject"]), spec["concept"])
            param_specs[key].append(spec)

    for (neuron, concept), specs in param_specs.items():
        if len(specs) > 1:
            conditions = [s.get("condition", "") for s in specs]
            unique_conditions = set(conditions)
            if len(unique_conditions) > 1:
                failures.append(
                    _make_failure(
                        "contradictory_params",
                        (
                            f"Neuron '{neuron}' has contradictory {concept} specs: "
                            f"{list(unique_conditions)}"
                        ),
                        specs=specs,
                        field=concept,
                        value=list(unique_conditions),
                    )
                )

    return failures


def _check_orphan_populations(
    parsed_specs: list[ParsedSentence],
) -> list[dict[str, Any]]:
    """Check that every declared population has at least one connection."""
    failures = []
    declared = set()
    for spec in parsed_specs:
        if spec["concept"] == "population_coding" or (
            spec["concept"] == "network_topology"
            and "population of" in (spec.get("condition") or "")
        ):
            declared.add(_population_name(spec["subject"]))

    connected = set()
    connections = _extract_connection_endpoints(parsed_specs)
    for src, tgt in connections:
        connected.add(src)
        connected.add(tgt)

    # Also check projection targets
    for spec in parsed_specs:
        if spec["concept"] == "network_topology" and "projects to" in (
            spec.get("condition") or ""
        ):
            connected.add(_population_name(spec["subject"]))
            targets_str = (spec["condition"] or "").replace("projects to ", "")
            for t in targets_str.split(", "):
                connected.add(_population_name(t))

    orphans = declared - connected
    for name in sorted(orphans):
        matched_spec = next(
            (
                candidate
                for candidate in parsed_specs
                if candidate["concept"] == "network_topology"
                and _population_name(candidate["subject"]) == name
            ),
            None,
        )
        failures.append(
            _make_failure(
                "orphan_population",
                f"Population '{name}' is declared but has no connections.",
                spec=matched_spec,
                field="subject",
                value=name,
            )
        )
    return failures


def _check_empty_network(neurons: set[str]) -> list[dict[str, Any]]:
    """Check for empty network (no neurons defined)."""
    if not neurons:
        return [
            _make_failure(
                "empty_network", "Network has no defined neurons or populations."
            )
        ]
    return []


def _check_single_node_network(
    neurons: set[str], parsed_specs: list[ParsedSentence]
) -> list[dict[str, Any]]:
    """Check for single-node network."""
    if len(neurons) == 1:
        return [
            _make_failure(
                "single_node_network",
                f"Network has only one neuron/population: {list(neurons)[0]}",
                specs=parsed_specs,
                value=list(neurons)[0],
            )
        ]
    return []


def _check_zero_edge_network(
    neurons: set[str],
    connections: list[tuple[str, str]],
    parsed_specs: list[ParsedSentence],
) -> list[dict[str, Any]]:
    """Check for network with no connections (but potentially neurons)."""
    if neurons and not connections:
        return [
            _make_failure(
                "zero_edge_network",
                "Network has neurons but no connections between them.",
                specs=parsed_specs,
            )
        ]
    return []


def validate_cross_sentence(parsed_specs: list[ParsedSentence]) -> dict[str, Any]:
    """Validate cross-sentence consistency of parsed CNL specs.

    Parameters
    ----------
    parsed_specs : list[ParsedSentence]
        Output of cnl_parser.parse() for multiple sentences.

    Returns
    -------
    dict
        Validation report with keys:
        - checks_passed: list of check names that passed
        - checks_failed: list of dicts with 'check' and 'detail'
        - neurons_found: set of neuron names found
        - connections_found: list of (source, target) tuples
        - overall: True if all checks passed
    """
    neurons = _extract_neuron_names(parsed_specs)
    connections = _extract_connection_endpoints(parsed_specs)

    all_failures = []

    # Check 1: Dangling connections
    dangling = _check_dangling_connections(parsed_specs)
    all_failures.extend(dangling)

    # Check 2: Contradictory parameters
    contradictions = _check_contradictory_params(parsed_specs)
    all_failures.extend(contradictions)

    # Check 3: Orphan populations
    orphans = _check_orphan_populations(parsed_specs)
    all_failures.extend(orphans)

    # Check 4: Negative thresholds without inhibition
    neg_thresholds = _check_negative_threshold_without_inhibition(parsed_specs)
    all_failures.extend(neg_thresholds)

    # Check 5: Zero-weight synapses
    zero_weights = _check_zero_weight_synapses(parsed_specs)
    all_failures.extend(zero_weights)

    # Check 6: Self-referencing connections
    self_refs = _check_self_referencing_connections(parsed_specs)
    all_failures.extend(self_refs)

    # Check 7: Empty network
    empty = _check_empty_network(neurons)
    all_failures.extend(empty)

    # Check 8: Single-node network
    single_node = _check_single_node_network(neurons, parsed_specs)
    all_failures.extend(single_node)

    # Check 9: Zero-edge network
    zero_edges = _check_zero_edge_network(neurons, connections, parsed_specs)
    all_failures.extend(zero_edges)

    checks_passed = []
    if not dangling:
        checks_passed.append("no_dangling_connections")
    if not contradictions:
        checks_passed.append("no_contradictory_params")
    if not orphans:
        checks_passed.append("no_orphan_populations")
    if not neg_thresholds:
        checks_passed.append("no_negative_threshold_without_inhibition")
    if not zero_weights:
        checks_passed.append("no_zero_weight_synapses")
    if not self_refs:
        checks_passed.append("no_self_referencing_connections")
    if not empty:
        checks_passed.append("no_empty_network")
    if not single_node:
        checks_passed.append("no_single_node_network")
    if not zero_edges:
        checks_passed.append("no_zero_edge_network")

    return {
        "checks_passed": checks_passed,
        "checks_failed": all_failures,
        "neurons_found": sorted(neurons),
        "connections_found": connections,
        "overall": len(all_failures) == 0,
    }


# Primitives that represent neurons (not I/O or transformations)
_NIR_NEURON_PRIMITIVES = frozenset({"LIF", "CubaLIF", "LI", "CubaLI", "IF", "I"})


def validate_nir_records(
    records: list[NIRNodeRecord | NIREdgeRecord | NetworkContainer],
) -> dict[str, Any]:
    """
    Cross-record consistency validation for NIR-native records.

    Identifies neurons by record.primitive (e.g. "LIF", "CubaLIF") instead of
    legacy ParsedSentence concept keys. Returns same shape as
    validate_cross_sentence():
        {"checks_passed", "checks_failed", "neurons_found", "connections_found", "overall"}
    """
    checks_passed: list[str] = []
    checks_failed: list[dict[str, Any]] = []

    node_records: list[NIRNodeRecord] = [
        r for r in records if isinstance(r, NIRNodeRecord)
    ]
    edge_records: list[NIREdgeRecord] = [
        r for r in records if isinstance(r, NIREdgeRecord)
    ]

    # All declared node names
    {r.name for r in node_records}
    # Neuron names (excludes Input, Output, Affine, Linear, Conv*, etc.)
    neuron_names: set[str] = {
        r.name for r in node_records if r.primitive in _NIR_NEURON_PRIMITIVES
    }
    # Connection pairs
    connections: list[tuple[str, str]] = [(e.src, e.target) for e in edge_records]
    # All names referenced by edges
    edge_endpoints: set[str] = {ep for pair in connections for ep in pair}

    # ── 1. Empty network ────────────────────────────────────────────────────
    if not node_records:
        checks_failed.append(
            {
                "check": "empty_network",
                "reason": "No nodes declared in this network.",
            }
        )
        return {
            "checks_passed": checks_passed,
            "checks_failed": checks_failed,
            "neurons_found": [],
            "connections_found": connections,
            "overall": False,
        }
    checks_passed.append("empty_network")

    # ── 2. Zero-edge network ─────────────────────────────────────────────────
    if not edge_records:
        checks_failed.append(
            {
                "check": "zero_edge_network",
                "reason": "Nodes declared but no Connect statements found.",
            }
        )
    else:
        checks_passed.append("zero_edge_network")

    # ── 3. Single-node network ───────────────────────────────────────────────
    if len(node_records) == 1:
        checks_failed.append(
            {
                "check": "single_node_network",
                "reason": f"Network contains only one node: '{node_records[0].name}'.",
            }
        )
    else:
        checks_passed.append("single_node_network")

    # ── 4. Self-referencing connections ──────────────────────────────────────
    self_refs = [(s, t) for s, t in connections if s == t]
    if self_refs:
        for src, tgt in self_refs:
            checks_failed.append(
                {
                    "check": "self_referencing_connection",
                    "src": src,
                    "target": tgt,
                    "reason": f"Node '{src}' connects to itself.",
                }
            )
    else:
        checks_passed.append("self_referencing_connection")

    # ── 5. Orphan neurons (declared but not referenced by any edge) ──────────
    orphaned = neuron_names - edge_endpoints
    if orphaned:
        for name in sorted(orphaned):
            checks_failed.append(
                {
                    "check": "orphan_population",
                    "node": name,
                    "reason": f"Neuron '{name}' is declared but not connected to anything.",
                }
            )
    else:
        checks_passed.append("orphan_population")

    overall = len(checks_failed) == 0
    return {
        "checks_passed": checks_passed,
        "checks_failed": checks_failed,
        "neurons_found": sorted(neuron_names),
        "connections_found": connections,
        "overall": overall,
    }
