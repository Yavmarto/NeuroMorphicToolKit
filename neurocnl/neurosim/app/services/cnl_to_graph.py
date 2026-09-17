"""Import canonical NeuroCNL graphs as a CanvasGraph.

The legacy biological-grammar repair path (``cnl_to_graph``,
``parse_semantic_statements``, and the ``MUST``/``sensory``/``motor``
regex patterns) has been removed. All CNL → canvas conversion now goes
through the NIR-native pipeline:

    NIR-native CNL → NIR_CNL_Parser → NIR_Compiler → serialize_nir_to_canvas_graph

Use the ``/api/neurosim/parse-cnl`` endpoint for live sync, or call
``import_graph_from_contract`` when NeuroCNL provides a typed import
contract directly.
"""

from __future__ import annotations

from dataclasses import dataclass

from neurosim.contracts.design_contracts import NeuroCnlImportContract

from ..schemas.canvas import CanvasGraph

# ---------------------------------------------------------------------------
# Layout helpers
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class _LayoutConfig:
    position_hints: dict[str, tuple[float, float]] | None
    x_offset: float
    x_step: float
    y_pos: float


def _resolve_position(
    node_id: str,
    name: str,
    node_count: int,
    layout: _LayoutConfig,
) -> tuple[float, float]:
    """Resolve the node position from hints or the default left-to-right layout."""
    position_hints = layout.position_hints
    pos = position_hints.get(node_id) if position_hints else None
    if not pos and position_hints:
        pos = position_hints.get(name)
    if pos:
        return pos
    return (layout.x_offset + node_count * layout.x_step, layout.y_pos)


def _apply_position_hints(
    graph: CanvasGraph,
    position_hints: dict[str, tuple[float, float]] | None,
) -> CanvasGraph:
    """Preserve caller-provided layout while keeping imported node ids stable."""
    if not position_hints:
        return graph

    layout = _LayoutConfig(
        position_hints=position_hints,
        x_offset=100.0,
        x_step=300.0,
        y_pos=200.0,
    )
    nodes = [
        node.model_copy(
            update={
                "position": _resolve_position(
                    node.id,
                    str(node.parameters.get("name", node.id)),
                    index,
                    layout,
                ),
            },
        )
        for index, node in enumerate(graph.nodes)
    ]
    return graph.model_copy(update={"nodes": nodes})


def _coerce_to_import_contract(value: object) -> NeuroCnlImportContract:
    """Coerce value to NeuroCnlImportContract, handling the case where the caller passes a dict.

    The public function ``import_graph_from_contract`` declares its argument as
    ``NeuroCnlImportContract``, but ``neurocnl.handoff.build_neurosim_handoff_spec`` is not
    yet fully typed and can return a plain ``dict`` at runtime.  Taking ``object`` here keeps
    every ``isinstance`` branch reachable per mypy and avoids suppression comments.

    Args:
        value (object): A ``NeuroCnlImportContract`` instance or a plain ``dict`` payload.

    Returns:
        NeuroCnlImportContract: The validated contract model.
    """
    if isinstance(value, dict):
        return NeuroCnlImportContract.model_validate(value)
    if isinstance(value, NeuroCnlImportContract):
        return value
    raise TypeError(f"Expected NeuroCnlImportContract or dict, got {type(value)!r}")


def import_graph_from_contract(
    import_contract: NeuroCnlImportContract,
    position_hints: dict[str, tuple[float, float]] | None = None,
) -> CanvasGraph:
    """Import a graph from a typed NeuroCNL-owned semantics contract.

    Args:
        import_contract (NeuroCnlImportContract): The typed contract payload.
        position_hints (dict | None): Optional canvas position overrides keyed by node name.

    Returns:
        CanvasGraph: The canvas graph derived from the contract.
    """
    contract = _coerce_to_import_contract(import_contract)
    return _apply_position_hints(contract.graph, position_hints)
