"""Shared record builders for the weight-initialisation test suites.

Extracted from ``test_compiler_weight_init.py`` so each split-out test
module (zero-fill/xavier/kaiming strategies, diagnostics, RNG/integration)
can build ``NIRNodeRecord`` fixtures without a CNL text round-trip.
"""

from __future__ import annotations

from typing import Any, cast

import numpy as np

from neurocnl.nir_cnl.compiler import NIR_Compiler
from neurocnl.nir_cnl.ir_types import (
    ArraySpec,
    ArrayValues,
    EvaluationConfigRecord,
    ExportConfigRecord,
    NetworkContainer,
    NIREdgeRecord,
    NIRNodeRecord,
    TrainingConfigRecord,
)

_CompilableRecord = (
    NIRNodeRecord
    | NIREdgeRecord
    | NetworkContainer
    | TrainingConfigRecord
    | EvaluationConfigRecord
    | ExportConfigRecord
)


def io_records(
    in_name: str = "inp", out_name: str = "outp"
) -> list[NIRNodeRecord | NIREdgeRecord]:
    """Return a minimal Input + Output + edge record list."""
    return [
        NIRNodeRecord(
            name=in_name,
            primitive="Input",
            params={"input_type": (1,)},
            metadata={},
            line=1,
        ),
        NIRNodeRecord(
            name=out_name,
            primitive="Output",
            params={"output_type": (1,)},
            metadata={},
            line=1,
        ),
        NIREdgeRecord(src=in_name, target=out_name, line=1),
    ]


def make_linear_record(
    M: int,
    N: int,
    *,
    weight_init: str = "xavier",
    seed: int | None = None,
    name: str = "lin1",
    line: int = 1,
) -> NIRNodeRecord:
    """Build a Linear ``NIRNodeRecord`` with ``ArraySpec`` weight."""
    metadata: dict[str, Any] = {"weight_init": weight_init}
    if seed is not None:
        metadata["seed"] = seed
    return NIRNodeRecord(
        name=name,
        primitive="Linear",
        params={"weight": ArraySpec(shape=(M, N))},
        metadata=metadata,
        line=line,
    )


def compile_linear(record: NIRNodeRecord) -> np.ndarray[Any, Any]:
    """Compile *record* through ``NIR_Compiler`` and return the weight array."""
    records: list[_CompilableRecord] = [record, *io_records()]
    graph = NIR_Compiler().compile(records)
    return cast("np.ndarray[Any, Any]", graph.nodes[record.name].weight)


def make_conv1d_record(
    out_ch: int,
    in_ch: int,
    kernel: int,
    *,
    weight_init: str = "xavier",
    seed: int | None = None,
    name: str = "conv1",
    line: int = 1,
) -> NIRNodeRecord:
    """Build a Conv1d ``NIRNodeRecord`` with shape-only weight."""
    metadata: dict[str, Any] = {"weight_init": weight_init}
    if seed is not None:
        metadata["seed"] = seed
    return NIRNodeRecord(
        name=name,
        primitive="Conv1d",
        params={
            "weight": ArraySpec(shape=(out_ch, in_ch, kernel)),
            "bias": ArrayValues(
                shape=(out_ch,), values=tuple(0.0 for _ in range(out_ch))
            ),
            "stride": (1,),
            "padding": (0,),
            "dilation": (1,),
            "groups": 1,
            "input_shape": 8,
        },
        metadata=metadata,
        line=line,
    )


def compile_conv1d(record: NIRNodeRecord) -> np.ndarray[Any, Any]:
    """Compile *record* through ``NIR_Compiler`` and return the weight array."""
    records: list[_CompilableRecord] = [record, *io_records()]
    graph = NIR_Compiler().compile(records)
    return cast("np.ndarray[Any, Any]", graph.nodes[record.name].weight)


def legacy_rng_state() -> tuple[str, np.ndarray[Any, Any], int, int, float]:
    """Snapshot the global legacy MT19937 RNG state as a typed tuple.

    ``numpy.random.get_state()`` is typed to return
    ``dict[str, Any] | tuple[...]`` because the same call also serves the
    newer bit-generator API; the legacy ``RandomState`` singleton this
    module tests always returns the 5-tuple form at runtime.
    """
    state = np.random.get_state()
    assert isinstance(state, tuple)
    return state
