"""NIR-Native CNL parser.

This module implements :class:`NIR_CNL_Parser`, the natural-language
parser for the NIR-Native Controlled Natural Language. The parser
converts CNL prose such as::

    Define a network named demo.
    Define an input port named in1 with shape (1,).
    Define a LIF neuron named lif1 with time
        constant 0.02, resistance 1.0, leak voltage 0.0,
        and firing threshold 1.0.
    Connect in1 to lif1.

into a list of :class:`~neurocnl.nir_cnl.ir_types.NIRNodeRecord`,
:class:`~neurocnl.nir_cnl.ir_types.NIREdgeRecord`, and
:class:`~neurocnl.nir_cnl.ir_types.NetworkContainer` records that the
:class:`~neurocnl.nir_cnl.compiler.NIR_Compiler` materialises into a
``nir.NIRGraph``.

Pipeline
--------
1. Pre-validate the input against the legacy-token denylist
   (Requirements 1.8 and 8.4) by calling
   :func:`~neurocnl.nir_cnl.validator.scan_for_legacy_tokens` first.
   Any matched diagnostics are accumulated and surface in the final
   :class:`ParseError`.
2. Tokenise. Lines whose first non-whitespace character is ``#`` are
   treated as comments and dropped (Requirement 1.9). The remainder is
   scanned with a single multi-pattern regex into ``Token(kind, value,
   line)`` records.
3. Split the token stream on ``.`` tokens into sentence-level token
   lists.
4. Dispatch each sentence on its leading verb token: ``Connect`` →
   edge, ``Define a network`` / ``Create a network`` → network
   container, anything else starting with ``Define``/``Create`` →
   node declaration.
5. Accumulate every per-sentence diagnostic; once every sentence has
   been processed (or the 10 000-entry cap has been reached), if the
   diagnostic list is non-empty raise
   :class:`~neurocnl.nir_cnl.errors.ParseError` carrying every
   collected diagnostic.

Design references
-----------------
* ``.kiro/specs/nir-native-cnl/requirements.md`` Requirement 1
  (grammar surface), Requirement 9 (diagnostic field contract).
* ``.kiro/specs/nir-native-cnl/design.md`` § "CNL → NIR (parse +
  compile)" and § "Error Codes".
"""

from __future__ import annotations

from neurocnl.nir_cnl.diagnostics import (
    MAX_DIAGNOSTICS,
    MAX_RAW_LEN,
    SentenceError,
    diagnostic_from_sentence,
    finalize_diagnostics,
    sentence_raw,
)
from neurocnl.nir_cnl.errors import Diagnostic, ParseError
from neurocnl.nir_cnl.grammar_tables import (
    export_target_id_to_phrase,
    export_target_phrase_to_id,
    keyword_set,
)
from neurocnl.nir_cnl.ir_types import (
    EvaluationConfigRecord,
    ExportConfigRecord,
    NetworkContainer,
    NIREdgeRecord,
    NIRNodeRecord,
    TrainingConfigRecord,
)
from neurocnl.nir_cnl.token_cursor import (
    _IDENTIFIER_TOKEN_KINDS,
    _SORTED_NOUN_PHRASES,
    _classify_train_clause,
    _consume_longest_noun_phrase,
    _consume_longest_phrase,
    _expect_word,
    _find_clause_end,
    _merge_clause_parts,
    _parse_int_scalar,
    _parse_metadata_clause,
    _parse_param_clause,
    _parse_scalar_number,
    _validate_identifier,
)
from neurocnl.nir_cnl.tokenizer import Token
from neurocnl.nir_cnl.tokenizer import split_sentences as _split_sentences
from neurocnl.nir_cnl.tokenizer import tokenize as _tokenize
from neurocnl.nir_cnl.validator import scan_for_legacy_tokens

__all__ = [
    "ParseError",
    "NIR_CNL_Parser",
    "Token",
    "_split_sentences",
    "_tokenize",
]

# Private compatibility aliases retained while sentence parsers still live here.
_SentenceError = SentenceError
_MAX_RAW_LEN = MAX_RAW_LEN
_MAX_DIAGNOSTICS = MAX_DIAGNOSTICS
_sentence_raw = sentence_raw


# ---------------------------------------------------------------------------
# Per-sentence parsers
# ---------------------------------------------------------------------------


def _parse_node_sentence(tokens: list[Token]) -> NIRNodeRecord:
    """Parse a node-declaration NL_Sentence.

    Implements Requirements 1.2, 1.3, 1.4, 1.5, 1.10, 1.11, 1.12, 10.2,
    and 10.6:

    * matches ``(?i)(define|create) (a|an)`` as the verb phrase;
    * greedily consumes the longest noun phrase from
      ``noun_phrase_to_primitive`` (case-insensitive), raising
      ``unknown_primitive_phrase`` on miss;
    * parses ``named <identifier>`` against the Requirement 1.3 regex
      (length ≤ 64), raising ``invalid_identifier`` on miss;
    * parses optional ``with <param-clauses>`` against
      ``parameter_phrases[primitive]``;
    * dispatches each clause's value to the appropriate kind
      (scalar, shape literal, parenthesised int tuple, or string for
      metadata only); merges ``shape`` + ``values`` sub-clauses into
      :class:`ArrayValues`;
    * accepts any number of trailing
      ``annotated with metadata <key> equal to <value>`` clauses,
      raising ``duplicate_metadata_key`` on byte-equal duplicate keys.
    """
    pos = 0
    if (
        pos >= len(tokens)
        or tokens[pos].kind != "word"
        or tokens[pos].value.lower() not in ("define", "create")
    ):
        raise _SentenceError(
            code="syntax_error",
            message="Node sentence must begin with 'Define' or 'Create'.",
        )
    pos += 1
    if (
        pos >= len(tokens)
        or tokens[pos].kind != "word"
        or tokens[pos].value.lower() not in ("a", "an")
    ):
        raise _SentenceError(
            code="syntax_error",
            message="Expected 'a' or 'an' after verb.",
        )
    pos += 1

    primitive, n = _consume_longest_noun_phrase(tokens, pos)
    if primitive is None:
        raise _SentenceError(
            code="unknown_primitive_phrase",
            message="Unknown primitive noun phrase.",
            hint=f"Valid phrases: {', '.join(_SORTED_NOUN_PHRASES)}",
        )
    pos += n

    pos = _expect_word(tokens, pos, "named", code="syntax_error")
    if pos >= len(tokens) or tokens[pos].kind not in _IDENTIFIER_TOKEN_KINDS:
        raise _SentenceError(
            code="invalid_identifier",
            message="Expected identifier after 'named'.",
        )
    name = tokens[pos].value
    if not _validate_identifier(name):
        raise _SentenceError(
            code="invalid_identifier",
            message=(
                f"Identifier {name!r} does not match the contract "
                f"[A-Za-z_][A-Za-z0-9_]* (length ≤ 64)."
            ),
        )
    pos += 1

    line = tokens[0].line
    working: dict[str, dict[str, object]] = {}
    metadata: dict[str, str | int | float] = {}

    # Optional ``with`` block: at least one parameter clause follows
    # the ``with`` keyword. Metadata clauses may appear *after* the
    # parameter list (separated by comma or ``and``) or directly after
    # the identifier with no parameter clauses at all.
    if (
        pos < len(tokens)
        and tokens[pos].kind == "word"
        and tokens[pos].value.lower() == "with"
    ):
        pos += 1
        # Either the first token is ``annotated`` (a metadata-only
        # ``with``) or it's a parameter phrase.
        if (
            pos < len(tokens)
            and tokens[pos].kind == "word"
            and tokens[pos].value.lower() == "annotated"
        ):
            # Defer to metadata parsing — no parameter clauses.
            pass
        else:
            arg_name, sub_form, value, pos = _parse_param_clause(tokens, pos, primitive)
            working.setdefault(arg_name, {})[sub_form] = value
            while pos < len(tokens):
                # Connectives between parameter clauses.
                if tokens[pos].kind == "comma":
                    pos += 1
                    if (
                        pos < len(tokens)
                        and tokens[pos].kind == "word"
                        and tokens[pos].value.lower() == "and"
                    ):
                        pos += 1
                elif tokens[pos].kind == "word" and tokens[pos].value.lower() == "and":
                    pos += 1
                else:
                    break
                # If the next token starts a metadata clause, hand off
                # to the metadata loop below.
                if (
                    pos < len(tokens)
                    and tokens[pos].kind == "word"
                    and tokens[pos].value.lower() == "annotated"
                ):
                    break
                arg_name, sub_form, value, pos = _parse_param_clause(
                    tokens, pos, primitive
                )
                working.setdefault(arg_name, {})[sub_form] = value

    # Trailing ``annotated with metadata <key> equal to <value>``
    # clauses, possibly separated by commas / ``and`` connectives.
    while pos < len(tokens):
        if tokens[pos].kind == "comma":
            pos += 1
            if (
                pos < len(tokens)
                and tokens[pos].kind == "word"
                and tokens[pos].value.lower() == "and"
            ):
                pos += 1
            continue
        if tokens[pos].kind == "word" and tokens[pos].value.lower() == "and":
            pos += 1
            continue
        if tokens[pos].kind == "word" and tokens[pos].value.lower() == "annotated":
            pos = _parse_metadata_clause(tokens, pos, metadata)
            continue
        raise _SentenceError(
            code="syntax_error",
            message=(f"Unexpected token {tokens[pos].value!r} in node sentence."),
        )

    return NIRNodeRecord(
        name=name,
        primitive=primitive,
        params=_merge_clause_parts(working),
        metadata=metadata,
        line=line,
    )


def _parse_edge_sentence(tokens: list[Token]) -> NIREdgeRecord:
    """Parse ``Connect <src> to <target>`` per Requirement 1.6.

    Both identifiers are validated against the Requirement 1.3 regex.
    """
    pos = 0
    if (
        pos >= len(tokens)
        or tokens[pos].kind != "word"
        or tokens[pos].value.lower() != "connect"
    ):
        raise _SentenceError(
            code="syntax_error",
            message="Edge sentence must begin with 'Connect'.",
        )
    pos += 1
    if pos >= len(tokens) or tokens[pos].kind not in _IDENTIFIER_TOKEN_KINDS:
        raise _SentenceError(
            code="invalid_identifier",
            message="Expected source identifier after 'Connect'.",
        )
    src = tokens[pos].value
    if not _validate_identifier(src):
        raise _SentenceError(
            code="invalid_identifier",
            message=(
                f"Source identifier {src!r} does not match [A-Za-z_][A-Za-z0-9_]* (length ≤ 64)."
            ),
        )
    pos += 1
    pos = _expect_word(tokens, pos, "to")
    if pos >= len(tokens) or tokens[pos].kind not in _IDENTIFIER_TOKEN_KINDS:
        raise _SentenceError(
            code="invalid_identifier",
            message="Expected target identifier after 'to'.",
        )
    target = tokens[pos].value
    if not _validate_identifier(target):
        raise _SentenceError(
            code="invalid_identifier",
            message=(
                f"Target identifier {target!r} does not match [A-Za-z_][A-Za-z0-9_]* (length ≤ 64)."
            ),
        )
    pos += 1
    if pos != len(tokens):
        raise _SentenceError(
            code="syntax_error",
            message="Unexpected tokens after edge sentence.",
        )
    return NIREdgeRecord(src=src, target=target, line=tokens[0].line)


def _parse_active_voice_edge_sentence(tokens: list[Token]) -> NIREdgeRecord:
    """Parse ``<src> connects to <target>`` per active-voice edge form.

    Both identifiers are validated against the Requirement 1.3 regex.
    """
    pos = 0
    # First token is the source identifier
    if pos >= len(tokens) or tokens[pos].kind not in _IDENTIFIER_TOKEN_KINDS:
        raise _SentenceError(
            code="invalid_identifier",
            message="Expected source identifier at start of active-voice edge sentence.",
        )
    src = tokens[pos].value
    if not _validate_identifier(src):
        raise _SentenceError(
            code="invalid_identifier",
            message=(
                f"Source identifier {src!r} does not match [A-Za-z_][A-Za-z0-9_]* (length ≤ 64)."
            ),
        )
    pos += 1
    # Expect 'connects'
    pos = _expect_word(tokens, pos, "connects")
    # Expect 'to'
    pos = _expect_word(tokens, pos, "to")
    # Target identifier
    if pos >= len(tokens) or tokens[pos].kind not in _IDENTIFIER_TOKEN_KINDS:
        raise _SentenceError(
            code="invalid_identifier",
            message="Expected target identifier after 'connects to'.",
        )
    target = tokens[pos].value
    if not _validate_identifier(target):
        raise _SentenceError(
            code="invalid_identifier",
            message=(
                f"Target identifier {target!r} does not match [A-Za-z_][A-Za-z0-9_]* (length ≤ 64)."
            ),
        )
    pos += 1
    if pos != len(tokens):
        raise _SentenceError(
            code="syntax_error",
            message="Unexpected tokens after active-voice edge sentence.",
        )
    return NIREdgeRecord(src=src, target=target, line=tokens[0].line)


def _parse_network_sentence(tokens: list[Token]) -> NetworkContainer:
    """Parse ``Define a network named <id>`` per Requirement 1.7.

    Both ``Define`` and the synonym ``Create`` are accepted; the
    identifier is validated against the Requirement 1.3 regex.

    An optional trailing ``with timestep <seconds>`` clause declares the
    network's simulation timestep in seconds (Requirement 1.7's optional
    network-timestep clause). When present, the compiler propagates it
    into every ``nir.LIF`` node's ``metadata["dt"]`` that doesn't already
    carry its own explicit ``dt``. The declared value must be a positive
    number — a zero or negative timestep would later cause a division by
    zero deep in the snnTorch codegen's threshold rescale.
    """
    pos = 0
    if (
        pos >= len(tokens)
        or tokens[pos].kind != "word"
        or tokens[pos].value.lower() not in ("define", "create")
    ):
        raise _SentenceError(
            code="syntax_error",
            message="Network sentence must begin with 'Define' or 'Create'.",
        )
    pos += 1
    if (
        pos >= len(tokens)
        or tokens[pos].kind != "word"
        or tokens[pos].value.lower() not in ("a", "an")
    ):
        raise _SentenceError(
            code="syntax_error",
            message="Expected 'a' or 'an' after verb.",
        )
    pos += 1
    pos = _expect_word(tokens, pos, "network")
    pos = _expect_word(tokens, pos, "named")
    if pos >= len(tokens) or tokens[pos].kind not in _IDENTIFIER_TOKEN_KINDS:
        raise _SentenceError(
            code="invalid_identifier",
            message="Expected identifier after 'named'.",
        )
    name = tokens[pos].value
    if not _validate_identifier(name):
        raise _SentenceError(
            code="invalid_identifier",
            message=(
                f"Network identifier {name!r} does not match [A-Za-z_][A-Za-z0-9_]* (length ≤ 64)."
            ),
        )
    pos += 1

    timestep_seconds: float | None = None
    if pos < len(tokens):
        pos = _expect_word(tokens, pos, "with")
        pos = _expect_word(tokens, pos, "timestep")
        value, pos = _parse_scalar_number(tokens, pos)
        timestep_seconds = float(value)
        if timestep_seconds <= 0:
            raise _SentenceError(
                code="invalid_value",
                message=f"Network timestep must be positive, got {timestep_seconds!r}.",
                hint="Declare a positive timestep in seconds, e.g. 'with timestep 0.001'.",
            )

    if pos != len(tokens):
        raise _SentenceError(
            code="syntax_error",
            message="Unexpected tokens after network sentence.",
        )
    return NetworkContainer(
        name=name, line=tokens[0].line, timestep_seconds=timestep_seconds
    )


# ---------------------------------------------------------------------------
# Pipeline sentence parsers (Train / Evaluate / Export)
# ---------------------------------------------------------------------------


def _parse_train_sentence(tokens: list[Token]) -> TrainingConfigRecord:
    """Parse ``Train the network for <N> epochs [with <clauses>].``

    ``for <N> epochs`` is the mandatory anchor. The optional ``with``
    tail carries an order-independent, comma/``and``-joined list of up
    to five clauses (learning rate, batch size, optimizer, training
    strategy, loss function); each clause kind may appear at most once
    (``duplicate_pipeline_clause`` otherwise).
    """
    pos = 0
    pos = _expect_word(tokens, pos, "train")
    pos = _expect_word(tokens, pos, "the")
    pos = _expect_word(tokens, pos, "network")
    pos = _expect_word(tokens, pos, "for")
    if pos >= len(tokens) or tokens[pos].kind != "number":
        got = tokens[pos].value if pos < len(tokens) else "<end of sentence>"
        raise _SentenceError(
            code="invalid_value",
            message=f"Expected integer epoch count after 'for', got {got!r}.",
        )
    epochs, pos = _parse_int_scalar(tokens, pos, "epochs")
    pos = _expect_word(tokens, pos, "epochs")
    line = tokens[0].line

    learning_rate: float | None = None
    batch_size: int | None = None
    optimizer: str | None = None
    training_strategy: str | None = None
    loss_function: str | None = None
    seen_kinds: set[str] = set()

    if pos < len(tokens):
        pos = _expect_word(tokens, pos, "with")
        while True:
            end = _find_clause_end(tokens, pos)
            clause_tokens = tokens[pos:end]
            if not clause_tokens:
                raise _SentenceError(
                    code="syntax_error",
                    message="Expected a training clause.",
                )
            kind, value = _classify_train_clause(clause_tokens)
            if kind in seen_kinds:
                raise _SentenceError(
                    code="duplicate_pipeline_clause",
                    message=f"Duplicate {kind} clause in Train sentence.",
                )
            seen_kinds.add(kind)
            if kind == "learning_rate":
                learning_rate = value  # type: ignore[assignment]
            elif kind == "batch_size":
                batch_size = value  # type: ignore[assignment]
            elif kind == "optimizer":
                optimizer = value  # type: ignore[assignment]
            elif kind == "training_strategy":
                training_strategy = value  # type: ignore[assignment]
            elif kind == "loss_function":
                loss_function = value  # type: ignore[assignment]
            pos = end
            if pos >= len(tokens):
                break
            if tokens[pos].kind == "comma":
                pos += 1
                if (
                    pos < len(tokens)
                    and tokens[pos].kind == "word"
                    and tokens[pos].value.lower() == "and"
                ):
                    pos += 1
            elif tokens[pos].kind == "word" and tokens[pos].value.lower() == "and":
                pos += 1
            else:
                raise _SentenceError(
                    code="syntax_error",
                    message=f"Unexpected token {tokens[pos].value!r} after training clause.",
                )
            if pos >= len(tokens):
                raise _SentenceError(
                    code="syntax_error",
                    message="Expected a training clause after connective.",
                )

    return TrainingConfigRecord(
        epochs=epochs,
        learning_rate=learning_rate,
        batch_size=batch_size,
        optimizer=optimizer,
        training_strategy=training_strategy,
        loss_function=loss_function,
        line=line,
    )


def _parse_evaluate_sentence(tokens: list[Token]) -> EvaluationConfigRecord:
    """Parse ``Evaluate the network [with <metric-list> metrics].``

    The bare form (no ``with`` tail) sets ``eval_metrics=None`` —
    presence of the record alone signals evaluation should run. The
    metric list is open-vocabulary (no grammar-table lookup), matching
    the fact that ``eval_metrics`` is not a closed enum in
    ``PipelineConfigPayload`` today.
    """
    pos = 0
    pos = _expect_word(tokens, pos, "evaluate")
    pos = _expect_word(tokens, pos, "the")
    pos = _expect_word(tokens, pos, "network")
    line = tokens[0].line
    if pos == len(tokens):
        return EvaluationConfigRecord(eval_metrics=None, line=line)

    pos = _expect_word(tokens, pos, "with")
    if pos >= len(tokens):
        raise _SentenceError(
            code="syntax_error",
            message="Expected a metric list after 'with'.",
        )
    if not (tokens[-1].kind == "word" and tokens[-1].value.lower() == "metrics"):
        raise _SentenceError(
            code="syntax_error",
            message="Expected the sentence to end with 'metrics'.",
        )
    metric_tokens = tokens[pos:-1]
    metrics: list[str] = []
    for tok in metric_tokens:
        if tok.kind == "comma":
            continue
        if tok.kind == "word" and tok.value.lower() == "and":
            continue
        if tok.kind != "word":
            raise _SentenceError(
                code="syntax_error",
                message=f"Unexpected token {tok.value!r} in metric list.",
            )
        metrics.append(tok.value.lower())
    if not metrics:
        raise _SentenceError(
            code="syntax_error",
            message="Expected at least one metric before 'metrics'.",
        )
    return EvaluationConfigRecord(eval_metrics=tuple(metrics), line=line)


def _parse_export_sentence(tokens: list[Token]) -> ExportConfigRecord:
    """Parse ``Export the trained network to <target-list>.``

    At least one closed-vocabulary target (``NIR`` / ``a Python
    script``) is required — a target-less Export sentence asserts
    nothing, so it is rejected as a ``syntax_error``.
    """
    pos = 0
    pos = _expect_word(tokens, pos, "export")
    pos = _expect_word(tokens, pos, "the")
    pos = _expect_word(tokens, pos, "trained")
    pos = _expect_word(tokens, pos, "network")
    pos = _expect_word(tokens, pos, "to")
    line = tokens[0].line

    def _consume_target(p: int) -> tuple[str, int]:
        target_id, n = _consume_longest_phrase(tokens, p, export_target_phrase_to_id)
        if target_id is None:
            raise _SentenceError(
                code="unknown_export_target_phrase",
                message="Unknown export target phrase.",
                hint=f"Valid targets: {', '.join(sorted(export_target_id_to_phrase.values()))}",
            )
        return target_id, p + n

    if pos >= len(tokens):
        raise _SentenceError(
            code="syntax_error",
            message="Expected at least one export target after 'to'.",
        )
    targets: set[str] = set()
    target_id, pos = _consume_target(pos)
    targets.add(target_id)

    while pos < len(tokens):
        if tokens[pos].kind == "comma":
            pos += 1
            if (
                pos < len(tokens)
                and tokens[pos].kind == "word"
                and tokens[pos].value.lower() == "and"
            ):
                pos += 1
        elif tokens[pos].kind == "word" and tokens[pos].value.lower() == "and":
            pos += 1
        else:
            raise _SentenceError(
                code="syntax_error",
                message=f"Unexpected token {tokens[pos].value!r} in export target list.",
            )
        if pos >= len(tokens):
            raise _SentenceError(
                code="syntax_error",
                message="Expected an export target after connective.",
            )
        target_id, pos = _consume_target(pos)
        if target_id in targets:
            raise _SentenceError(
                code="duplicate_pipeline_clause",
                message=f"Duplicate export target {target_id!r}.",
            )
        targets.add(target_id)

    return ExportConfigRecord(
        export_nir="export_nir" in targets,
        generate_py_download="generate_py_download" in targets,
        line=line,
    )


# ---------------------------------------------------------------------------
# NIR_CNL_Parser — public entry point
# ---------------------------------------------------------------------------


# Single-token verbs that the legacy keyword set may surface as
# identifiers; defended against by the keyword set itself. We import
# ``keyword_set`` only to keep the parser's lookup contract honest —
# the present implementation does not use it directly because every
# grammatical use-site already names the keyword explicitly.
_ = keyword_set  # noqa: F841 — kept for re-export clarity in static review.


class NIR_CNL_Parser:
    """Convert NIR-Native CNL text into intermediate IR records.

    The parser is stateless — every call to :meth:`parse` is
    independent — and its single public method returns either the
    in-source-order list of records or raises
    :class:`~neurocnl.nir_cnl.errors.ParseError` carrying every
    collected diagnostic.

    Examples
    --------
    >>> parser = NIR_CNL_Parser()
    >>> records = parser.parse(
    ...     "Define a network named demo.\\n"
    ...     "Define an input port named in1 with shape (1,)."
    ... )
    >>> records[0].name, records[0].__class__.__name__
    ('demo', 'NetworkContainer')
    """

    def parse(
        self, text: str
    ) -> list[
        NIRNodeRecord
        | NIREdgeRecord
        | NetworkContainer
        | TrainingConfigRecord
        | EvaluationConfigRecord
        | ExportConfigRecord
    ]:
        """Parse *text* into a list of IR records.

        Implements Requirements 1.13, 9.1, 9.3, and 9.4:

        * runs the legacy-token validator first (Requirement 1.8 / 8.4);
        * tokenises and splits the remainder into sentences, accumulating
          one diagnostic per failing sentence (Requirement 9.3);
        * checks each successfully parsed node sentence for a duplicate
          identifier inside the same network container, emitting a
          ``duplicate_identifier`` diagnostic and skipping the record on
          collision (Requirement 1.13);
        * caps the diagnostic list at 10 000 entries and sorts by
          ``line`` ascending with ties broken by occurrence order
          (Requirement 9.4);
        * raises :class:`ParseError` carrying every collected diagnostic
          when the list is non-empty.

        Parameters
        ----------
        text:
            CNL source text. May be empty (yields ``[]``). Comment
            lines (first non-whitespace ``#``) are ignored.

        Returns
        -------
        list of records
            Mixed list of :class:`NIRNodeRecord`,
            :class:`NIREdgeRecord`, and :class:`NetworkContainer`
            instances in source order.

        Raises
        ------
        ParseError
            If any sentence fails to parse or the legacy-token
            validator produces a diagnostic.
        """
        diagnostics: list[Diagnostic] = []

        # ── Phase 1: legacy-token gate (Requirement 1.8 / 8.4) ─────────
        diagnostics.extend(scan_for_legacy_tokens(text))

        # ── Phase 2: tokenise & sentence-split ─────────────────────────
        tokens = _tokenize(text)
        sentences = _split_sentences(tokens)

        # ── Phase 3: per-sentence parse loop ───────────────────────────
        records: list[
            NIRNodeRecord
            | NIREdgeRecord
            | NetworkContainer
            | TrainingConfigRecord
            | EvaluationConfigRecord
            | ExportConfigRecord
        ] = []
        seen_identifiers: set[str] = set()

        for sent_tokens in sentences:
            if len(diagnostics) >= _MAX_DIAGNOSTICS:
                break
            if not sent_tokens:
                continue
            try:
                rec = self._dispatch_sentence(sent_tokens, seen_identifiers)
            except _SentenceError as exc:
                diagnostics.append(diagnostic_from_sentence(exc, sent_tokens))
                continue
            if rec is not None:
                records.append(rec)

        # ── Phase 4: surface diagnostics ───────────────────────────────
        if diagnostics:
            # Stable sort by ``line`` so ties preserve occurrence order
            # (Requirement 9.3 / 9.4). Treat ``None`` as 0 for sorting.
            raise ParseError(finalize_diagnostics(diagnostics))

        return records

    # ------------------------------------------------------------------
    # Internal: per-sentence dispatch
    # ------------------------------------------------------------------

    def _dispatch_sentence(
        self,
        sent_tokens: list[Token],
        seen_identifiers: set[str],
    ) -> (
        NIRNodeRecord
        | NIREdgeRecord
        | NetworkContainer
        | TrainingConfigRecord
        | EvaluationConfigRecord
        | ExportConfigRecord
        | None
    ):
        """Dispatch one sentence to the appropriate sentence-form parser.

        Returns ``None`` when the sentence parsed cleanly but produced no
        record (e.g. a duplicate identifier on a node sentence — the
        diagnostic is appended via the calling exception).
        """
        first = sent_tokens[0]
        # Detect active-voice edge: ``<identifier> connects to <identifier>.``
        # The source can be a word, dotted, or number token kind.
        if (
            first.kind in _IDENTIFIER_TOKEN_KINDS
            and len(sent_tokens) >= 3
            and sent_tokens[1].kind == "word"
            and sent_tokens[1].value.lower() == "connects"
        ):
            return _parse_active_voice_edge_sentence(sent_tokens)
        if first.kind != "word":
            raise _SentenceError(
                code="syntax_error",
                message=(
                    f"Sentence must begin with a verb keyword, got {first.value!r}."
                ),
            )
        verb = first.value.lower()
        if verb == "connect":
            return _parse_edge_sentence(sent_tokens)
        if verb in ("define", "create"):
            # Disambiguate ``Define a network named ...`` from the more
            # general node-declaration form. The tokens after the
            # verb / article are the network keyword for the network
            # form and a noun-phrase token for the node form.
            if (
                len(sent_tokens) >= 4
                and sent_tokens[1].kind == "word"
                and sent_tokens[1].value.lower() in ("a", "an")
                and sent_tokens[2].kind == "word"
                and sent_tokens[2].value.lower() == "network"
            ):
                return _parse_network_sentence(sent_tokens)
            rec = _parse_node_sentence(sent_tokens)
            if rec.name in seen_identifiers:
                raise _SentenceError(
                    code="duplicate_identifier",
                    message=(
                        f"Duplicate node identifier {rec.name!r} within the same network container."
                    ),
                    hint=(
                        f"Identifier {rec.name!r} is already declared in this network."
                    ),
                )
            seen_identifiers.add(rec.name)
            return rec
        if verb == "train":
            return _parse_train_sentence(sent_tokens)
        if verb == "evaluate":
            return _parse_evaluate_sentence(sent_tokens)
        if verb == "export":
            return _parse_export_sentence(sent_tokens)
        raise _SentenceError(
            code="syntax_error",
            message=f"Unknown sentence verb {first.value!r}.",
            hint=(
                "Sentences must begin with 'Define', 'Create', 'Connect', "
                "'Train', 'Evaluate', or 'Export'."
            ),
        )
