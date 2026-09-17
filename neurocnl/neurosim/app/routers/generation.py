"""Router for NIR-Native CNL ↔ canvas synchronization.

The three NIR-Native CNL endpoints (`/api/neurosim/generate-cnl-from-nir`,
`/api/neurosim/generate-cnl`, `/api/neurosim/parse-cnl`) are wired
directly through the NIR-Native CNL pipeline:

* :class:`~neurocnl.nir_cnl.NIR_Renderer` — `nir.NIRGraph` → CNL text.
* :class:`~neurocnl.nir_cnl.NIR_CNL_Parser` — CNL text → record list.
* :class:`~neurocnl.nir_cnl.NIR_Compiler` — record list → `nir.NIRGraph`.

Canvas conversion is delegated to the preserved canvas serializer at
``backend.app.services.nir_graph_serializer``; per Requirement 12 each
endpoint calls the serializer exactly once and never wraps it in a
helper that adds, removes, reorders, or transforms fields.

Size and validation contract (Requirement 7):

* ``/generate-cnl-from-nir`` — ≤ 10 MB raw `.nir` bytes; HTTP 400 on
  oversized or invalid binary; HTTP 422 with a structured diagnostics
  array when the graph contains node types outside the 18 Primitives;
  HTTP 500 if diagnostic-array construction itself fails.
* ``/generate-cnl`` — ≤ 10 MB JSON; HTTP 400 on oversized payload.
* ``/parse-cnl`` — ≤ 1 MB JSON, UTF-8 decoded; HTTP 400 on oversized
  payload or invalid UTF-8; HTTP 422 with structured diagnostics on
  any ``ParseError`` / ``CompileError``; HTTP 500 if diagnostic-array
  construction itself fails.
"""

from __future__ import annotations

import re
import tempfile
from typing import Any

from fastapi import APIRouter, HTTPException, Request, Response
from pydantic import BaseModel, ValidationError

from backend.app.services.nir_graph_serializer import (
    NirCanvasConversionError,
    deserialize_canvas_graph,
    serialize_nir_to_canvas_graph,
)
from neurocnl._nir_compat import safe_nir_read
from neurocnl.nir_cnl import (
    CompileError,
    Diagnostic,
    NIR_CNL_Parser,
    NIR_Compiler,
    NIR_Renderer,
    ParseError,
    RenderError,
)
from neurocnl.nir_cnl.grammar_tables import primitive_phrases
from neurosim.contracts.canonical_editor_contracts import (
    CanonicalEditorDocument,
    CanvasNodeMutation,
    ParseCnlRequest,
    ParseCnlResponse,
)
from neurosim.contracts.design_contracts import (
    CanvasGraph,
    CnlSyncRequest,
    CnlSyncResponse,
)

from ..limiter import rate_limit
from ..services.canonical_editor_projection import (
    apply_canvas_mutation,
    canonical_from_cnl,
    canonical_from_ir,
    canonical_to_cnl,
)
from ..services.cnl_to_graph import import_graph_from_contract

router = APIRouter(prefix="/api/neurosim", tags=["generation"])


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------


# Requirement 7.1, 7.2, 7.3 — payload caps.
_MAX_NIR_BYTES: int = 10 * 1024 * 1024  # 10 MB
_MAX_CANVAS_JSON_BYTES: int = 10 * 1024 * 1024  # 10 MB
_MAX_CNL_JSON_BYTES: int = 1 * 1024 * 1024  # 1 MB


# Pre-formatted hint string for unsupported-primitive diagnostics.
_SUPPORTED_PRIMITIVES_HINT: str = "Supported primitives: " + ", ".join(
    primitive_phrases.keys()
)


# Regex that matches the renderer's unsupported-node comment line:
#   ``# unsupported node type <PrimitiveClassName> for node <node_id>``
# Both the type name and the node identifier match ``\S+`` because the
# renderer only ever emits ``[A-Za-z_][A-Za-z0-9_]*`` node identifiers
# and class names.
_UNSUPPORTED_NODE_RE = re.compile(r"^# unsupported node type (\S+) for node (\S+)\s*$")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


async def _read_capped_body(request: Request, max_bytes: int) -> bytes:
    """Read the request body, rejecting payloads larger than *max_bytes*.

    A ``Content-Length`` header that exceeds the cap short-circuits to
    HTTP 400 without buffering the rest of the body.  The actual
    received-byte length is verified after the body is read so a missing
    or lying header still cannot bypass the cap.
    """
    cl = request.headers.get("content-length")
    if cl is not None:
        try:
            if int(cl) > max_bytes:
                raise HTTPException(
                    status_code=400,
                    detail={
                        "error": f"payload exceeds {max_bytes} bytes",
                    },
                )
        except ValueError:
            # Malformed Content-Length — fall through and let the body
            # read decide.
            pass
    body = await request.body()
    if len(body) > max_bytes:
        raise HTTPException(
            status_code=400,
            detail={"error": f"payload exceeds {max_bytes} bytes"},
        )
    return body


def _diagnostic_dict(d: Diagnostic) -> dict[str, Any]:
    """Convert a :class:`Diagnostic` to the documented JSON shape.

    Per Requirement 7.5 the API surface guarantees ``code`` (non-empty
    string), ``message`` (non-empty string), ``line`` (integer ≥ 1), and
    ``hint`` (string, possibly empty).  ``Diagnostic.line`` may be
    ``None`` for materializer- and validator-stage diagnostics; default
    to ``1`` so the API contract holds.
    """
    return {
        "code": d.code,
        "message": d.message,
        "line": d.line if d.line is not None else 1,
        "hint": d.hint or "",
    }


# ---------------------------------------------------------------------------
# Canonical-editor endpoints (preserved)
# ---------------------------------------------------------------------------


@router.post("/parse-cnl-canonical", response_model=ParseCnlResponse)
async def parse_cnl_canonical(request: ParseCnlRequest) -> ParseCnlResponse:
    """Parse CNL text into a canonical editor document with canvas projection.

    Primary live-sync endpoint. Returns the full canonical document
    (ir_json, cnl_text, fidelity_annotations, canvas projection).
    Use /parse-cnl for the legacy lossy-repair fallback only.

    Returns HTTP 422 when parsing fails or the canvas projection is empty so
    the client receives a structured error instead of a silent null canvas.
    """
    try:
        document = canonical_from_cnl(request.spec_text)
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(
            status_code=422,
            detail={"message": str(exc), "unsupported_concepts": []},
        ) from exc

    if document.canvas is None or (
        not document.canvas.nodes and request.spec_text.strip()
    ):
        raise HTTPException(
            status_code=422,
            detail={
                "message": "CNL parsed but produced an empty canvas.",
                "unsupported_concepts": [],
            },
        )

    return ParseCnlResponse(document=document, diagnostics=[])


class _GenerateCnlCanonicalRequest(BaseModel):
    document: CanonicalEditorDocument


class _GenerateCnlCanonicalResponse(BaseModel):
    cnl_text: str
    document: CanonicalEditorDocument


class _GenerateCnlFromNirResponse(BaseModel):
    cnl_text: str
    diagnostics: list[dict[str, Any]] = []


@router.post("/generate-cnl-canonical", response_model=_GenerateCnlCanonicalResponse)
async def generate_cnl_canonical(
    request: _GenerateCnlCanonicalRequest,
) -> _GenerateCnlCanonicalResponse:
    """Render CNL from a canonical editor document.

    Accepts a canonical document (ir_json), re-renders CNL with embedded
    round-trip metadata, and returns both the CNL text and the updated document.
    """
    cnl_text = canonical_to_cnl(request.document)
    updated_doc = canonical_from_cnl(cnl_text)
    return _GenerateCnlCanonicalResponse(cnl_text=cnl_text, document=updated_doc)


class _CanvasToCanonicalRequest(BaseModel):
    graph: CanvasGraph


@router.post("/canvas-to-canonical", response_model=ParseCnlResponse)
async def canvas_to_canonical(request: _CanvasToCanonicalRequest) -> ParseCnlResponse:
    """Derive a CanonicalEditorDocument from a canvas graph.

    Converts the canvas graph to NIR, imports the NetworkIR, then builds the
    canonical document with canvas projection. Returns 422 for empty graphs or
    unsupported graph structures.
    """
    if not request.graph.nodes:
        raise HTTPException(
            status_code=422,
            detail={"message": "Cannot derive canonical document from empty graph."},
        )
    try:
        from neurocnl.cnl.document import import_ir_from_nir
        from neurosim.app.services.canonical_editor_projection import canonical_from_ir

        nir_graph = deserialize_canvas_graph(request.graph)
        ir = import_ir_from_nir(nir_graph)
        document = canonical_from_ir(ir, nir_graph=nir_graph)
    except Exception as exc:
        raise HTTPException(
            status_code=422,
            detail={"message": str(exc), "unsupported_concepts": []},
        ) from exc
    return ParseCnlResponse(document=document, diagnostics=[])


class _CanvasMutationRequest(BaseModel):
    document: CanonicalEditorDocument
    mutation: CanvasNodeMutation


@router.post("/canvas-mutation", response_model=ParseCnlResponse)
async def canvas_mutation_endpoint(body: _CanvasMutationRequest) -> ParseCnlResponse:
    """Apply a typed parameter edit to a canonical editor document.

    Accepts the current canonical document and a mutation (node_id + changed
    fields), applies the change through the service layer, and returns the
    updated canonical document. Returns 422 when the node_id is unknown.
    """
    try:
        document = apply_canvas_mutation(body.document, body.mutation)
    except (ValueError, KeyError) as exc:
        raise HTTPException(
            status_code=422,
            detail={"message": str(exc), "unsupported_concepts": []},
        ) from exc
    return ParseCnlResponse(document=document, diagnostics=[])


# ---------------------------------------------------------------------------
# NIR-Native CNL endpoints (Requirement 7)
# ---------------------------------------------------------------------------


@router.post("/nir-to-canonical", response_model=ParseCnlResponse)
@rate_limit("30/minute")
async def nir_bytes_to_canonical(
    request: Request, response: Response
) -> ParseCnlResponse:
    """Translate uploaded raw ``.nir`` bytes directly into a canonical editor document.

    Unlike ``/generate-cnl-from-nir`` → ``/parse-cnl-canonical`` this endpoint
    never routes through the CNL text representation, so it works for ALL NIR
    graphs regardless of which primitives they contain.  Unsupported node types
    (anything not in the NIR-native CNL grammar) appear as placeholder canvas
    nodes — the graph is still fully displayable and editable.

    Flow:
      raw NIR bytes
        → nir.read (HDF5 → NIRGraph)
        → import_ir_from_nir (NIRGraph → NetworkIR, LIF-family only)
        → canonical_from_ir(ir, nir_graph=nir_graph)
              (builds CanvasProjection from the raw NIR graph — ALL node types)
        → ParseCnlResponse
    """
    body = await _read_capped_body(request, _MAX_NIR_BYTES)

    try:
        with tempfile.NamedTemporaryFile(suffix=".nir") as handle:
            handle.write(body)
            handle.flush()
            nir_graph = safe_nir_read(handle.name)
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(
            status_code=400,
            detail={"error": f"invalid_nir_binary: {exc}"},
        ) from exc

    try:
        from neurocnl.cnl.document import import_ir_from_nir

        ir = import_ir_from_nir(nir_graph)
        document = canonical_from_ir(ir, nir_graph=nir_graph)
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(
            status_code=422,
            detail={"error": f"nir_to_canonical_failed: {exc}"},
        ) from exc

    return ParseCnlResponse(document=document, diagnostics=[])


@router.post("/generate-cnl-from-nir", response_model=_GenerateCnlFromNirResponse)
async def generate_cnl_from_uploaded_nir(
    request: Request,
) -> _GenerateCnlFromNirResponse:
    """Translate uploaded raw ``.nir`` bytes into NIR-Native CNL text.

    Implements Requirement 7.1, 7.4, 7.6, 7.7:

    * Reads up to 10 MB of `.nir` bytes; oversized payloads return
      HTTP 400.
    * Calls :func:`nir.read` then :meth:`NIR_Renderer.render`; an invalid
      `.nir` binary returns HTTP 400.
    * If the rendered text contains any ``# unsupported node type ...``
      lines (the renderer's signal that the graph has node types outside
      the 18 Primitives), the endpoint returns HTTP 422 with one
      ``diagnostics`` entry per offending node.
    * If diagnostic-array construction itself fails, returns HTTP 500
      with a ``diagnostic_generation_failed:`` payload — never a partial
      HTTP 422.
    """
    body = await _read_capped_body(request, _MAX_NIR_BYTES)

    # ── nir.read accepts a path or a file-like; use NamedTemporaryFile
    # because some readers seek the on-disk file directly.
    try:
        with tempfile.NamedTemporaryFile(suffix=".nir") as handle:
            handle.write(body)
            handle.flush()
            graph = safe_nir_read(handle.name)
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(
            status_code=400,
            detail={"error": f"invalid_nir_binary: {exc}"},
        ) from exc

    try:
        cnl_text = NIR_Renderer().render(graph)
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(
            status_code=500,
            detail={"error": f"diagnostic_generation_failed: {exc}"},
        ) from exc

    # ── Detect 18-Primitive violations by scanning for the renderer's
    # ``# unsupported node type ...`` comment lines.  Each such line was
    # emitted in place of a node sentence per Requirement 3.6.
    try:
        offending: list[tuple[str, str]] = []
        for line in cnl_text.splitlines():
            m = _UNSUPPORTED_NODE_RE.match(line)
            if m is not None:
                offending.append((m.group(1), m.group(2)))
    except Exception as exc:  # noqa: BLE001
        # Per Requirement 7.7, never return a partial 422.
        raise HTTPException(
            status_code=500,
            detail={"error": f"diagnostic_generation_failed: {exc}"},
        ) from exc

    if offending:
        try:
            diagnostics = [
                {
                    "code": "unsupported_primitive",
                    "message": (
                        f"Unsupported NIR node type {primitive!r} (node {node_id!r})."
                    ),
                    "node_id": node_id,
                    "primitive": primitive,
                    "hint": _SUPPORTED_PRIMITIVES_HINT,
                }
                for primitive, node_id in offending
            ]
        except Exception as exc:  # noqa: BLE001
            raise HTTPException(
                status_code=500,
                detail={"error": f"diagnostic_generation_failed: {exc}"},
            ) from exc
        raise HTTPException(
            status_code=422,
            detail={
                "code": "unsupported_nir_import",
                "message": "NIR graph contains unsupported node types",
                "diagnostics": diagnostics,
            },
        )

    return _GenerateCnlFromNirResponse(cnl_text=cnl_text, diagnostics=[])


@router.post("/generate-cnl", response_model=CnlSyncResponse)
@rate_limit("60/minute")
async def generate_cnl(request: Request, response: Response) -> CnlSyncResponse:
    """Render NIR-Native CNL text from a canvas graph.

    Implements Requirement 7.2 and Requirement 12.4:

    * Reads up to 10 MB of JSON; oversized payloads return HTTP 400.
    * Decodes the JSON into :class:`CanvasGraph`; malformed JSON or
      schema violations return HTTP 400.
    * Calls :func:`deserialize_canvas_graph` exactly once (no helper
      wrapper).  Per Requirement 12.5 the call site does not catch the
      serializer's exceptions; they propagate to FastAPI's default
      error handler.
    * Calls :meth:`NIR_Renderer.render` on the resulting graph and
      returns the CNL text.
    """
    body = await _read_capped_body(request, _MAX_CANVAS_JSON_BYTES)
    try:
        graph = CanvasGraph.model_validate_json(body)
    except ValidationError as exc:
        raise HTTPException(
            status_code=400,
            detail={"error": f"invalid_canvas_graph: {exc}"},
        ) from exc

    try:
        nir_graph = deserialize_canvas_graph(graph)
    except NirCanvasConversionError as exc:
        raise HTTPException(
            status_code=422,
            detail={
                "message": str(exc),
                "unsupported_concepts": exc.unsupported_types,
            },
        ) from exc

    try:
        cnl_text = NIR_Renderer().render(nir_graph)
    except RenderError as exc:
        raise HTTPException(
            status_code=422,
            detail={
                "message": str(exc),
                "unsupported_concepts": [],
            },
        ) from exc

    return CnlSyncResponse(cnl_spec=cnl_text, graph=graph)


@router.post("/parse-cnl", response_model=CanvasGraph)
@rate_limit("60/minute")
async def parse_cnl(request: Request, response: Response) -> CanvasGraph:
    """Parse NIR-Native CNL text into a canvas graph.

    Implements Requirements 7.3, 7.5, 7.6, 7.7 and Requirement 12.3:

    * Reads up to 1 MB of JSON; oversized payloads return HTTP 400.
    * Decodes the request body as UTF-8; non-UTF-8 input returns
      HTTP 400.
    * Decodes the JSON into :class:`CnlSyncRequest`; malformed JSON or
      a missing ``cnl_spec`` returns HTTP 400.
    * Calls :meth:`NIR_CNL_Parser.parse` and :meth:`NIR_Compiler.compile`
      exactly once each; any ``ParseError`` or ``CompileError`` is
      converted to HTTP 422 with the documented diagnostics array.
    * Calls :func:`serialize_nir_to_canvas_graph` exactly once on the
      compiled graph (Requirement 12.3).
    * If diagnostic-array construction itself fails, returns HTTP 500
      with a ``diagnostic_generation_failed:`` payload — never a partial
      HTTP 422.
    """
    body = await _read_capped_body(request, _MAX_CNL_JSON_BYTES)

    # Requirement 7.6 — non-UTF-8 input returns HTTP 400.
    try:
        body.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise HTTPException(
            status_code=400,
            detail={"error": f"invalid_utf8: {exc}"},
        ) from exc

    try:
        payload = CnlSyncRequest.model_validate_json(body)
    except ValidationError as exc:
        raise HTTPException(
            status_code=400,
            detail={"error": f"invalid_request: {exc}"},
        ) from exc

    if not payload.cnl_spec:
        raise HTTPException(
            status_code=400,
            detail={"error": "cnl_spec is required"},
        )

    position_hints = None
    if payload.graph:
        position_hints = {node.id: node.position for node in payload.graph.nodes}

    if payload.import_contract is not None:
        return import_graph_from_contract(
            payload.import_contract,
            position_hints=position_hints,
        )

    try:
        records = NIR_CNL_Parser().parse(payload.cnl_spec)
        nir_graph = NIR_Compiler().compile(records)
    except (ParseError, CompileError) as exc:
        try:
            errors = exc.errors if isinstance(exc, ParseError) else exc.diagnostics
            diagnostics = [_diagnostic_dict(d) for d in errors]
        except Exception as inner:  # noqa: BLE001
            # Per Requirement 7.7 never return a partial 422 — escalate
            # to 500 when the diagnostic-generation path itself fails.
            raise HTTPException(
                status_code=500,
                detail={
                    "error": f"diagnostic_generation_failed: {inner}",
                },
            ) from inner
        raise HTTPException(
            status_code=422, detail={"diagnostics": diagnostics}
        ) from exc

    return serialize_nir_to_canvas_graph(nir_graph)
