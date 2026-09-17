"""POST /api/parse — parse a CNL spec into structured sentences."""

from fastapi import APIRouter

from backend.app.schemas.common import ErrorDetail
from backend.app.schemas.parse import (
    ParsedSpec,
    ParseRequest,
    ParseResponse,
    ParseSentence,
)
from backend.app.services.neurocnl_bridge import parse_spec

router = APIRouter()


@router.post("/parse", response_model=ParseResponse)
def parse_cnl(request: ParseRequest) -> ParseResponse:
    results = parse_spec(request.spec)
    sentences = []
    for r in results:
        parsed = None
        if r["parsed"] is not None:
            p = r["parsed"]
            parsed = ParsedSpec(
                concept=p["concept"],
                subject=p["subject"],
                action=p["action"],
                verb=p["verb"],
                negated=p["negated"],
                condition=p.get("condition"),
                shape=p.get("shape"),
                connectivity_pattern=p.get("connectivity_pattern"),
                connectivity_mask=p.get("connectivity_mask"),
                locality_radius=p.get("locality_radius"),
                connection_density=p.get("connection_density"),
            )
        raw_error_detail = r.get("error_detail")
        sentences.append(
            ParseSentence(
                line=r["line"],
                raw=r["raw"],
                parsed=parsed,
                valid=r["valid"],
                error=r["error"],
                error_detail=(
                    ErrorDetail(**raw_error_detail) if raw_error_detail else None
                ),
            )
        )
    return ParseResponse(
        sentences=sentences,
        total=len(sentences),
        errors=sum(1 for s in sentences if not s.valid),
    )
