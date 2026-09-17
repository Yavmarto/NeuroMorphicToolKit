"""Intermediate-representation record types for the NIR-native CNL pipeline.

This module defines the small, dependency-free record set that flows
between the three executable components of the NIR-native CNL pipeline:

    NIR_CNL_Parser  →  [NIRNodeRecord | NIREdgeRecord | NetworkContainer]  →  NIR_Compiler

The records carry only data structures from the Python standard library
(``int``, ``float``, ``str``, ``tuple``, ``dict``) plus the two array
declaration types defined here (:class:`ArraySpec`, :class:`ArrayValues`).
No ``numpy`` array is constructed at this layer — that materialisation
happens in :mod:`neurocnl.nir_cnl.compiler` once structural validation
has succeeded. Keeping the parser output free of ``numpy`` keeps this
module importable in minimal environments and makes the parser/compiler
contract surface explicit.

Records and their roles
-----------------------
ArraySpec
    A shape-only array declaration. Produced by the parser when a CNL
    sentence supplies a parameter shape but no explicit numeric values
    (e.g. ``with weight matrix shape (2, 3)``). The compiler materialises
    each :class:`ArraySpec` as ``numpy.zeros(shape, dtype=float)``.
    Frozen — once parsed, a shape declaration is immutable.

ArrayValues
    An explicit array declaration carrying both a shape and the flattened
    C-order numeric values. Produced by the parser for the canonical
    round-trip form ``with weight matrix shape (...) and weight matrix
    values (...)``. The compiler materialises each :class:`ArrayValues`
    as ``numpy.asarray(values, dtype=float).reshape(shape)``. Frozen —
    once parsed, an explicit array declaration is immutable.

NIRNodeRecord
    The parser's record for one node-declaration NL_Sentence. The parser
    builds this record incrementally as it consumes the verb phrase, the
    noun phrase, the identifier, and each ``with`` parameter clause, so
    the dataclass is intentionally mutable. The ``params`` dict accepts
    every parameter value kind the grammar produces (see the union below);
    ``metadata`` carries values recovered from ``annotated with metadata
    <key> equal to <value>`` clauses.

    The ``params`` value union covers every kind the parser emits:

    * ``int``  / ``float`` — scalar parameters such as ``tau`` or
      ``v_threshold``;
    * :class:`ArraySpec` — shape-only array declarations for the parser's
      shape-literal sub-grammar;
    * :class:`ArrayValues` — explicit-values array declarations for the
      round-trip ``shape (...) and ... values (...)`` form;
    * ``tuple[int, ...]`` — integer-tuple structural parameters such as
      ``stride``, ``padding``, ``dilation``, ``input_shape``, and
      ``kernel_size``.

    The ``metadata`` value union is restricted to the three Python
    primitive types the grammar permits in a metadata clause: ``str``,
    ``int``, and ``float``.

NIREdgeRecord
    The parser's record for one ``Connect <src> to <target>.``
    NL_Sentence. Mutable, like :class:`NIRNodeRecord`, so the parser can
    construct it field-by-field during sentence parsing.

NetworkContainer
    The parser's record for one ``Define a network named <id>.``
    NL_Sentence, optionally extended with a ``with timestep <seconds>``
    clause. Frozen — once a container declaration has been parsed, its
    identifier, source line, and declared timestep are fixed. When
    ``timestep_seconds`` is set, the compiler propagates it into every
    ``nir.LIF`` node's ``metadata["dt"]`` (unless that node already
    carries its own explicit ``dt``) and mirrors it onto the compiled
    graph's own ``metadata["dt"]``.

All five dataclasses use ``slots=True`` to keep instances compact and to
forbid stray attribute writes. ``ArraySpec``, ``ArrayValues``, and
``NetworkContainer`` are additionally ``frozen=True``; the two record
types the parser builds incrementally (:class:`NIRNodeRecord` and
:class:`NIREdgeRecord`) are mutable.
"""

from __future__ import annotations

from dataclasses import dataclass

__all__ = [
    "ArraySpec",
    "ArrayValues",
    "NIRNodeRecord",
    "NIREdgeRecord",
    "NetworkContainer",
    "TrainingConfigRecord",
    "EvaluationConfigRecord",
    "ExportConfigRecord",
]


@dataclass(frozen=True, slots=True)
class ArraySpec:
    """Shape-only array declaration produced by the parser.

    Used for parameter clauses of the form ``<phrase> shape (d1, ..., dN)``
    where the user supplies only the array's shape and expects the
    compiler to synthesise a zero-filled ``numpy`` array.

    Attributes
    ----------
    shape:
        Tuple of integer dimensions, e.g. ``(2, 3)`` for a 2×3 matrix or
        ``(N,)`` for a 1-D vector. Validation of dimension positivity and
        the documented ``[1, 4096]`` range is performed by the compiler,
        not by this dataclass.
    """

    shape: tuple[int, ...]


@dataclass(frozen=True, slots=True)
class ArrayValues:
    """Explicit array declaration carrying both a shape and a flattened
    C-order value list.

    Used for the canonical round-trip form
    ``<phrase> shape (d1, ..., dN) and <phrase> values (v1, ..., vM)``
    where ``M = d1 * d2 * ... * dN``. The compiler reshapes the flat
    value tuple back into an N-dimensional ``numpy`` array.

    Attributes
    ----------
    shape:
        Tuple of integer dimensions describing the target N-D shape.
    values:
        Flattened (C-order) tuple of every element value. Its length must
        equal ``prod(shape)``; the compiler enforces this invariant.
    """

    shape: tuple[int, ...]
    values: tuple[float, ...]


@dataclass(slots=True)
class NIRNodeRecord:
    """Parser record for one node-declaration NL_Sentence.

    Mutable so the parser can populate fields incrementally while
    consuming a sentence's verb phrase, noun phrase, identifier, and
    successive ``with`` parameter clauses.

    Attributes
    ----------
    name:
        Node identifier exactly as written after ``named`` in the
        sentence, e.g. ``"lif1"``. Carries no surrounding quotes.
    primitive:
        Primitive class name as resolved against the noun-phrase mapping
        table, e.g. ``"LIF"``, ``"Conv2d"``, ``"Input"``. The compiler
        uses this string to look up the corresponding ``nir.*`` class.
    params:
        Mapping from ``nir.*`` constructor argument name to its parsed
        value. Values are one of: a scalar ``int`` or ``float``; an
        :class:`ArraySpec` for shape-only declarations; an
        :class:`ArrayValues` for explicit-values declarations; or a
        ``tuple[int, ...]`` for integer-tuple structural parameters such
        as ``stride``, ``padding``, ``dilation``, ``input_shape``, or
        ``kernel_size``.
    metadata:
        Mapping from metadata key to its parsed value. Values are
        restricted to ``str``, ``int``, or ``float`` to match the
        grammar's metadata-clause sub-rule.
    line:
        1-indexed source line where the sentence appeared, used for
        diagnostic reporting.
    """

    name: str
    primitive: str
    params: dict[str, int | float | ArraySpec | ArrayValues | tuple[int, ...]]
    metadata: dict[str, str | int | float]
    line: int


@dataclass(slots=True)
class NIREdgeRecord:
    """Parser record for one ``Connect <src> to <target>.`` NL_Sentence.

    Mutable so the parser can populate the source and target identifiers
    in two separate parsing steps.

    Attributes
    ----------
    src:
        Source node identifier (unquoted).
    target:
        Target node identifier (unquoted).
    line:
        1-indexed source line where the sentence appeared.
    """

    src: str
    target: str
    line: int


@dataclass(frozen=True, slots=True)
class NetworkContainer:
    """Parser record for one ``Define a network named <id>.`` NL_Sentence.

    Immutable: a network container declaration is a single closed clause
    with no fields populated incrementally.

    Attributes
    ----------
    name:
        Network identifier exactly as written after ``named``.
    line:
        1-indexed source line where the sentence appeared.
    timestep_seconds:
        Optional declared simulation timestep in seconds, from an
        optional ``with timestep <seconds>`` clause (per Requirement
        1.7's optional network-timestep clause). ``None`` when the
        sentence declares no timestep, in which case downstream
        codegen falls back to its own existing default unchanged.
    """

    name: str
    line: int
    timestep_seconds: float | None = None


@dataclass(frozen=True, slots=True)
class TrainingConfigRecord:
    """Parser record for one ``Train the network for <N> epochs ...`` sentence.

    Immutable: the sentence's ``with``-clause list is parsed in full
    before the record is constructed, so there is no incremental
    population step (unlike :class:`NIRNodeRecord`).

    Attributes
    ----------
    epochs:
        Mandatory epoch count — the sentence's anchor clause.
    learning_rate, batch_size, optimizer, training_strategy, loss_function:
        Optional scalar/closed-vocabulary fields from the sentence's
        ``with`` clause list. ``optimizer``/``training_strategy``/
        ``loss_function`` carry the canonical backend id (e.g.
        ``"Adam"``, ``"surrogate_gradient"``, ``"mse_count"``), not the
        English surface phrase. ``None`` when the corresponding clause
        was not present in the sentence.
    line:
        1-indexed source line where the sentence appeared.
    """

    epochs: int
    learning_rate: float | None
    batch_size: int | None
    optimizer: str | None
    training_strategy: str | None
    loss_function: str | None
    line: int


@dataclass(frozen=True, slots=True)
class EvaluationConfigRecord:
    """Parser record for one ``Evaluate the network ...`` sentence.

    Attributes
    ----------
    eval_metrics:
        Tuple of lower-cased, open-vocabulary metric names from the
        optional ``with <metrics> metrics`` clause, or ``None`` when the
        sentence carries no metric list (bare ``Evaluate the network.``
        form). The record's mere presence in the parse output signals
        that evaluation should run — extraction sets
        ``PipelineConfig.run_evaluation = True`` whenever this record is
        present, independent of whether ``eval_metrics`` is ``None``.
    line:
        1-indexed source line where the sentence appeared.
    """

    eval_metrics: tuple[str, ...] | None
    line: int


@dataclass(frozen=True, slots=True)
class ExportConfigRecord:
    """Parser record for one ``Export the trained network to ...`` sentence.

    Attributes
    ----------
    export_nir, generate_py_download:
        ``True`` iff the corresponding closed-vocabulary target
        (``NIR`` / ``a Python script``) appeared in the sentence's
        target list. The grammar has no negative form — a target's
        absence leaves the corresponding field ``False`` here, and
        extraction/merge logic treats ``False`` as "not specified by
        CNL" rather than "explicitly disabled".
    line:
        1-indexed source line where the sentence appeared.
    """

    export_nir: bool
    generate_py_download: bool
    line: int
