"""POST /api/generate — compile a NIR graph and return its topology."""

from fastapi import APIRouter, HTTPException

from backend.app.schemas.generate import (
    GenerateRequest,
    GenerateResponse,
    NetworkEdge,
    NetworkGraph,
    NetworkNode,
    NodePosition,
)
from backend.app.services.neurocnl_bridge import _NIR_ALL_CONCEPTS, parse_spec
from backend.app.services.nir_code_exporter import export_nir_code
from backend.app.services.nir_graph_serializer import serialize_nir_graph
from backend.app.utils.cnl_errors import (
    build_lowering_failure_detail,
    build_parse_failure_detail,
    build_validation_failure_detail,
)
from neurocnl.compile import CompileError, compile_to_nir
from neurocnl.pipeline import generate_cnl_from_nir

router = APIRouter()


@router.post("/generate", response_model=GenerateResponse)
def generate_network(request: GenerateRequest) -> GenerateResponse:
    parse_results = parse_spec(request.spec)

    if any(not r["valid"] for r in parse_results):
        raise HTTPException(
            status_code=400, detail=build_parse_failure_detail(parse_results)
        )

    parsed_specs = [
        r["parsed"] for r in parse_results if r["valid"] and r["parsed"] is not None
    ]
    if not parsed_specs:
        raise HTTPException(
            status_code=422,
            detail=build_validation_failure_detail(
                "No valid CNL sentences found.",
                code="no_valid_cnl_sentences",
            ),
        )

    # All CNL entering the generate endpoint must be NIR-native.  Biological-
    # grammar specs are rejected at the parse stage (MUST/MUST NOT are illegal).
    # Route directly to compile_to_nir which owns the NIR-native compile stack.
    is_nir = any(p["concept"] in _NIR_ALL_CONCEPTS for p in parsed_specs)
    if not is_nir:
        raise HTTPException(
            status_code=422,
            detail=build_validation_failure_detail(
                "Spec contains no recognisable NIR-native CNL sentences.",
                code="no_nir_sentences",
            ),
        )

    try:
        graph = compile_to_nir(request.spec)
    except CompileError as exc:
        raise HTTPException(
            status_code=422, detail=build_lowering_failure_detail(exc)
        ) from exc

    graph_dict = serialize_nir_graph(graph)

    nodes = [
        NetworkNode(
            id=n["id"],
            type=n["type"],
            label=n["label"],
            params=n.get("params", {}),
            position=NodePosition(**n["position"]) if n.get("position") else None,
        )
        for n in graph_dict["nodes"]
    ]
    edges = [
        NetworkEdge(
            id=e["id"],
            source=e["source"],
            target=e["target"],
            params=e.get("params", {}),
        )
        for e in graph_dict["edges"]
    ]

    nir_code = export_nir_code(graph)
    cnl_document = generate_cnl_from_nir(graph)

    return GenerateResponse(
        network=NetworkGraph(nodes=nodes, edges=edges),
        cnl_document=cnl_document,
        nir_code=nir_code,
    )
