"""snn-mlir compiler worker — lowers a .nir graph to bare-metal C via snn-opt.

Pipeline: .nir -> snn_mlir.to_mlir() -> snn-opt (lower to linalg/arith,
verifies the dialect IR) -> codegen.emit_c_artifacts() -> optional gcc build.

Default port: 8007. Start with:
    uvicorn workers.snn_mlir_compiler.main:app --port 8007

Isolated from suite_api because it depends on a from-source LLVM/MLIR build
(see workers/snn_mlir_compiler/Dockerfile) — a heavy dependency the common
dev loop should never have to pay for.
"""

import base64
import logging
import os
import subprocess
import tempfile
from pathlib import Path
from typing import Any

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

from workers.snn_mlir_compiler.codegen import emit_c_artifacts

logger = logging.getLogger("snn_mlir_compiler_worker")

SNN_OPT_PATH = os.environ.get("NMTK_SNN_OPT_PATH", "/usr/local/bin/snn-opt")

app = FastAPI(
    title="SNN-MLIR Compiler Worker",
    version="0.1.0",
    description="Lowers .nir graphs to bare-metal C via snn-opt. Feedforward, fully-connected networks only.",
)


@app.get("/health")
async def health() -> dict[str, Any]:
    snn_opt_ok = Path(SNN_OPT_PATH).exists()
    try:
        import snn_mlir  # noqa: F401

        snn_mlir_ok = True
    except ImportError:
        snn_mlir_ok = False

    return {
        "status": "ok" if (snn_opt_ok and snn_mlir_ok) else "degraded",
        "service": "snn-mlir-compiler-worker",
        "snn_opt_available": snn_opt_ok,
        "snn_mlir_available": snn_mlir_ok,
    }


class CompileRequest(BaseModel):
    nir_content_b64: str
    quantize: bool = False
    n_steps: int = 100
    index_bits: int = 64
    compile_binary: bool = False


class CompileResponse(BaseModel):
    mlir_text: str
    lowered_mlir_text: str
    main_c: str
    snn_data_h: str
    binary_b64: str | None = None


@app.post("/compile", response_model=CompileResponse)
async def compile_nir(request: CompileRequest) -> CompileResponse:
    import snn_mlir

    with tempfile.TemporaryDirectory() as tmp_dir:
        tmp_path = Path(tmp_dir)
        nir_path = tmp_path / "network.nir"
        nir_path.write_bytes(base64.b64decode(request.nir_content_b64))

        try:
            mlir_text = snn_mlir.to_mlir(str(nir_path), quantize=request.quantize)
        except Exception as exc:
            raise HTTPException(
                status_code=400, detail=f"snn-mlir failed to lower NIR graph: {exc}"
            ) from exc

        mlir_path = tmp_path / "network.mlir"
        mlir_path.write_text(mlir_text)

        lowered_path = tmp_path / "lowered.mlir"
        proc = subprocess.run(
            [SNN_OPT_PATH, str(mlir_path), "-o", str(lowered_path)],
            capture_output=True,
            text=True,
            timeout=60,
        )
        if proc.returncode != 0:
            raise HTTPException(
                status_code=400,
                detail=f"snn-opt lowering failed: {proc.stderr.strip()}",
            )
        lowered_mlir_text = lowered_path.read_text()

        layers = snn_mlir.parse_graph(str(nir_path))
        if request.quantize:
            snn_mlir.quantize_layers(layers)
        artifacts = emit_c_artifacts(
            layers, n_steps=request.n_steps, index_bits=request.index_bits
        )

        binary_b64 = None
        if request.compile_binary:
            binary_b64 = _compile_c_to_binary(tmp_path, artifacts, layers)

        return CompileResponse(
            mlir_text=mlir_text,
            lowered_mlir_text=lowered_mlir_text,
            main_c=artifacts.main_c,
            snn_data_h=artifacts.snn_data_h,
            binary_b64=binary_b64,
        )


def _compile_c_to_binary(tmp_path: Path, artifacts: Any, layers: list[object]) -> str:
    (tmp_path / "snn_data.h").write_text(artifacts.snn_data_h)
    (tmp_path / "main.c").write_text(artifacts.main_c)
    input_size = getattr(layers[0], "size", 0) if layers else 0
    (tmp_path / "input.h").write_text(
        f"static const float SNN_INPUT[{input_size}] = {{0}};\n"
    )

    binary_path = tmp_path / "network_bin"
    proc = subprocess.run(
        ["gcc", "-O2", str(tmp_path / "main.c"), "-I", str(tmp_path), "-o", str(binary_path)],
        capture_output=True,
        text=True,
        timeout=60,
    )
    if proc.returncode != 0:
        raise HTTPException(
            status_code=400, detail=f"gcc compilation failed: {proc.stderr.strip()}"
        )
    return base64.b64encode(binary_path.read_bytes()).decode("ascii")
