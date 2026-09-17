"""Public compile_to_nir() entrypoint for CNL → IR → NIR compilation.

This module is the primary public surface for the CNL → NIR pipeline.
It owns two exports:

- :class:`CompileError` — raised on any compilation failure, carrying a
  structured list of :class:`Diagnostic` objects so callers can surface
  actionable errors without parsing exception strings.
- :func:`compile_to_nir` — thin façade over the internal parse / lower /
  materialize stack.  Returns a ``nir.NIRGraph`` directly; no Nengo network
  is constructed.

Quick start::

    from neurocnl import compile_to_nir, CompileError

    spec = \"\"\"
    The network MUST contain an excitatory input population of 4 neurons
    The network MUST contain an excitatory output population of 2 neurons
    The input MUST project to output
    \"\"\"

    try:
        graph = compile_to_nir(spec)
    except CompileError as exc:
        for d in exc.diagnostics:
            print(f"[{d.stage}] {d.code}: {d.message}")
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path
from typing import TYPE_CHECKING

import nir

if TYPE_CHECKING:
    from neurocnl.nir_cnl.pipeline_config import PipelineConfig

__all__ = ["Diagnostic", "CompileError", "compile_to_nir", "compile_pipeline_config"]


@dataclass(slots=True)
class Diagnostic:
    """A single structured compilation diagnostic.

    Attributes
    ----------
    stage : str
        Pipeline stage that produced the diagnostic.
        One of ``"parse"``, ``"exportability"``, ``"lowering"``,
        ``"materializer"``, or ``"write"``.
    code : str
        Machine-readable error code (e.g. ``"parse_error"``,
        ``"unsupported_concepts"``).
    message : str
        Human-readable description of the problem.
    line : int or None
        Source line number in the CNL spec, when available.
    raw : str or None
        The raw CNL sentence that triggered the diagnostic, when available.
    hint : str or None
        Optional suggestion for how to resolve the problem.
    """

    stage: str
    code: str
    message: str
    line: int | None = None
    raw: str | None = None
    hint: str | None = None


class CompileError(Exception):
    """Raised when :func:`compile_to_nir` cannot produce a valid NIR graph.

    The exception message summarises the overall failure; fine-grained
    detail is available through the ``diagnostics`` attribute.

    Attributes
    ----------
    diagnostics : list[Diagnostic]
        One entry per failure.  Parse errors include line numbers; lowering
        and materializer errors describe the structural issue.

    Examples
    --------
    ::

        from neurocnl import compile_to_nir, CompileError

        try:
            graph = compile_to_nir(bad_spec)
        except CompileError as exc:
            for d in exc.diagnostics:
                loc = f" (line {d.line})" if d.line is not None else ""
                print(f"[{d.stage}] {d.code}: {d.message}{loc}")
    """

    def __init__(self, message: str, diagnostics: list[Diagnostic]) -> None:
        super().__init__(message)
        self.diagnostics: list[Diagnostic] = diagnostics

    def __str__(self) -> str:
        base = super().__str__()
        if not self.diagnostics:
            return base
        lines = [base]
        for d in self.diagnostics:
            loc = f" (line {d.line})" if d.line is not None else ""
            hint = f" — hint: {d.hint}" if d.hint else ""
            lines.append(f"  [{d.stage}] {d.code}: {d.message}{loc}{hint}")
        return "\n".join(lines)


def compile_to_nir(
    spec: str,
    *,
    save_to: str | os.PathLike[str] | None = None,
) -> nir.NIRGraph:
    """Compile a CNL specification string to a NIR graph.

    This is the primary public entrypoint for the ``CNL → IR → NIR``
    pipeline.  The contract is **fail-closed**: any unsupported concept,
    parse failure, or lowering error raises :class:`CompileError` with
    structured diagnostics rather than producing a silently dishonest graph.

    The function does **not** construct a Nengo network.  It delegates to
    the internal parse → lower → materialize stack and returns the resulting
    ``nir.NIRGraph`` directly.

    Parameters
    ----------
    spec : str
        CNL specification text.  Multi-line strings are accepted; blank lines
        and lines starting with ``#`` are treated as comments and ignored.
    save_to : str or Path, optional
        When provided, the compiled NIR graph is also written to this path
        as a ``.nir`` file.  Parent directories are created automatically.
        The graph is compiled first; a write failure does not discard it —
        :class:`CompileError` is raised with ``stage="write"`` while the
        successfully compiled graph is attached to the exception cause.

    Returns
    -------
    nir.NIRGraph
        The compiled NIR graph.  Concepts the current bridge cannot represent
        faithfully (e.g. ``refractory_period``, unscoped learning rules) are
        preserved as advisory metadata on the relevant nodes rather than
        silently dropped or approximated.  The ``nir_lowering_summary`` key
        in the graph's top-level metadata describes exactly what was lowered
        faithfully, what became metadata, and what was approximated.

    Raises
    ------
    CompileError
        Raised if any CNL sentence fails to parse, if the spec contains
        concepts that the current NIR bridge cannot represent honestly, or if
        IR lowering or NIR materialization fails.  The ``diagnostics``
        attribute carries one :class:`Diagnostic` per failure with machine-
        readable ``code`` and ``stage`` fields.

    Examples
    --------
    In-memory compilation::

        from neurocnl import compile_to_nir

        spec = \"\"\"
        The network MUST contain an excitatory input population of 4 neurons
        The network MUST contain an excitatory output population of 2 neurons
        The input MUST project to output
        The connection from input to output MUST have WITH synaptic weight of 0.5
        \"\"\"

        graph = compile_to_nir(spec)
        print(graph.nodes.keys())   # dict_keys(['input', 'weight_input_to_output_0', 'output'])

    Compile and save to disk::

        graph = compile_to_nir(spec, save_to="my_network.nir")

    Inspecting lowering fidelity::

        import json
        summary = graph.metadata.get("nir_lowering_summary", {})
        print(json.dumps(summary.get("concepts", {}), indent=2))

    Structured error handling::

        from neurocnl import compile_to_nir, CompileError

        try:
            graph = compile_to_nir(bad_spec)
        except CompileError as exc:
            for d in exc.diagnostics:
                loc = f" (line {d.line})" if d.line is not None else ""
                print(f"[{d.stage}] {d.code}: {d.message}{loc}")
    """
    # Phase 1 — legacy-grammar gate (Requirement 8.3, 8.4). Any
    # Biological_Grammar keyword or Structured_DSL_Token in the input
    # raises before the parser even sees the text. The validator never
    # raises; it returns one ``Diagnostic`` per match (already tagged
    # ``stage="validator"``) and we surface them here as a single
    # ``CompileError``.
    from neurocnl.nir_cnl.validator import scan_for_legacy_tokens

    legacy = scan_for_legacy_tokens(spec)
    if legacy:
        # Requirement 8.4 mandates that compile_to_nir raises with
        # code="legacy_grammar" regardless of whether the offending
        # token was a Biological_Grammar keyword or a Structured_DSL_Token.
        # Remap all validator diagnostics to the unified "legacy_grammar" code.
        remapped = [
            Diagnostic(
                stage=d.stage,
                code="legacy_grammar",
                message=d.message,
                line=d.line,
                raw=d.raw,
                hint=d.hint,
            )
            for d in legacy
        ]
        raise CompileError("Legacy CNL grammar detected.", remapped)

    # Phase 2 — natural-language parse (Requirement 1, 9.3). Any
    # ``ParseError`` carries the full diagnostic list; rewrap it as a
    # ``CompileError`` so callers see a single exception type.
    from neurocnl.nir_cnl.errors import ParseError
    from neurocnl.nir_cnl.parser import NIR_CNL_Parser

    try:
        records = NIR_CNL_Parser().parse(spec)
    except ParseError as exc:
        raise CompileError("CNL parse failed.", exc.errors) from exc

    # Phase 3 — structural validation + materialisation. The compiler
    # raises ``CompileError`` directly (it shares the class via
    # ``neurocnl.nir_cnl.errors``), so we let it propagate untouched.
    from neurocnl.nir_cnl.compiler import NIR_Compiler

    graph = NIR_Compiler().compile(records)

    # Phase 4 — optional persistence. The compiled graph already exists
    # in memory; ``save_to`` simply mirrors it to disk.
    if save_to is not None:
        path = Path(save_to)
        path.parent.mkdir(parents=True, exist_ok=True)
        try:
            nir.write(str(path), graph)
        except Exception as exc:
            diag = Diagnostic(
                stage="write",
                code="write_error",
                message=f"Failed to write NIR graph to disk: {exc}",
                hint=f"Check permissions and disk space for {path}",
            )
            raise CompileError("NIR write failed.", [diag]) from exc

    return graph


def compile_pipeline_config(spec: str) -> PipelineConfig | None:
    """Extract Train/Evaluate/Export pipeline config from a CNL spec.

    Companion to :func:`compile_to_nir`, **not** a modification to it:
    :func:`compile_to_nir`'s return type is embedded verbatim in every
    previously generated notebook's saved cell source
    (``graph = compile_to_nir(cnl_spec)``), so its signature must never
    change. This function runs the identical legacy-token gate and
    :class:`~neurocnl.nir_cnl.parser.NIR_CNL_Parser` parse — same
    fail-closed ``CompileError``-raising contract, including on a
    malformed Train/Evaluate/Export sentence — then returns
    :func:`~neurocnl.nir_cnl.pipeline_config.extract_pipeline_config`
    applied to the parsed records.

    Calling both this function and :func:`compile_to_nir` on the same
    *spec* parses the text twice; given spec sizes (single-digit KB,
    regex-only, no ML/network calls) this is negligible and was chosen
    over widening :func:`compile_to_nir`'s frozen return contract.

    Parameters
    ----------
    spec:
        CNL specification text. May contain architecture sentences
        (``Define``/``Connect``), pipeline sentences
        (``Train``/``Evaluate``/``Export``), or both — this function
        only looks at the pipeline sentences.

    Returns
    -------
    PipelineConfig or None
        ``None`` when *spec* contains no ``Train``/``Evaluate``/
        ``Export`` sentence.

    Raises
    ------
    CompileError
        If the legacy-token gate matches, or if any sentence in *spec*
        fails to parse (including an unrecognized pipeline clause,
        e.g. an unknown optimizer phrase).
    """
    from neurocnl.nir_cnl.validator import scan_for_legacy_tokens

    legacy = scan_for_legacy_tokens(spec)
    if legacy:
        remapped = [
            Diagnostic(
                stage=d.stage,
                code="legacy_grammar",
                message=d.message,
                line=d.line,
                raw=d.raw,
                hint=d.hint,
            )
            for d in legacy
        ]
        raise CompileError("Legacy CNL grammar detected.", remapped)

    from neurocnl.nir_cnl.errors import ParseError
    from neurocnl.nir_cnl.parser import NIR_CNL_Parser

    try:
        records = NIR_CNL_Parser().parse(spec)
    except ParseError as exc:
        raise CompileError("CNL parse failed.", exc.errors) from exc

    from neurocnl.nir_cnl.pipeline_config import extract_pipeline_config

    return extract_pipeline_config(records)
