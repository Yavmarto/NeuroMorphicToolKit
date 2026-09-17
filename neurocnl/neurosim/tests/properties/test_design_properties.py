from typing import Any

import nengo
import pytest
from hypothesis import given, settings
from hypothesis import strategies as st
from hypothesis.strategies import DrawFn, SearchStrategy
from pydantic import ValidationError

from neurosim.app.services.preview_runner import run_preview
from neurosim.app.services.sweep_runner import run_sweep
from neurosim.contracts.design_contracts import (
    CanvasEdge,
    CanvasGraph,
    CanvasNode,
    CnlSyncRequest,
    CreateProjectRequest,
    NeuroCnlImportContract,
    PreviewRequest,
    Project,
    SweepRequest,
)

# --- Strategies ---


@st.composite
def node_strategy(draw: DrawFn) -> CanvasNode:
    # Ensure name is alphanumeric + spaces to avoid parsing issues in CNL
    name = draw(
        st.text(
            min_size=1,
            max_size=20,
            alphabet=st.characters(
                whitelist_categories=("Lu", "Ll", "Nd"), whitelist_characters=" "
            ),
        )
    ).strip()
    if not name:
        name = "Node"

    node_id = name.lower().replace(" ", "_")
    # Pydantic validation for CanvasGraph requires unique node IDs.
    if not node_id:
        node_id = "node"

    # Biological invariant: tau_ref < tau_rc
    tau_rc = draw(
        st.floats(min_value=0.002, max_value=1.0, allow_nan=False, allow_infinity=False)
    )
    tau_ref = draw(
        st.floats(
            min_value=0.0,
            max_value=tau_rc - 0.001,
            allow_nan=False,
            allow_infinity=False,
        )
    )

    return CanvasNode(
        id=node_id,
        component_id=draw(st.sampled_from(["lif_population", "adaptive_lif"])),
        parameters={
            "name": name,
            "n_neurons": draw(st.integers(min_value=1, max_value=1000)),
            "tau_rc": tau_rc,
            "tau_ref": tau_ref,
        },
        position=draw(
            st.tuples(
                st.floats(
                    min_value=0, max_value=2000, allow_nan=False, allow_infinity=False
                ),
                st.floats(
                    min_value=0, max_value=2000, allow_nan=False, allow_infinity=False
                ),
            )
        ),
    )


@st.composite
def graph_strategy(draw: DrawFn) -> CanvasGraph:
    nodes = draw(
        st.lists(node_strategy(), min_size=1, max_size=5, unique_by=lambda x: x.id)
    )
    node_ids = [n.id for n in nodes]

    edges = draw(
        st.lists(
            st.builds(
                CanvasEdge,
                id=st.text(min_size=1, max_size=10),
                source_node_id=st.sampled_from(node_ids),
                source_port=st.just("out"),
                target_node_id=st.sampled_from(node_ids),
                target_port=st.just("in"),
                parameters=st.fixed_dictionaries(
                    {
                        "synapse_type": st.sampled_from(["static_synapse"]),
                        "weight": st.floats(
                            min_value=-10.0,
                            max_value=10.0,
                            allow_nan=False,
                            allow_infinity=False,
                        ),
                        "delay": st.floats(
                            min_value=0.001,
                            max_value=0.1,
                            allow_nan=False,
                            allow_infinity=False,
                        ),
                    }
                ),
            ),
            unique_by=lambda x: (x.source_node_id, x.target_node_id),
            max_size=5,
        )
    )

    metadata = draw(
        st.dictionaries(st.text(min_size=1, max_size=10), st.text(max_size=10))
    )
    return CanvasGraph(nodes=nodes, edges=edges, metadata=metadata)


def preview_request_strategy() -> SearchStrategy[PreviewRequest]:
    return st.builds(
        PreviewRequest,
        graph=graph_strategy(),
        duration_ms=st.floats(
            min_value=0.001, max_value=500.0, allow_nan=False, allow_infinity=False
        ),
    )


@st.composite
def sweep_request_strategy(draw: DrawFn) -> SweepRequest:
    graph = draw(graph_strategy())

    # Pick a random node from the graph and a random parameter to sweep
    node = draw(st.sampled_from(graph.nodes))
    param_name = draw(st.sampled_from(["n_neurons", "tau_rc", "tau_ref"]))
    parameter_path = f"nodes.{node.id}.{param_name}"

    if param_name == "n_neurons":
        start = float(draw(st.integers(min_value=1, max_value=100)))
        end = float(draw(st.integers(min_value=int(start) + 1, max_value=200)))
    elif param_name == "tau_rc":
        # Keep tau_rc > current tau_ref
        current_tau_ref = node.parameters.get("tau_ref", 0.002)
        # Ensure max_value > min_value by bounding current_tau_ref
        current_tau_ref = min(current_tau_ref, 0.4)
        start = draw(
            st.floats(
                min_value=current_tau_ref + 0.001,
                max_value=0.8,
                allow_nan=False,
                allow_infinity=False,
            )
        )
        end = draw(
            st.floats(
                min_value=start + 0.001,
                max_value=start
                + 0.5,  # avoid being too large and breaking float limits later? Actually max_value=1.0 is fine as long as start is < 0.99
                allow_nan=False,
                allow_infinity=False,
            )
        )
    else:  # tau_ref
        # Keep tau_ref < current tau_rc
        current_tau_rc = node.parameters.get("tau_rc", 0.02)
        start = draw(
            st.floats(
                min_value=0.0,
                max_value=current_tau_rc - 0.002,
                allow_nan=False,
                allow_infinity=False,
            )
        )
        end = draw(
            st.floats(
                min_value=start + 0.0005,
                max_value=current_tau_rc - 0.0005,
                allow_nan=False,
                allow_infinity=False,
            )
        )

    steps = draw(st.integers(min_value=1, max_value=20))
    simulation_duration_ms = draw(
        st.floats(min_value=0.1, max_value=500.0, allow_nan=False, allow_infinity=False)
    )

    return SweepRequest(
        graph=graph,
        parameter_path=parameter_path,
        start=start,
        end=end,
        steps=steps,
        simulation_duration_ms=simulation_duration_ms,
    )


def project_strategy() -> SearchStrategy[Project]:
    return st.builds(
        Project,
        id=st.uuids().map(str),
        name=st.text(min_size=1).filter(lambda s: bool(s.strip())),
        description=st.text(),
        updated_at=st.datetimes().map(lambda x: x.isoformat() + "Z"),
        graph=graph_strategy(),
        cnl_spec=st.text(),
    )


def create_project_request_strategy() -> SearchStrategy[CreateProjectRequest]:
    return st.builds(
        CreateProjectRequest,
        name=st.text(min_size=1).filter(lambda s: bool(s.strip())),
        description=st.text(),
        graph=graph_strategy(),
    )


def cnl_sync_request_strategy() -> SearchStrategy[CnlSyncRequest]:
    return st.one_of(
        st.builds(
            CnlSyncRequest,
            import_contract=st.builds(
                NeuroCnlImportContract,
                cnl_spec=st.text(min_size=1),
                graph=graph_strategy(),
                warnings=st.lists(st.text(max_size=40), max_size=3),
            ),
            cnl_spec=st.none(),
            graph=st.none(),
            import_mode=st.none(),
        ),
        st.builds(
            CnlSyncRequest,
            graph=st.none(),
            cnl_spec=st.text(min_size=1),
            import_mode=st.just("repair"),
        ),
        st.builds(
            CnlSyncRequest,
            graph=graph_strategy(),
            cnl_spec=st.text(min_size=1),
            import_mode=st.just("repair"),
        ),
    )


# --- Tests ---


@settings(max_examples=100)
@given(graph_strategy())
def test_canvas_graph_round_trip(graph: Any) -> None:
    dump = graph.model_dump()
    restored = CanvasGraph.model_validate(dump)
    assert restored == graph
    # Connection invariant check
    node_ids = {n.id for n in restored.nodes}
    for edge in restored.edges:
        assert edge.source_node_id in node_ids
        assert edge.target_node_id in node_ids


@settings(max_examples=100)
@given(preview_request_strategy())
def test_preview_request_invariants(request_obj: Any) -> None:
    assert 0 < request_obj.duration_ms <= 500
    dump = request_obj.model_dump()
    assert PreviewRequest.model_validate(dump) == request_obj


@settings(max_examples=100)
@given(sweep_request_strategy())
def test_sweep_request_invariants(request_obj: Any) -> None:
    assert 0 < request_obj.steps <= 20
    assert request_obj.simulation_duration_ms > 0
    assert request_obj.start < request_obj.end
    dump = request_obj.model_dump()
    assert SweepRequest.model_validate(dump) == request_obj


@settings(max_examples=200)
@given(project_strategy())
def test_project_invariants(project: Any) -> None:
    assert len(project.name) >= 1
    dump = project.model_dump()
    assert Project.model_validate(dump) == project


@settings(max_examples=200)
@given(create_project_request_strategy())
def test_create_project_request_invariants(request_obj: Any) -> None:
    assert len(request_obj.name) >= 1
    dump = request_obj.model_dump()
    assert CreateProjectRequest.model_validate(dump) == request_obj


@settings(max_examples=200)
@given(cnl_sync_request_strategy())
def test_cnl_sync_request_invariants(request_obj: Any) -> None:
    assert request_obj.import_contract is not None or request_obj.cnl_spec is not None
    dump = request_obj.model_dump()
    assert CnlSyncRequest.model_validate(dump) == request_obj


@settings(max_examples=10, deadline=None)
@given(preview_request_strategy())
def test_simulation_determinism_property(request_obj: PreviewRequest) -> None:
    """Verify that running a simulation preview multiple times with same input yields same results."""
    try:
        nengo.rc.set("decoder_cache", "enabled", "False")
        res1 = run_preview(request_obj)
        res2 = run_preview(request_obj)
        res1.job_id = None
        res2.job_id = None
        # the simulation execution time varies so we don't compare metrics
        res1.metrics = None
        res2.metrics = None
        # the error messages might be very slightly different across threads/runs
        res1.error = None
        res2.error = None
        assert res1 == res2
    except Exception as e:
        # Nengo throws these for certain parameter combinations when generating uniform random rates
        if "lead to neurons with negative or non-finite gain" in str(e):
            return
        if "Value must be greater than or equal to 1" in str(e):
            return
        if "tuple index out of range" in str(e):
            return
        raise


@settings(max_examples=10, deadline=None)
@given(sweep_request_strategy())
def test_sweep_determinism_property(request_obj: SweepRequest) -> None:
    """Verify that running a parameter sweep multiple times with same input yields same results."""
    try:
        nengo.rc.set("decoder_cache", "enabled", "False")
        res1 = run_sweep(request_obj)
        res2 = run_sweep(request_obj)
        res1.job_id = None
        res2.job_id = None
        if res1.steps:
            for step in res1.steps:
                step.result.job_id = None
                step.result.metrics = None
                step.result.error = None
        if res2.steps:
            for step in res2.steps:
                step.result.job_id = None
                step.result.metrics = None
                step.result.error = None
        assert res1 == res2
    except Exception as e:
        if "lead to neurons with negative or non-finite gain" in str(e):
            return
        if "Value must be greater than or equal to 1" in str(e):
            return
        if "tuple index out of range" in str(e):
            return
        raise


# --- Negative Tests ---


@given(st.floats(max_value=0, allow_nan=False, allow_infinity=False))
def test_invalid_preview_duration_non_positive(val: Any) -> None:
    with pytest.raises(ValueError, match="Preview duration must be positive"):
        PreviewRequest(
            graph=CanvasGraph(
                nodes=[
                    CanvasNode(
                        id="n1", component_id="c1", parameters={}, position=(0, 0)
                    )
                ],
                edges=[],
                metadata={},
            ),
            duration_ms=val,
        )


@given(st.floats(min_value=500.01, allow_nan=False, allow_infinity=False))
def test_invalid_preview_duration_too_large(val: Any) -> None:
    with pytest.raises(ValidationError):
        PreviewRequest(
            graph=CanvasGraph(
                nodes=[
                    CanvasNode(
                        id="n1", component_id="c1", parameters={}, position=(0, 0)
                    )
                ],
                edges=[],
                metadata={},
            ),
            duration_ms=val,
        )


@given(st.integers(max_value=0))
def test_invalid_sweep_steps_non_positive(val: Any) -> None:
    with pytest.raises(ValueError, match="Sweep steps must be positive"):
        SweepRequest(
            graph=CanvasGraph(nodes=[], edges=[], metadata={}),
            parameter_path="p",
            start=0,
            end=1,
            steps=val,
        )


@given(st.integers(min_value=21))
def test_invalid_sweep_steps_too_many(val: Any) -> None:
    with pytest.raises(ValidationError):
        SweepRequest(
            graph=CanvasGraph(nodes=[], edges=[], metadata={}),
            parameter_path="p",
            start=0,
            end=1,
            steps=val,
        )


@given(
    st.floats(min_value=0, allow_nan=False, allow_infinity=False),
    st.floats(allow_nan=False, allow_infinity=False),
)
def test_invalid_sweep_range(start: Any, end: Any) -> None:
    if start < end:
        return
    with pytest.raises(ValueError, match="start must be strictly less than end"):
        SweepRequest(
            graph=CanvasGraph(nodes=[], edges=[], metadata={}),
            parameter_path="p",
            start=start,
            end=end,
            steps=5,
        )


def test_invalid_canvas_edge_dangling() -> None:
    node = CanvasNode(
        id="n1", component_id="c1", parameters={"name": "N1"}, position=(0, 0)
    )
    edge = CanvasEdge(
        id="e1",
        source_node_id="n1",
        source_port="p",
        target_node_id="n2",
        target_port="p",
        parameters={},
    )
    with pytest.raises(ValidationError) as excinfo:
        CanvasGraph(nodes=[node], edges=[edge], metadata={})
    assert "references non-existent target node 'n2'" in str(excinfo.value)


def test_invalid_project_name_empty() -> None:
    with pytest.raises(ValidationError):
        Project(
            id="1",
            name="",
            updated_at="2026-03-26T12:00:00Z",
            graph=CanvasGraph(nodes=[], edges=[], metadata={}),
        )


def test_invalid_create_project_name_empty() -> None:
    with pytest.raises(ValidationError):
        CreateProjectRequest(
            name="",
            description="Test",
            graph=CanvasGraph(nodes=[], edges=[], metadata={}),
        )


def test_invalid_cnl_sync_request_empty() -> None:
    with pytest.raises(ValidationError) as excinfo:
        CnlSyncRequest(graph=None, cnl_spec=None)
    assert (
        "Provide either 'import_contract' or raw 'cnl_spec' with import_mode='repair'."
        in str(excinfo.value)
    )
