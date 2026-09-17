"""POST /api/export — export spec as .cnl file or HTML report."""

from __future__ import annotations

import html as html_lib
import tempfile
from datetime import UTC, datetime
from pathlib import Path

from fastapi import APIRouter, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel, ConfigDict

from backend.app.schemas.common import BackendSupport
from backend.app.utils.cnl_errors import (
    build_backend_failure_detail,
    build_lowering_failure_detail,
    build_parse_failure_detail,
    build_validation_failure_detail,
)
from neurocnl.backends import BACKEND_CAPABILITIES
from neurocnl.compile import CompileError, compile_to_nir
from neurocnl.export.nir_exporter import summarize_nir_lowering
from neurocnl.ir import LoweringError, NetworkIR, lower_to_ir
from neurocnl.ir.metadata_schema import ADVISORY_SEMANTICS_VERSION
from neurocnl.pipeline import parse_spec_text
from neurocnl.planner import plan_backend_support

router = APIRouter()


class ExportPreflightRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    spec: str
    format: str = "nir"


class ExportPreflightResponse(BaseModel):
    backend_support: BackendSupport | None = None


@router.post("/export/preflight", response_model=ExportPreflightResponse)
def export_preflight(request: ExportPreflightRequest) -> ExportPreflightResponse:
    """Return the backend capability verdict without generating any artifacts."""
    parse_results = parse_spec_text(request.spec)
    if any(not r["valid"] for r in parse_results):
        return ExportPreflightResponse(
            backend_support=BackendSupport(
                backend=request.format,
                verdict="unsupported",
                warnings=[
                    "Spec contains parse errors; cannot determine backend support."
                ],
            )
        )
    parsed_specs = [r["parsed"] for r in parse_results if r["valid"]]
    if not parsed_specs:
        return ExportPreflightResponse(
            backend_support=BackendSupport(
                backend=request.format,
                verdict="unsupported",
                warnings=["No valid CNL sentences found."],
            )
        )
    if request.format not in BACKEND_CAPABILITIES:
        return ExportPreflightResponse(
            backend_support=BackendSupport(
                backend=request.format,
                verdict="unsupported",
                warnings=[
                    f"'{request.format}' is not a supported backend target for capability planning."
                ],
            )
        )
    try:
        ir_model = lower_to_ir(parsed_specs)
        planner = plan_backend_support(ir_model, request.format)
    except LoweringError as exc:
        return ExportPreflightResponse(
            backend_support=BackendSupport(
                backend=request.format,
                verdict="unsupported",
                warnings=[str(exc)],
            )
        )
    return ExportPreflightResponse(
        backend_support=BackendSupport(
            backend=planner.backend,
            verdict=planner.verdict,
            supported_concepts=planner.supported_concepts,
            approximated_concepts=planner.approximated_concepts,
            unsupported_concepts=planner.unsupported_concepts,
            warnings=planner.warnings,
        )
    )


class CnlExportRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    spec: str
    format: str = "cnl"
    filename: str = "spec.cnl"
    validation_summary: dict | None = None
    network_summary: dict | None = None
    simulation_summary: dict | None = None
    backend_support: dict | None = None
    generator_fidelity: dict | None = None


@router.post("/export")
def export_spec(request: CnlExportRequest) -> Response:
    if request.format == "cnl":
        return Response(
            content=request.spec,
            media_type="text/plain",
            headers={
                "Content-Disposition": f'attachment; filename="{request.filename}"'
            },
        )

    if request.format == "html":
        html_content = _build_html_report(request)
        return Response(
            content=html_content,
            media_type="text/html",
            headers={
                "Content-Disposition": 'attachment; filename="neurocnl_report.html"'
            },
        )

    if request.format == "akida":
        try:
            from neurocnl.generation.akida_generator import generate_script

            parse_results = parse_spec_text(request.spec)

            if any(not r["valid"] for r in parse_results):
                raise HTTPException(
                    status_code=400,
                    detail=build_parse_failure_detail(parse_results),
                )

            parsed_specs = [r["parsed"] for r in parse_results if r["valid"]]
            if not parsed_specs:
                raise HTTPException(
                    status_code=422,
                    detail=build_validation_failure_detail(
                        "No valid CNL sentences found.",
                        code="no_valid_cnl_sentences",
                    ),
                )

            ir_model = lower_to_ir(parsed_specs)

            # Since akida is pure IR->Script we don't build a nengo net to extract headers
            planner = plan_backend_support(ir_model, "akida")
            export_headers = {}
            if planner is not None:
                export_headers["X-NeuroCNL-Backend-Verdict"] = planner.verdict
                export_headers["X-NeuroCNL-Backend-Warning-Count"] = str(
                    len(planner.warnings)
                )

            exported_content = generate_script(ir_model)

            return Response(
                content=exported_content,
                media_type="text/plain",
                headers={
                    "Content-Disposition": 'attachment; filename="network.py"',
                    **export_headers,
                },
            )
        except HTTPException:
            raise
        except RuntimeError as re:
            raise HTTPException(
                status_code=400, detail=build_lowering_failure_detail(re)
            ) from re
        except Exception as e:
            raise HTTPException(
                status_code=500,
                detail=build_backend_failure_detail(
                    "export_failed", str(e), source="export"
                ),
            ) from e

    if request.format == "mlir":
        try:
            with tempfile.NamedTemporaryFile(suffix=".nir", delete=False) as tmp:
                tmp_path = tmp.name
            try:
                from neurocnl.generation.snn_mlir_generator import generate_mlir

                parse_results = parse_spec_text(request.spec)
                if any(not r["valid"] for r in parse_results):
                    raise HTTPException(
                        status_code=400,
                        detail=build_parse_failure_detail(parse_results),
                    )

                parsed_specs = [r["parsed"] for r in parse_results if r["valid"]]
                if not parsed_specs:
                    raise HTTPException(
                        status_code=422,
                        detail=build_validation_failure_detail(
                            "No valid CNL sentences found.",
                            code="no_valid_cnl_sentences",
                        ),
                    )

                compile_to_nir(request.spec, save_to=tmp_path)
                mlir_text = generate_mlir(tmp_path)

                return Response(
                    content=mlir_text,
                    media_type="text/plain",
                    headers={
                        "Content-Disposition": 'attachment; filename="network.mlir"'
                    },
                )
            finally:
                if Path(tmp_path).exists():
                    Path(tmp_path).unlink()
        except HTTPException:
            raise
        except CompileError as e:
            raise HTTPException(
                status_code=400, detail=build_lowering_failure_detail(e)
            ) from e
        except RuntimeError as re:
            raise HTTPException(
                status_code=400, detail=build_lowering_failure_detail(re)
            ) from re
        except Exception as e:
            raise HTTPException(
                status_code=500,
                detail=build_backend_failure_detail(
                    "export_failed", str(e), source="export"
                ),
            ) from e

    # Legacy Nengo-backed exporters (neuroml, c_header, loihi, lava, spinnaker, etc.) are
    # intentionally gone from the active product surface. Return 410 Gone so callers
    # receive a clear signal rather than a silent fallback or 404.
    _LEGACY_FORMATS = frozenset(
        {
            "neuroml",
            "c_header",
            "loihi",
            "lava",
            "spinnaker",
            "spinnaker2",
            "pynq",
            "pynq_artifact",
        }
    )
    if request.format in _LEGACY_FORMATS:
        raise HTTPException(
            status_code=410,
            detail=build_backend_failure_detail(
                "legacy_export_removed",
                (
                    f"Export format '{request.format}' is no longer supported on the "
                    "NIR-only NeuroCNL surface."
                ),
                source="export",
                hint=(
                    "Use format='nir' for the canonical artifact or format='cnl' to "
                    "download the round-tripable source document."
                ),
                examples=[
                    'POST /api/export {"format": "nir"}',
                    'POST /api/export {"format": "cnl"}',
                ],
            ),
        )

    if request.format == "nir":
        try:
            with tempfile.NamedTemporaryFile(suffix=".nir", delete=False) as tmp:
                tmp_path = tmp.name
            try:
                parse_results = parse_spec_text(request.spec)
                if any(not r["valid"] for r in parse_results):
                    raise HTTPException(
                        status_code=400,
                        detail=build_parse_failure_detail(parse_results),
                    )

                parsed_specs = [r["parsed"] for r in parse_results if r["valid"]]
                if not parsed_specs:
                    raise HTTPException(
                        status_code=422,
                        detail=build_validation_failure_detail(
                            "No valid CNL sentences found.",
                            code="no_valid_cnl_sentences",
                        ),
                    )

                nir_graph = compile_to_nir(request.spec, save_to=tmp_path)
                export_headers = _build_export_headers(
                    net=nir_graph,
                    parsed_specs=parsed_specs,
                    backend=request.format,
                )
                with open(tmp_path, "rb") as f:
                    nir_content = f.read()
                return Response(
                    content=nir_content,
                    media_type="application/octet-stream",
                    headers={
                        "Content-Disposition": 'attachment; filename="network.nir"',
                        **export_headers,
                    },
                )
            finally:
                if Path(tmp_path).exists():
                    Path(tmp_path).unlink()
        except HTTPException:
            raise
        except CompileError as e:
            raise HTTPException(
                status_code=400, detail=build_lowering_failure_detail(e)
            ) from e
        except Exception as e:
            raise HTTPException(
                status_code=500,
                detail=build_backend_failure_detail(
                    "export_failed", str(e), source="export"
                ),
            ) from e

    raise HTTPException(
        status_code=400,
        detail=build_backend_failure_detail(
            "unsupported_export_format",
            f"Unsupported export format: {request.format}",
            source="export",
        ),
    )


def _build_html_report(request: CnlExportRequest) -> str:
    """Generate a self-contained HTML report."""
    import neurocnl

    generated_at = datetime.now(UTC).isoformat()
    neurocnl_version = getattr(neurocnl, "__version__", "unknown")
    spec_html = html_lib.escape(request.spec)

    # Client-provided summary disclaimer
    client_provided_note = (
        '<p style="color:#f59e0b;font-size:12px;margin:0 0 16px">'
        "&#9888; Validation and network summaries below were provided by the client "
        "and have not been recomputed server-side.</p>\n"
        if (request.validation_summary or request.network_summary)
        else ""
    )

    # Validation section
    validation_html = ""
    backend_support = request.backend_support
    generator_fidelity = request.generator_fidelity
    if request.validation_summary:
        v = request.validation_summary
        backend_support = backend_support or v.get("backend_support")
        generator_fidelity = generator_fidelity or v.get("generator_fidelity")
        overall = v.get("overall", False)
        status = "PASSED" if overall else "FAILED"
        status_color = "#22c55e" if overall else "#ef4444"
        validation_html += (
            f'<h2>Validation <span style="color:{status_color}">{status}</span></h2>\n'
        )

        # Layer 1
        l1 = v.get("layer1", {})
        if l1:
            validation_html += "<h3>Layer 1: Biophysical Invariants</h3>\n<table><tr><th>Invariant</th><th>Description</th><th>Result</th></tr>\n"
            for inv in l1.get("passed", []):
                validation_html += f'<tr><td>{html_lib.escape(inv.get("name", ""))}</td><td>{html_lib.escape(inv.get("description", ""))}</td><td style="color:#22c55e">\u2713</td></tr>\n'
            for inv in l1.get("failed", []):
                validation_html += f'<tr><td>{html_lib.escape(inv.get("name", ""))}</td><td>{html_lib.escape(inv.get("description", ""))}</td><td style="color:#ef4444">\u2717</td></tr>\n'
            validation_html += "</table>\n"

        # Layer 2
        l2 = v.get("layer2", {})
        if l2:
            validation_html += "<h3>Layer 2: Cross-Reference Checks</h3>\n<ul>\n"
            for check in l2.get("checks_passed", []):
                validation_html += (
                    f'<li style="color:#22c55e">\u2713 {html_lib.escape(check)}</li>\n'
                )
            for check in l2.get("checks_failed", []):
                validation_html += (
                    f'<li style="color:#ef4444">\u2717 {html_lib.escape(check)}</li>\n'
                )
            validation_html += "</ul>\n"
            neurons = l2.get("neurons_found", [])
            if neurons:
                validation_html += f"<p><strong>Neurons found:</strong> {', '.join(html_lib.escape(n) for n in neurons)}</p>\n"

    fidelity_html = ""
    if backend_support:
        verdict = html_lib.escape(str(backend_support.get("verdict", "unknown")))
        backend_name = html_lib.escape(str(backend_support.get("backend", "unknown")))
        fidelity_html += f"<h2>Backend Support</h2>\n<p><strong>{backend_name}</strong>: {verdict}</p>\n"
        warnings = backend_support.get("warnings", [])
        if warnings:
            fidelity_html += "<ul>\n"
            for warning in warnings:
                fidelity_html += f"<li>{html_lib.escape(str(warning))}</li>\n"
            fidelity_html += "</ul>\n"

    if generator_fidelity and generator_fidelity.get("annotations"):
        fidelity_html += "<h2>Generator Fidelity</h2>\n<table><tr><th>Concept</th><th>Subject</th><th>Fidelity</th><th>Reason</th></tr>\n"
        for item in generator_fidelity.get("annotations", []):
            fidelity_html += (
                "<tr>"
                f"<td>{html_lib.escape(str(item.get('concept', '')))}</td>"
                f"<td>{html_lib.escape(str(item.get('subject', '')))}</td>"
                f"<td>{html_lib.escape(str(item.get('fidelity', '')))}</td>"
                f"<td>{html_lib.escape(str(item.get('reason', '')))}</td>"
                "</tr>\n"
            )
        fidelity_html += "</table>\n"

    # Network section
    network_html = ""
    if request.network_summary:
        net = request.network_summary
        nodes = net.get("nodes", [])
        edges = net.get("edges", [])
        network_html += "<h2>Network Topology</h2>\n"
        if nodes:
            network_html += "<h3>Nodes</h3>\n<table><tr><th>ID</th><th>Type</th><th>Label</th></tr>\n"
            for node in nodes:
                network_html += f"<tr><td>{html_lib.escape(str(node.get('id', '')))}</td><td>{html_lib.escape(str(node.get('type', '')))}</td><td>{html_lib.escape(str(node.get('label', '')))}</td></tr>\n"
            network_html += "</table>\n"
        if edges:
            network_html += "<h3>Connections</h3>\n<table><tr><th>Source</th><th>Target</th><th>Weight</th><th>Synapse</th></tr>\n"
            for edge in edges:
                params = edge.get("params", {})
                network_html += f"<tr><td>{html_lib.escape(str(edge.get('source', '')))}</td><td>{html_lib.escape(str(edge.get('target', '')))}</td><td>{html_lib.escape(str(params.get('transform', '')))}</td><td>{html_lib.escape(str(params.get('synapse', '')))}</td></tr>\n"
            network_html += "</table>\n"

    # Simulation section
    sim_html = ""
    if request.simulation_summary:
        s = request.simulation_summary
        sim_html += "<h2>Simulation Summary</h2>\n<table>\n"
        for key, label in [
            ("sensory_spike_count", "Sensory Spike Count"),
            ("motor_spike_count", "Motor Spike Count"),
            ("sensory_mean_rate", "Sensory Mean Rate (Hz)"),
            ("motor_mean_rate", "Motor Mean Rate (Hz)"),
            ("first_output_spike", "First Output Spike (s)"),
            ("input_to_output_latency", "Input-to-Output Latency (s)"),
        ]:
            val = s.get(key)
            if val is not None:
                sim_html += (
                    f"<tr><td><strong>{label}</strong></td><td>{val}</td></tr>\n"
                )
        sim_html += "</table>\n"

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>neurocnl Studio Report</title>
<style>
  body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 900px; margin: 40px auto; padding: 0 20px; background: #1a1a2e; color: #e0e0e0; }}
  h1 {{ color: #a78bfa; border-bottom: 2px solid #a78bfa; padding-bottom: 8px; }}
  h2 {{ color: #c4b5fd; margin-top: 32px; }}
  h3 {{ color: #94a3b8; }}
  pre {{ background: #16213e; padding: 16px; border-radius: 8px; overflow-x: auto; border: 1px solid #334155; font-size: 14px; line-height: 1.5; }}
  table {{ border-collapse: collapse; width: 100%; margin: 12px 0; }}
  th, td {{ text-align: left; padding: 8px 12px; border: 1px solid #334155; }}
  th {{ background: #1e293b; color: #a78bfa; }}
  tr:nth-child(even) {{ background: #1e293b; }}
  ul {{ padding-left: 20px; }}
  li {{ margin: 4px 0; }}
  .footer {{ margin-top: 48px; padding-top: 16px; border-top: 1px solid #334155; color: #64748b; font-size: 12px; }}
</style>
</head>
<body>
<h1>neurocnl Studio Report</h1>

{client_provided_note}
<h2>CNL Specification</h2>
<pre>{spec_html}</pre>

{validation_html}
{fidelity_html}
{network_html}
{sim_html}

<div class="footer">
  Generated by neurocnl Studio &mdash; neurocnl {html_lib.escape(neurocnl_version)} &mdash; {html_lib.escape(generated_at)}
</div>
</body>
</html>"""


def _build_export_headers(
    *, net: object, parsed_specs: list[dict], backend: str
) -> dict[str, str]:
    """Attach additive export metadata without changing response bodies."""
    import nir as _nir

    headers: dict[str, str] = {}
    ir_model: NetworkIR | None = net if isinstance(net, NetworkIR) else None
    nir_graph: _nir.NIRGraph | None = net if isinstance(net, _nir.NIRGraph) else None

    fidelity = getattr(net, "generator_fidelity", None)
    if fidelity and fidelity.get("annotations"):
        headers["X-NeuroCNL-Generator-Fidelity-Count"] = str(
            len(fidelity["annotations"])
        )

    # For NIR-native exports the compiled artifact is a nir.NIRGraph; there is no
    # biological-grammar NetworkIR to feed through lower_to_ir / plan_backend_support.
    # Report a faithful verdict and absent advisory semantics — the spec maps 1:1 to NIR.
    if nir_graph is not None and ir_model is None:
        headers["X-NeuroCNL-Backend-Verdict"] = "faithful"
        headers["X-NeuroCNL-Backend-Warning-Count"] = "0"
        headers["X-NeuroCNL-NIR-Advisory-Semantics"] = "absent"
        headers["X-NeuroCNL-NIR-Advisory-Semantics-Version"] = str(
            ADVISORY_SEMANTICS_VERSION
        )
        return headers

    if backend in BACKEND_CAPABILITIES:
        try:
            if ir_model is None:
                ir_model = lower_to_ir(parsed_specs)
            planner = plan_backend_support(ir_model, backend)
        except LoweringError:
            planner = None
        if planner is not None:
            headers["X-NeuroCNL-Backend-Verdict"] = planner.verdict
            headers["X-NeuroCNL-Backend-Warning-Count"] = str(len(planner.warnings))
    if backend == "nir" and ir_model is not None:
        lowering_summary = summarize_nir_lowering(ir_model)
        headers["X-NeuroCNL-NIR-Approximate-Count"] = str(
            lowering_summary.connection_summary["approximate_dense_connections"]
        )
        headers["X-NeuroCNL-NIR-Structured-One-To-One-Count"] = str(
            lowering_summary.connection_summary["structured_one_to_one"]
        )
        headers["X-NeuroCNL-NIR-Structured-Binary-Mask-Count"] = str(
            lowering_summary.connection_summary["structured_binary_mask"]
        )
        headers["X-NeuroCNL-NIR-Delay-Node-Count"] = str(
            lowering_summary.connection_summary["delay_nodes"]
        )
        headers["X-NeuroCNL-NIR-Structured-Intent-Metadata-Only-Count"] = str(
            lowering_summary.connection_summary["structured_intent_metadata_only"]
        )
        headers["X-NeuroCNL-NIR-Timing-Declaration-Count"] = str(
            lowering_summary.metadata_only_summary["timing_declarations"]
        )
        headers["X-NeuroCNL-NIR-Population-Shape-Count"] = str(
            lowering_summary.metadata_only_summary["populations_with_shape"]
        )
        headers["X-NeuroCNL-NIR-Metadata-Only-Count"] = str(
            sum(
                1
                for verdict in lowering_summary.concept_verdicts.values()
                if verdict == "lowered_as_metadata"
            )
        )
        headers["X-NeuroCNL-NIR-Advisory-Semantics"] = "present"
        headers["X-NeuroCNL-NIR-Advisory-Semantics-Version"] = str(
            ADVISORY_SEMANTICS_VERSION
        )
        headers["X-NeuroCNL-NIR-Not-Lowered-Count"] = str(
            sum(
                1
                for verdict in lowering_summary.concept_verdicts.values()
                if verdict == "not_lowered"
            )
        )

    return headers
