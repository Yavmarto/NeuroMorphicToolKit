# snn-mlir compiler worker — lowers SNN-MLIR dialect IR to bare-metal C via
# `snn-opt` (github.com/INTERA-GROUP/snn-mlir), then compiles the emitted
# main.c/snn_data.h with a native C toolchain.
#
# LLVM/MLIR comes from apt.llvm.org's prebuilt packages, matching exactly
# what snn-mlir's own CI does (.github/workflows/ci.yml: `llvm.sh 22` +
# `libmlir-22-dev`) -- NOT a from-source LLVM build. A previous version of
# this Dockerfile built LLVM 19.1.7 from source (~40 min) and then failed at
# the final configure step every time, because snn-mlir's CMakeLists.txt
# requires `find_package(MLIR 22.1 REQUIRED)` -- confirmed true on every
# tagged release (v0.1.0 through v0.2.0), not just `main`. Prebuilt packages
# fix both the version mismatch and the build time.

# ── Stage 1: install LLVM/MLIR 22 + build snn-opt ─────────────────────────────
FROM ubuntu:24.04 AS llvm-builder

ARG SNN_MLIR_REF=main

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake ninja-build git python3 python3-pip ca-certificates \
    wget gnupg lsb-release software-properties-common \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
RUN wget -qO llvm.sh https://apt.llvm.org/llvm.sh \
 && chmod +x llvm.sh \
 && ./llvm.sh 22 \
 && apt-get install -y --no-install-recommends \
    libmlir-22-dev mlir-22-tools llvm-22-tools \
 && rm -rf /var/lib/apt/lists/* llvm.sh

# Some LLVM 22 nightly packages briefly shipped ArrayRef.h with a stray
# trailing quote on this return statement. Keep the guard idempotent: remove
# the bad byte if present, but never mutate a valid header into invalid C++.
RUN sed -i '272s/"$//' /usr/lib/llvm-22/include/llvm/ADT/ArrayRef.h

# snn-opt — the dialect-lowering CLI (not shipped in the `snn-mlir` pip package)
RUN git clone --depth 1 --branch ${SNN_MLIR_REF} https://github.com/INTERA-GROUP/snn-mlir.git
ENV MLIR_DIR=/usr/lib/llvm-22/lib/cmake/mlir
RUN cd snn-mlir && sed -i 's/ninja -j"$NPROC"/ninja -j4/' scripts/build_snn_dialect.sh && bash scripts/build_snn_dialect.sh

# ── Stage 2: runtime ───────────────────────────────────────────────────────────
FROM python:3.12-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir \
    "fastapi>=0.109.0" \
    "uvicorn[standard]>=0.27.0" \
    "pydantic>=2.5.0" \
    "snn-mlir"

COPY --from=llvm-builder /build/snn-mlir/build/bin/snn-opt /usr/local/bin/snn-opt

WORKDIR /repo
COPY workers/snn_mlir_compiler/ workers/snn_mlir_compiler/
ENV NMTK_SNN_OPT_PATH=/usr/local/bin/snn-opt

CMD ["uvicorn", "workers.snn_mlir_compiler.main:app", "--host", "0.0.0.0", "--port", "8007"]
