import csv
import io
from typing import Literal

from fastapi import APIRouter, HTTPException, Query, Request, Response

from app.schemas.comparison import EncodingComparisonResult, TargetComparisonResult
from app.schemas.results import DiffResult
from app.services.diff_engine import diff_engine
from app.services.encoding_comparator import encoding_comparator
from app.services.result_store import result_store
from app.services.target_comparator import target_comparator

router = APIRouter()


def _diff_metrics_to_csv(diff: DiffResult) -> str:
    """Serialize diff metrics to CSV without importing optional dataframe deps."""
    rows: list[dict[str, object]] = []
    fieldnames: list[str] = []

    for metric in diff.metrics:
        row = metric.model_dump()
        baseline_ci = row.pop("baseline_ci", None)
        current_ci = row.pop("current_ci", None)
        if baseline_ci:
            row["baseline_ci_low"], row["baseline_ci_high"] = baseline_ci
        if current_ci:
            row["current_ci_low"], row["current_ci_high"] = current_ci
        for key in row:
            if key not in fieldnames:
                fieldnames.append(key)
        rows.append(row)

    stream = io.StringIO()
    if not fieldnames:
        stream.write("\n")
        return stream.getvalue()

    writer = csv.DictWriter(stream, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(rows)
    return stream.getvalue()


@router.get("/{baseline_ids}/{current_ids}", response_model=DiffResult)
def compare_results(
    request: Request,
    response: Response,
    baseline_ids: str,
    current_ids: str,
) -> DiffResult:
    """Compare baseline result(s) with current result(s).

    Args:
        request (Request): The incoming request.
        response (Response): The outgoing response.
        baseline_ids (str): Comma-separated baseline result IDs.
        current_ids (str): Comma-separated current result IDs.

    Returns:
        DiffResult: The computed difference.
    """
    # Slowapi requires 'request' and 'response' arguments by name in the signature.
    _ = (request, response)
    b_id_list = baseline_ids.split(",")
    c_id_list = current_ids.split(",")

    baselines = []
    for b_id in b_id_list:
        res = result_store.get_result(b_id) or next(
            (b for b in result_store.get_all_baselines() if b.id == b_id), None
        )
        if not res:
            raise HTTPException(status_code=404, detail=f"Baseline result '{b_id}' not found")
        baselines.append(res)

    currents = []
    for c_id in c_id_list:
        res = result_store.get_result(c_id)
        if not res:
            raise HTTPException(status_code=404, detail=f"Current result '{c_id}' not found")
        currents.append(res)

    return diff_engine.compute_diff(
        baseline=baselines[0] if len(baselines) == 1 else baselines,
        current=currents[0] if len(currents) == 1 else currents,
    )


@router.get("/export", response_class=Response)
def export_diff(
    request: Request,
    response: Response,
    baseline_ids: str = Query(..., description="Comma-separated baseline IDs"),
    current_ids: str = Query(..., description="Comma-separated current IDs"),
    format: Literal["csv", "json"] = Query("csv", description="Export format"),
) -> Response:
    """Export the difference between results.

    Args:
        request (Request): The incoming request.
        response (Response): The outgoing response.
        baseline_ids (str): Comma-separated baseline IDs.
        current_ids (str): Comma-separated current IDs.
        format (Literal["csv", "json"]): The export format.

    Returns:
        Response: The exported file.
    """
    # Use request/response when calling compare_results which needs them for slowapi.
    import sys

    print("DEBUG export_diff request type:", type(request), file=sys.stderr)
    print("DEBUG export_diff response type:", type(response), file=sys.stderr)
    try:
        diff = compare_results(request, response, baseline_ids, current_ids)
    except Exception as e:
        print("DEBUG exception type:", type(e), file=sys.stderr)
        raise

    if format == "json":
        return Response(
            content=diff.model_dump_json(indent=2),
            media_type="application/json",
            headers={"Content-Disposition": "attachment; filename=diff_export.json"},
        )

    return Response(
        content=_diff_metrics_to_csv(diff),
        media_type="text/csv",
        headers={"Content-Disposition": "attachment; filename=diff_export.csv"},
    )


@router.post("/targets", response_model=TargetComparisonResult)
def compare_targets(
    cnl_spec_path: str = Query(..., description="Path to the .cnl specification file"),
) -> TargetComparisonResult:
    """Run cross-target comparison.

    Args:
        cnl_spec_path (str): Path to the .cnl network specification file.

    Returns:
        TargetComparisonResult: The results of the cross-target comparison.
    """
    return target_comparator.compare_targets(cnl_spec_path=cnl_spec_path)


@router.post("/encoding", response_model=EncodingComparisonResult)
def compare_encoding() -> EncodingComparisonResult:
    """Run encoding strategy comparison.

    Returns:
        EncodingComparisonResult: The results of the encoding strategy comparison.
    """
    return encoding_comparator.compare_encoding()
