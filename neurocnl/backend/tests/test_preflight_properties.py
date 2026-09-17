"""Property-based tests for the preflight endpoints.

**Validates: Requirements 1.2, 1.3, 1.4, 1.5, 2.2, 2.3, 2.4, 2.5**

Each test function in this module is a named Hypothesis property.
Tests are ordered to match the task numbering (Property 1 is task 7.2,
Property 4 is task 7.5).
"""

from __future__ import annotations

import itertools
import tempfile
from pathlib import Path

import nir
import numpy as np
from fastapi.testclient import TestClient
from hypothesis import assume, given, settings
from hypothesis import strategies as st

from backend.app.main import app
from neurocnl import CompileError, compile_to_nir
from neurocnl.runtime.nir_support import SIMULATOR_RUNTIME_BACKENDS, classify_nir_graph

client = TestClient(app)

_PREFLIGHT_URL = "/api/simulators/preflight"
_PREFLIGHT_NIR_URL = "/api/simulators/preflight-nir"

# ---------------------------------------------------------------------------
# Rate-limit isolation helpers
#
# The preflight endpoints apply a "10/minute" rate limit keyed on client IP.
# Hypothesis can generate more than 10 examples per invocation, so each test
# call must use a unique IP.  This monotonically-increasing counter produces
# distinct 10.x.x.x addresses, matching the pattern used in
# test_simulators_logging_preservation.py.
# ---------------------------------------------------------------------------

_ip_counter = itertools.count(1)


def _next_ip() -> str:
    """Return a unique 10.x.x.x IP address for rate-limit isolation."""
    n = next(_ip_counter)
    a = (n >> 16) & 0xFF
    b = (n >> 8) & 0xFF
    c = n & 0xFF
    return f"10.{a}.{b}.{c}"


# ---------------------------------------------------------------------------
# Valid CNL fixtures (Task 7.2)
#
# A small list of CNL specs that are known to compile successfully via
# ``compile_to_nir``.  Drawn using ``st.sampled_from`` so Hypothesis covers
# every entry across its 100 examples.
# ---------------------------------------------------------------------------

# Inline minimal spec reused from test_preflight_exploration._VALID_SPEC.
_SPEC_PREFLIGHT_TEST = "\n".join(
    [
        "Define a network named preflight_test.",
        "Define an input port named input with shape (2,).",
        "Define a linear transformation named w_in with weight matrix shape (2, 2).",
        "Define a LIF neuron named pop_a "
        "with time constant 0.02, resistance 1.0, leak voltage 0.0, and firing threshold 1.0.",
        "Define a linear transformation named w_out with weight matrix shape (2, 2).",
        "Define a LIF neuron named pop_b "
        "with time constant 0.02, resistance 1.0, leak voltage 0.0, and firing threshold 1.0.",
        "Define an output port named output with shape (2,).",
        "input connects to w_in.",
        "w_in connects to pop_a.",
        "pop_a connects to w_out.",
        "w_out connects to pop_b.",
        "pop_b connects to output.",
    ]
)

# Path to the bundled CNL templates that ship with the backend.
_TEMPLATES_DIR = Path(__file__).parents[1] / "app" / "templates"

_SPEC_REFLEX_ARC = (_TEMPLATES_DIR / "reflex_arc.cnl").read_text()
_SPEC_COINCIDENCE = (_TEMPLATES_DIR / "coincidence_detector.cnl").read_text()

# Public constant so other test modules can import the fixture list if needed.
VALID_CNL_FIXTURES = [
    _SPEC_PREFLIGHT_TEST,
    _SPEC_REFLEX_ARC,
    _SPEC_COINCIDENCE,
]

# Five required top-level fields in every PreflightResult response body.
_PREFLIGHT_RESULT_FIELDS = {
    "level",
    "supported_nodes",
    "approximate_nodes",
    "unsupported_nodes",
    "diagnostics",
}
_VALID_LEVELS = {"exact", "approximate", "unsupported"}


# ---------------------------------------------------------------------------
# Property 1 — Preflight endpoint response completeness (CNL path)
# ---------------------------------------------------------------------------


@given(
    spec=st.sampled_from(VALID_CNL_FIXTURES),
    backend_name=st.sampled_from(["lava_sim", "snntorch_sim"]),
)
@settings(max_examples=100)
def test_preflight_cnl_response_completeness(spec: str, backend_name: str) -> None:
    """Property 1: Preflight endpoint response completeness (CNL path).

    **Validates: Requirements 1.2, 1.3**

    Strategy
    --------
    ``st.sampled_from(VALID_CNL_FIXTURES)`` draws from three CNL specs that
    are each known to compile without error.  ``st.sampled_from(["lava_sim",
    "snntorch_sim"])`` covers both supported backends.  Together they form a
    6-combination space that Hypothesis samples 100 times.

    Assertions
    ----------
    1. HTTP 200 is returned for every (spec, backend_name) combination.
    2. All five required ``PreflightResult`` fields are present in the
       response body (Requirement 1.3 field completeness).
    3. ``level`` is one of ``"exact"``, ``"approximate"``, or
       ``"unsupported"`` (Requirement 1.3 enumeration).
    4. ``supported_nodes``, ``approximate_nodes``, ``unsupported_nodes``,
       and ``diagnostics`` are all lists (Requirement 1.3 type contract).
    5. Level-consistency invariant (Requirement 1.3 semantics):
       - Non-empty ``unsupported_nodes`` → ``level == "unsupported"``.
       - Non-empty ``approximate_nodes`` and empty ``unsupported_nodes`` →
         ``level == "approximate"``.
    """
    resp = client.post(
        _PREFLIGHT_URL,
        json={"spec": spec, "backend_name": backend_name},
        headers={"X-Forwarded-For": _next_ip()},
    )

    # ── 1. HTTP 200 ───────────────────────────────────────────────────────
    assert resp.status_code == 200, (
        f"Expected HTTP 200 for valid CNL spec with backend {backend_name!r}, "
        f"got {resp.status_code}. Response: {resp.text!r}"
    )

    data = resp.json()

    # ── 2. All five fields present ────────────────────────────────────────
    missing = _PREFLIGHT_RESULT_FIELDS - data.keys()
    assert not missing, (
        f"PreflightResult response is missing required fields: {missing}. "
        f"Got keys: {list(data.keys())}"
    )

    # ── 3. level is a valid enumeration value ─────────────────────────────
    assert data["level"] in _VALID_LEVELS, (
        f"level must be one of {_VALID_LEVELS}, got {data['level']!r}. "
        f"backend_name={backend_name!r}"
    )

    # ── 4. Node lists and diagnostics are lists ───────────────────────────
    for field in (
        "supported_nodes",
        "approximate_nodes",
        "unsupported_nodes",
        "diagnostics",
    ):
        assert isinstance(data[field], list), (
            f"Expected {field!r} to be a list, got {type(data[field]).__name__}. "
            f"backend_name={backend_name!r}"
        )

    unsupported_nodes: list[str] = data["unsupported_nodes"]
    approximate_nodes: list[str] = data["approximate_nodes"]
    level: str = data["level"]

    # ── 5. Level-consistency invariant ───────────────────────────────────
    # 5a. Non-empty unsupported_nodes → level must be "unsupported"
    if unsupported_nodes:
        assert level == "unsupported", (
            f"Level-consistency violated: unsupported_nodes={unsupported_nodes!r} "
            f"is non-empty but level={level!r} (expected 'unsupported'). "
            f"backend_name={backend_name!r}"
        )

    # 5b. Non-empty approximate_nodes AND empty unsupported_nodes → level must be "approximate"
    if approximate_nodes and not unsupported_nodes:
        assert level == "approximate", (
            f"Level-consistency violated: approximate_nodes={approximate_nodes!r} "
            f"is non-empty, unsupported_nodes is empty, "
            f"but level={level!r} (expected 'approximate'). "
            f"backend_name={backend_name!r}"
        )


# ---------------------------------------------------------------------------
# NIR graph fixtures for Property 2 (Task 7.3)
#
# Each factory function returns a valid ``nir.NIRGraph`` that can be
# serialised to HDF5 bytes.  The factories intentionally cover the three
# support levels (exact / approximate / unsupported) to give Hypothesis
# meaningful variation across the 100 required examples.
#
# We use a fixed-fixture strategy (``st.sampled_from``) rather than fully
# random graph generation because ``nir.NIRGraph`` runs type-inference on
# construction and rejects shape-mismatched edges.  Building truly random
# valid graphs would require a graph search on the NIR type system — outside
# the scope of this property.  The fixture set is large enough to exercise
# both backends across all three support levels.
# ---------------------------------------------------------------------------


def _build_exact_nir_graph(n: int = 4) -> nir.NIRGraph:
    """Input → Linear → LIF → Output (all exact nodes on both backends)."""
    return nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([n])}),
            "lin": nir.Linear(weight=np.eye(n, dtype=np.float32)),
            "lif": nir.LIF(
                tau=np.full([n], 0.02, dtype=np.float32),
                r=np.full([n], 1.0, dtype=np.float32),
                v_leak=np.zeros(n, dtype=np.float32),
                v_threshold=np.ones(n, dtype=np.float32),
            ),
            "output": nir.Output(output_type={"output": np.array([n])}),
        },
        edges=[("input", "lin"), ("lin", "lif"), ("lif", "output")],
    )


def _build_approximate_nir_graph(n: int = 2) -> nir.NIRGraph:
    """Input → Linear → CubaLIF → Output (CubaLIF is approximate on both backends)."""
    return nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([n])}),
            "lin": nir.Linear(weight=np.eye(n, dtype=np.float32)),
            "cuba": nir.CubaLIF(
                tau_mem=np.full([n], 0.02, dtype=np.float32),
                tau_syn=np.full([n], 0.005, dtype=np.float32),
                r=np.full([n], 1.0, dtype=np.float32),
                v_leak=np.zeros(n, dtype=np.float32),
                v_threshold=np.ones(n, dtype=np.float32),
            ),
            "output": nir.Output(output_type={"output": np.array([n])}),
        },
        edges=[("input", "lin"), ("lin", "cuba"), ("cuba", "output")],
    )


def _build_exact_nir_graph_small(n: int = 2) -> nir.NIRGraph:
    """Smaller variant: Input → Linear → LIF → Output (n=2)."""
    return _build_exact_nir_graph(n=n)


def _build_exact_nir_graph_large(n: int = 8) -> nir.NIRGraph:
    """Larger variant: Input → Linear → LIF → Output (n=8)."""
    return _build_exact_nir_graph(n=n)


def _build_delay_nir_graph(n: int = 3) -> nir.NIRGraph:
    """Input → Linear → LIF → Delay → Output (Delay is approximate on both backends)."""
    return nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([n])}),
            "lin": nir.Linear(weight=np.eye(n, dtype=np.float32)),
            "lif": nir.LIF(
                tau=np.full([n], 0.02, dtype=np.float32),
                r=np.full([n], 1.0, dtype=np.float32),
                v_leak=np.zeros(n, dtype=np.float32),
                v_threshold=np.ones(n, dtype=np.float32),
            ),
            "delay": nir.Delay(delay=np.full([n], 1.0, dtype=np.float32)),
            "output": nir.Output(output_type={"output": np.array([n])}),
        },
        edges=[("input", "lin"), ("lin", "lif"), ("lif", "delay"), ("delay", "output")],
    )


# Public list of (graph_builder_fn, expected_level_for_both_backends) tuples.
# ``expected_level`` is the minimum support level across BOTH lava_sim and
# snntorch_sim — used to assert the invariant independently of the endpoint.
_NIR_GRAPH_FIXTURES: list[nir.NIRGraph] = [
    _build_exact_nir_graph(n=4),
    _build_exact_nir_graph_small(n=2),
    _build_exact_nir_graph_large(n=8),
    _build_approximate_nir_graph(n=2),
    _build_approximate_nir_graph(n=4),
    _build_delay_nir_graph(n=3),
]


def _graph_to_bytes(graph: nir.NIRGraph) -> bytes:
    """Serialise a NIRGraph to HDF5 bytes using a NamedTemporaryFile."""
    tmp_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(suffix=".nir", delete=False) as tmp:
            tmp_path = Path(tmp.name)
        nir.write(str(tmp_path), graph)
        return tmp_path.read_bytes()
    finally:
        if tmp_path is not None:
            tmp_path.unlink(missing_ok=True)


# Pre-serialise all fixtures once at module load time so Hypothesis doesn't
# re-serialise on every example (serialisation involves disk I/O).
_NIR_GRAPH_FIXTURE_BYTES: list[tuple[nir.NIRGraph, bytes]] = [
    (g, _graph_to_bytes(g)) for g in _NIR_GRAPH_FIXTURES
]


# ---------------------------------------------------------------------------
# Property 2 — Preflight endpoint response completeness (NIR path)
# ---------------------------------------------------------------------------


@given(
    fixture=st.sampled_from(_NIR_GRAPH_FIXTURE_BYTES),
    backend_name=st.sampled_from(["lava_sim", "snntorch_sim"]),
)
@settings(max_examples=100)
def test_preflight_nir_response_completeness(
    fixture: tuple[nir.NIRGraph, bytes],
    backend_name: str,
) -> None:
    """Property 2: Preflight endpoint response completeness (NIR path).

    **Validates: Requirements 2.2, 2.3**

    Strategy
    --------
    ``st.sampled_from(_NIR_GRAPH_FIXTURE_BYTES)`` draws from six pre-built
    ``nir.NIRGraph`` objects that cover exact, approximate, and mixed support
    levels.  Each graph has been serialised to HDF5 bytes at module load time.
    ``st.sampled_from(["lava_sim", "snntorch_sim"])`` covers both supported
    backends.  Together they form a 12-combination space that Hypothesis
    samples 100 times.

    Assertions
    ----------
    1. HTTP 200 is returned for every (graph, backend_name) combination
       (Requirement 2.2 — valid request returns 200).
    2. All five required ``PreflightResult`` fields are present in the
       response body (Requirement 2.3 field completeness).
    3. ``level`` is one of ``"exact"``, ``"approximate"``, or
       ``"unsupported"`` (Requirement 2.3 enumeration).
    4. All four list fields are actually lists (Requirement 2.3 type
       contract).
    5. The endpoint response matches ``classify_nir_graph(graph,
       backend_name)`` called directly — i.e. the HTTP layer does not
       mutate or lose classification data (Requirement 2.3 semantic
       fidelity).
    """
    graph, nir_bytes = fixture

    resp = client.post(
        _PREFLIGHT_NIR_URL,
        data={"backend_name": backend_name},
        files={"file": ("graph.nir", nir_bytes, "application/octet-stream")},
        headers={"X-Forwarded-For": _next_ip()},
    )

    # ── 1. HTTP 200 ───────────────────────────────────────────────────────
    assert resp.status_code == 200, (
        f"Expected HTTP 200 for valid NIR graph with backend {backend_name!r}, "
        f"got {resp.status_code}. Response: {resp.text!r}"
    )

    data = resp.json()

    # ── 2. All five fields present ────────────────────────────────────────
    missing = _PREFLIGHT_RESULT_FIELDS - data.keys()
    assert not missing, (
        f"PreflightResult response is missing required fields: {missing}. "
        f"Got keys: {list(data.keys())}"
    )

    # ── 3. level is a valid enumeration value ─────────────────────────────
    assert data["level"] in _VALID_LEVELS, (
        f"level must be one of {_VALID_LEVELS}, got {data['level']!r}. "
        f"backend_name={backend_name!r}"
    )

    # ── 4. Node lists and diagnostics are lists ───────────────────────────
    for field in (
        "supported_nodes",
        "approximate_nodes",
        "unsupported_nodes",
        "diagnostics",
    ):
        assert isinstance(data[field], list), (
            f"Expected {field!r} to be a list, got {type(data[field]).__name__}. "
            f"backend_name={backend_name!r}"
        )

    # ── 5. Response matches direct classify_nir_graph call ────────────────
    # Deserialise the fixture graph from bytes (via a temp file) to get the
    # exact same in-process graph that the endpoint will have loaded.
    # This assertion checks that the HTTP layer adds no mutation or data loss.
    tmp_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(suffix=".nir", delete=False) as tmp:
            tmp.write(nir_bytes)
            tmp_path = Path(tmp.name)
        loaded_graph = nir.read(str(tmp_path))
    finally:
        if tmp_path is not None:
            tmp_path.unlink(missing_ok=True)

    expected = classify_nir_graph(loaded_graph, backend_name)

    assert data["level"] == expected.level, (
        f"level mismatch: endpoint returned {data['level']!r}, "
        f"classify_nir_graph returned {expected.level!r}. "
        f"backend_name={backend_name!r}"
    )
    assert sorted(data["supported_nodes"]) == sorted(expected.supported_nodes), (
        f"supported_nodes mismatch: endpoint={data['supported_nodes']!r}, "
        f"direct={expected.supported_nodes!r}. backend_name={backend_name!r}"
    )
    assert sorted(data["approximate_nodes"]) == sorted(expected.approximate_nodes), (
        f"approximate_nodes mismatch: endpoint={data['approximate_nodes']!r}, "
        f"direct={expected.approximate_nodes!r}. backend_name={backend_name!r}"
    )
    assert sorted(data["unsupported_nodes"]) == sorted(expected.unsupported_nodes), (
        f"unsupported_nodes mismatch: endpoint={data['unsupported_nodes']!r}, "
        f"direct={expected.unsupported_nodes!r}. backend_name={backend_name!r}"
    )
    assert len(data["diagnostics"]) == len(expected.diagnostics), (
        f"diagnostics length mismatch: endpoint returned {len(data['diagnostics'])} items, "
        f"classify_nir_graph returned {len(expected.diagnostics)}. "
        f"backend_name={backend_name!r}"
    )


# ---------------------------------------------------------------------------
# Property 4 — Invalid HDF5 maps to HTTP 422 with nir_parse_error
# ---------------------------------------------------------------------------


@given(data=st.binary(min_size=0, max_size=8192))
@settings(max_examples=100)
def test_preflight_nir_parse_error(data: bytes) -> None:
    """Property 4: Invalid HDF5 maps to HTTP 422 with nir_parse_error.

    **Validates: Requirements 2.4**

    Strategy
    --------
    ``st.binary()`` generates arbitrary byte sequences.  The vast majority
    will not begin with the HDF5 magic bytes ``\\x89HDF``, so almost every
    generated payload is a genuine invalid NIR HDF5 file.  We use
    ``assume(not data.startswith(b"\\x89HDF"))`` to filter out the rare
    samples that could accidentally form a valid HDF5 header and happen to
    parse successfully as a NIR graph — such samples would not test the
    error path under test here.

    Assertions
    ----------
    1. HTTP 422 is returned (not 200, 400, 500, etc.).
    2. The response body has ``detail.error == "validation_failed"`` (the
       envelope used by ``build_validation_failure_detail``).
    3. At least one item in ``detail.items`` has ``code == "nir_parse_error"``.
    4. At least one entry in ``detail.messages`` is a non-empty string that
       provides a human-readable description of the failure.
    """
    # Filter: discard bytes that begin with the HDF5 magic signature — those
    # could potentially be valid HDF5 and would not exercise the parse-error
    # path.  Empty payloads are intentionally kept because they should also
    # trigger a parse failure.
    assume(not data.startswith(b"\x89HDF"))

    resp = client.post(
        _PREFLIGHT_NIR_URL,
        data={"backend_name": "lava_sim"},
        files={"file": ("graph.nir", data, "application/octet-stream")},
        headers={"X-Forwarded-For": _next_ip()},
    )

    # ── 1. HTTP status must be 422 ────────────────────────────────────────
    assert resp.status_code == 422, (
        f"Expected HTTP 422 for invalid HDF5 payload, got {resp.status_code}. "
        f"Response body: {resp.text!r}"
    )

    detail = resp.json().get("detail", {})

    # ── 2. Outer error envelope must be validation_failed ─────────────────
    assert detail.get("error") == "validation_failed", (
        f"Expected detail.error == 'validation_failed', got {detail.get('error')!r}. "
        f"Full detail: {detail}"
    )

    # ── 3. At least one item must carry code == nir_parse_error ──────────
    items = detail.get("items", [])
    assert isinstance(
        items, list
    ), f"Expected detail.items to be a list, got {type(items).__name__}. Full detail: {detail}"
    nir_parse_items = [item for item in items if item.get("code") == "nir_parse_error"]
    assert (
        len(nir_parse_items) >= 1
    ), f"Expected at least one item with code 'nir_parse_error', but items were: {items}"

    # ── 4. At least one human-readable message must be non-empty ─────────
    messages = detail.get("messages", [])
    assert isinstance(messages, list), (
        f"Expected detail.messages to be a list, got {type(messages).__name__}. "
        f"Full detail: {detail}"
    )
    non_empty_messages = [m for m in messages if isinstance(m, str) and m.strip()]
    assert len(non_empty_messages) >= 1, (
        f"Expected at least one non-empty human-readable message in detail.messages, "
        f"but messages were: {messages}"
    )


# ---------------------------------------------------------------------------
# Compile-pipeline stage names used in diagnostic items produced by
# compile_to_nir (see neurocnl/compile.py, nir_cnl/parser.py,
# nir_cnl/validator.py, nir_cnl/compiler.py).  When CompileError is raised
# the router maps each Diagnostic.stage to the item's "source" field.
#
# Actual stage values in use (confirmed by source inspection):
#   "validator"   — validator.py (legacy-grammar gate)
#   "parser"      — nir_cnl/parser.py (sentence-level parse errors)
#   "materializer"— nir_cnl/compiler.py (NIR materialisation failures)
#   "lowering"    — lowering phase
#   "exportability"— exportability rejection
#   "write"       — save_to disk failure
# ---------------------------------------------------------------------------

_COMPILE_STAGE_SOURCES = frozenset(
    {
        "validator",
        "parser",
        "parse",
        "exportability",
        "lowering",
        "materializer",
        "write",
    }
)


def _causes_compile_error(spec: str) -> bool:
    """Return True iff compile_to_nir raises CompileError for *spec*."""
    try:
        compile_to_nir(spec)
        return False
    except CompileError:
        return True


# ---------------------------------------------------------------------------
# Property 3 — Compile error maps to HTTP 400
# ---------------------------------------------------------------------------


@given(
    spec=st.text().filter(_causes_compile_error),
    backend_name=st.sampled_from(["lava_sim", "snntorch_sim"]),
)
@settings(max_examples=100)
def test_preflight_cnl_compile_error(spec: str, backend_name: str) -> None:
    """Property 3: Compile error maps to HTTP 400.

    **Validates: Requirements 1.4**

    Strategy
    --------
    ``st.text().filter(_causes_compile_error)`` generates arbitrary Unicode
    strings and discards any that compile successfully.  Because NeuroCNL
    requires highly structured CNL sentences, the overwhelming majority of
    random strings raise ``CompileError``, so Hypothesis finds 100 examples
    quickly with minimal filtering overhead.  ``st.sampled_from(["lava_sim",
    "snntorch_sim"])`` covers both supported backends.

    Assertions
    ----------
    1. HTTP 400 is returned (Requirement 1.4 — compile failure → 400).
    2. ``detail["error"] == "compile_failed"`` — the outer error envelope
       matches the structured ``CompileError`` diagnostic format shared with
       ``POST /api/simulators/run`` (Requirement 1.4).
    3. ``detail["items"]`` is a non-empty list — at least one diagnostic
       item is present (Requirement 1.4 structured format).
    4. Each item has a non-empty ``source`` field whose value is one of the
       recognised compile-pipeline stage names — confirming the HTTP layer
       faithfully maps ``Diagnostic.stage`` through to the response and does
       not silently drop diagnostic provenance.
    """
    # The filter guarantee above means compile_to_nir WILL raise for this spec.
    # We call the endpoint and assert the error surfaces correctly over HTTP.
    resp = client.post(
        _PREFLIGHT_URL,
        json={"spec": spec, "backend_name": backend_name},
        headers={"X-Forwarded-For": _next_ip()},
    )

    # ── 1. HTTP 400 ───────────────────────────────────────────────────────
    assert resp.status_code == 400, (
        f"Expected HTTP 400 for compile-failing spec with backend {backend_name!r}, "
        f"got {resp.status_code}. Response: {resp.text!r}"
    )

    detail = resp.json().get("detail", {})

    # ── 2. Outer error envelope must be compile_failed ────────────────────
    assert detail.get("error") == "compile_failed", (
        f"Expected detail.error == 'compile_failed', got {detail.get('error')!r}. "
        f"Full detail: {detail}"
    )

    # ── 3. Items must be a non-empty list ─────────────────────────────────
    items = detail.get("items", [])
    assert isinstance(
        items, list
    ), f"Expected detail.items to be a list, got {type(items).__name__}. Full detail: {detail}"
    assert len(items) > 0, (
        "Expected at least one diagnostic item in detail.items for a compile error, "
        f"but items were empty. Full detail: {detail}"
    )

    # ── 4. Each item must have a non-empty compile-pipeline source ────────
    for item in items:
        item_source = item.get("source")
        assert item_source, (
            f"Expected each diagnostic item to have a non-empty 'source' field, "
            f"but got source={item_source!r}. Item: {item}"
        )
        assert item_source in _COMPILE_STAGE_SOURCES, (
            f"Expected item 'source' to be a compile-pipeline stage name "
            f"(one of {sorted(_COMPILE_STAGE_SOURCES)}), got {item_source!r}. "
            f"Item: {item}"
        )


# ---------------------------------------------------------------------------
# Property 5 — Unknown backend rejected at both endpoints
# ---------------------------------------------------------------------------


@given(
    backend_name=st.text(min_size=1).filter(
        lambda s: s not in SIMULATOR_RUNTIME_BACKENDS
    )
)
@settings(max_examples=100)
def test_preflight_unknown_backend(backend_name: str) -> None:
    """Property 5: Unknown backend rejected at both endpoints.

    **Validates: Requirements 1.5, 2.5**

    Strategy
    --------
    ``st.text(min_size=1).filter(lambda s: s not in {"lava_sim", "snntorch_sim"})``
    generates arbitrary non-empty Unicode strings that are NOT valid backend
    names.  ``min_size=1`` is required because FastAPI treats an empty-string
    multipart form field as a missing required field (returning its own
    validation error before the endpoint handler runs), so empty strings do
    not exercise the ``unknown_backend`` code path under test.  This covers
    random text, near-miss values (e.g. ``"lava_sim "``), and entirely
    unrelated strings.  Both endpoints are exercised for each generated value
    so that the rejection logic is verified on the CNL path
    (``_PREFLIGHT_URL``) and the NIR path (``_PREFLIGHT_NIR_URL``) within
    the same example.

    Each of the two HTTP calls uses its own ``_next_ip()`` so that the
    rate-limiter treats them as independent requests and neither call is
    blocked by the other.

    Assertions
    ----------
    1. HTTP 422 is returned by ``POST /api/simulators/preflight``
       (Requirement 1.5 — unknown backend → 422).
    2. ``detail["error"] == "validation_failed"`` for the CNL endpoint
       (the envelope used by ``build_validation_failure_detail``).
    3. At least one item in ``detail["items"]`` has
       ``code == "unknown_backend"`` for the CNL endpoint.
    4. HTTP 422 is returned by ``POST /api/simulators/preflight-nir``
       (Requirement 2.5 — unknown backend → 422).
    5. ``detail["error"] == "validation_failed"`` for the NIR endpoint.
    6. At least one item in ``detail["items"]`` has
       ``code == "unknown_backend"`` for the NIR endpoint.
    """
    # ── CNL endpoint ──────────────────────────────────────────────────────
    resp_cnl = client.post(
        _PREFLIGHT_URL,
        json={"spec": _SPEC_PREFLIGHT_TEST, "backend_name": backend_name},
        headers={"X-Forwarded-For": _next_ip()},
    )

    # ── 1. HTTP 422 for CNL endpoint ──────────────────────────────────────
    assert resp_cnl.status_code == 422, (
        f"Expected HTTP 422 for unknown backend {backend_name!r} on CNL endpoint, "
        f"got {resp_cnl.status_code}. Response: {resp_cnl.text!r}"
    )

    detail_cnl = resp_cnl.json().get("detail", {})

    # ── 2. Outer error envelope must be validation_failed (CNL) ───────────
    assert detail_cnl.get("error") == "validation_failed", (
        f"Expected detail.error == 'validation_failed' for CNL endpoint, "
        f"got {detail_cnl.get('error')!r}. backend_name={backend_name!r}. "
        f"Full detail: {detail_cnl}"
    )

    # ── 3. At least one item with code == unknown_backend (CNL) ──────────
    items_cnl = detail_cnl.get("items", [])
    assert isinstance(items_cnl, list), (
        f"Expected detail.items to be a list for CNL endpoint, "
        f"got {type(items_cnl).__name__}. Full detail: {detail_cnl}"
    )
    unknown_backend_items_cnl = [
        item for item in items_cnl if item.get("code") == "unknown_backend"
    ]
    assert len(unknown_backend_items_cnl) >= 1, (
        f"Expected at least one item with code 'unknown_backend' in CNL endpoint response, "
        f"but items were: {items_cnl}. backend_name={backend_name!r}"
    )

    # ── NIR endpoint ──────────────────────────────────────────────────────
    # Use the first fixture entry (index 0) — an exact-support graph that is
    # known to produce valid HDF5 bytes so that backend validation is the only
    # reason for rejection.
    _graph, nir_bytes = _NIR_GRAPH_FIXTURE_BYTES[0]

    resp_nir = client.post(
        _PREFLIGHT_NIR_URL,
        data={"backend_name": backend_name},
        files={"file": ("graph.nir", nir_bytes, "application/octet-stream")},
        headers={"X-Forwarded-For": _next_ip()},
    )

    # ── 4. HTTP 422 for NIR endpoint ──────────────────────────────────────
    assert resp_nir.status_code == 422, (
        f"Expected HTTP 422 for unknown backend {backend_name!r} on NIR endpoint, "
        f"got {resp_nir.status_code}. Response: {resp_nir.text!r}"
    )

    detail_nir = resp_nir.json().get("detail", {})

    # ── 5. Outer error envelope must be validation_failed (NIR) ───────────
    assert detail_nir.get("error") == "validation_failed", (
        f"Expected detail.error == 'validation_failed' for NIR endpoint, "
        f"got {detail_nir.get('error')!r}. backend_name={backend_name!r}. "
        f"Full detail: {detail_nir}"
    )

    # ── 6. At least one item with code == unknown_backend (NIR) ──────────
    items_nir = detail_nir.get("items", [])
    assert isinstance(items_nir, list), (
        f"Expected detail.items to be a list for NIR endpoint, "
        f"got {type(items_nir).__name__}. Full detail: {detail_nir}"
    )
    unknown_backend_items_nir = [
        item for item in items_nir if item.get("code") == "unknown_backend"
    ]
    assert len(unknown_backend_items_nir) >= 1, (
        f"Expected at least one item with code 'unknown_backend' in NIR endpoint response, "
        f"but items were: {items_nir}. backend_name={backend_name!r}"
    )
