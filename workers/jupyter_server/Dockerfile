FROM python:3.11-slim

WORKDIR /app

ENV PIP_DEFAULT_TIMEOUT=300
ENV PIP_RETRIES=5
# Build tooling for any framework that ships only an sdist (no prebuilt wheel)
# on python:3.11-slim. Kept in one layer and cleaned up to limit image size.
RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential git \
 && rm -rf /var/lib/apt/lists/*

# Install CPU-only torch FIRST, from PyTorch's CPU wheel index, so every
# torch-dependent package in requirements.txt below binds to this CPU build
# instead of pulling the default (CUDA) wheel from PyPI. Unpinned so a rebuild
# tracks the latest CPU release; this layer only rebuilds when the base image
# changes, keeping the heavy download cached.
RUN pip install --no-cache-dir \
    --index-url https://download.pytorch.org/whl/cpu \
    torch

# NIR + sc-neurocore before neurocnl source copy — cache-stable, matches suite_api.
RUN pip install --no-cache-dir "nir>=1.0.5" "sc-neurocore>=3.13.0,<4"

# Full NeuroStudio kernel environment: Jupyter stack + scientific stack + all
# neuromorphic/SNN frameworks. Single source of truth shared with standalone
# mode (see requirements.txt header).
COPY workers/jupyter_server/requirements.txt /app/requirements.txt

# requirements.txt installs in two phases inside ONE RUN. DO NOT collapse this
# into a plain `pip install -r requirements.txt`, and do NOT split it back
# into independent `pip install -r <group>.txt` calls per group — both were
# tried and both broke in different ways; see below.
#
# Phase 1 — resolve + build every wheel ONCE, jointly, for the whole file:
#   `pip wheel -r requirements.txt -w /wheels` runs a single dependency
#   resolution across every package in the file — the same resolution a
#   plain `pip install -r requirements.txt` (and the standalone launcher's
#   install path) would compute — and writes the resulting wheels to
#   /wheels. This step mirrors the part of a plain install that has always
#   worked: resolution and wheel builds. Joint resolution matters because
#   packages in this file have real cross-package version constraints that
#   only surface when pip can see the WHOLE file at once — e.g. tonic
#   requires numpy<2.0. An earlier version of this fix split the INSTALL
#   into independent per-group `pip install -r <group>.txt` calls (jupyter
#   stack, sci stack, DL stack, ...); each call resolved its own group blind
#   to the others, so the scientific-stack group installed numpy
#   unconstrained (landing on the newest release, 2.4.6) before the
#   SNN-frameworks group ever asked for numpy<2.0 for tonic. That produced an
#   unsatisfiable conflict against the already-installed newer numpy, which
#   sent pip's resolver backtracking through a decade of matplotlib releases
#   looking for any combination that worked, and it hard-failed once it
#   reached pre-2020 matplotlib sdists that don't build under Python 3.11
#   (their setup.py calls `platform.linux_distribution`, removed from the
#   stdlib in Python 3.8+). Resolving once, up front, avoids this class of
#   bug entirely — by the time Phase 2 runs, every version is already fixed.
#   Only `torch` is excluded from this joint resolve: it's already installed
#   above (line 18-20) from PyTorch's CPU-only wheel index, and `pip wheel`
#   — unlike `pip install` — does not skip already-satisfied requirements, so
#   leaving it in would re-fetch torch's full CUDA build from PyPI's default
#   index, undoing the point of installing it from the CPU-only index first.
#   Phase 2 still installs torch from its unfiltered requirements.txt line,
#   where it resolves as already-satisfied against the environment. nir and
#   sc-neurocore (also pre-installed at line 23) are deliberately NOT
#   excluded here, even though they're already installed: nir has no
#   equivalent "wrong index" problem, and this file's own nir>=1.0.5 line is
#   the ONLY thing that forces pip to notice a real conflict — sinabs (every
#   3.x release on PyPI) hard-requires nir<=1.0.4, incompatible with this
#   project's nir>=1.0.5 (needed for `nir.CubaLI`, asserted later in this
#   Dockerfile). Excluding nir here previously hid that conflict from Phase
#   1, so pip happily installed nir>=1.0.5, then sinabs in a later batch
#   silently downgraded it to satisfy its own cap, then the nir batch failed
#   outright when it found only the downgraded 1.0.4 wheel available. Keeping
#   nir in Phase 1 lets pip's resolver do what a plain joint
#   `pip install -r requirements.txt` already does: back sinabs itself down
#   to 2.0.0 (its last release with an unconstrained nir dependency) so both
#   constraints hold at once.
#
# Phase 2 — install from the local wheelhouse in batches:
#   Each `pip install --no-index --find-links=/wheels -r <group>.txt` call
#   only installs a subset, so no single invocation has to unpack the ENTIRE
#   resolved set (torch + tensorflow + jax + numba/llvmlite + scikit-learn,
#   ...) at once — that all-at-once unpack was the ORIGINAL `docker build`
#   segfault (exit 139): peak memory during pip's "Installing collected
#   packages" step spiked far enough to trigger an OOM that surfaced as a
#   SIGSEGV inside a C extension's allocator instead of a clean Python
#   MemoryError. `--no-index --find-links=/wheels` restricts every batch to
#   the wheelhouse built in Phase 1, so batching here cannot reintroduce the
#   Phase-1 conflict — there is only one version of each package available
#   to install, decided once, up front. Each `grep` pulls the real,
#   unmodified specifier line straight out of requirements.txt — only the
#   bare package NAME is duplicated here for grouping, never the version
#   constraint, so requirements.txt (shared with the standalone launcher's
#   pip install path — see its own header comment) stays the single source
#   of truth for versions. If you add/remove a package from a section in
#   requirements.txt, update the matching pattern below. Group order no
#   longer affects correctness (Phase 1 already fixed every version) — it's
#   kept smallest-first purely so build logs read top-to-bottom sensibly.
#
# /wheels and the /tmp/reqs-*.txt group files are deleted at the end of this
# SAME RUN (not a later one) so they never get committed to their own image
# layer.
RUN grep -vE '^torch($|[<>=; ])' /app/requirements.txt > /tmp/reqs-joint.txt \
 && pip install --no-cache-dir --dry-run --report /tmp/report.json -r /tmp/reqs-joint.txt \
 && python -c "import json; data=json.load(open('/tmp/report.json')); print('\n'.join(f\"{p['metadata']['name']}=={p['metadata']['version']}\" for p in data.get('install', [])))" > /tmp/resolved.txt \
 && grep -E '^(jupyterlab|jupyter_server|ipykernel)' /app/requirements.txt > /tmp/reqs-01-jupyter.txt \
 && pip install --no-cache-dir -c /tmp/resolved.txt -r /tmp/reqs-01-jupyter.txt \
 && grep -E '^(numpy|pandas|matplotlib|seaborn|tqdm)' /app/requirements.txt > /tmp/reqs-02-scientific.txt \
 && pip install --no-cache-dir -c /tmp/resolved.txt -r /tmp/reqs-02-scientific.txt \
 && grep -E '^(torch|pytorch-lightning|jax)' /app/requirements.txt > /tmp/reqs-03-dl.txt \
 && pip install --no-cache-dir -c /tmp/resolved.txt -r /tmp/reqs-03-dl.txt \
 && grep -E '^(snntorch|norse|rockpool|sinabs|spyx|nengo|tonic)' /app/requirements.txt > /tmp/reqs-04-snn.txt \
 && pip install --no-cache-dir -c /tmp/resolved.txt -r /tmp/reqs-04-snn.txt \
 && grep -E '^(nir|nirtorch|sc-neurocore)' /app/requirements.txt > /tmp/reqs-05-nir.txt \
 && pip install --no-cache-dir -c /tmp/resolved.txt -r /tmp/reqs-05-nir.txt \
 && grep -E '^(brian2|PyNN|akida|cnn2snn|lava-nc)' /app/requirements.txt > /tmp/reqs-06-frameworks.txt \
 && pip install --no-cache-dir -c /tmp/resolved.txt -r /tmp/reqs-06-frameworks.txt \
 && pip check \
 && rm -rf /tmp/report.json /tmp/resolved.txt /tmp/reqs-*.txt

# Install neurocnl with all extras (brings nir and framework bindings).
# Heavy torch/framework layers above are already cached so this is fast.
COPY neurocnl/ /tmp/neurocnl/
RUN pip install --no-cache-dir "/tmp/neurocnl[training,rockpool,synsense,norse]" \
 && python -c "import nir; assert hasattr(nir, 'CubaLI'), 'nir>=1.0.4 required'; from neurocnl.runtime.sc_neurocore_simulator import sc_neurocore_nir_bridge_available; assert sc_neurocore_nir_bridge_available(), 'sc-neurocore NIR bridge missing'; import os; os._exit(0)" \
 && rm -rf /tmp/neurocnl

# Register the kernel so JupyterLab discovers it on startup.
# --sys-prefix writes to the current Python prefix — always visible to the
# jupyter server running in the same container.
RUN python -m ipykernel install --sys-prefix \
    --name neurocnl \
    --display-name "Python (NeuroStudio)"

# NMTK environment manager — a Jupyter Server extension that clones this
# immutable base kernel into customisable per-user environments. Installed into
# the base env so it runs in-process with the server. User environments and
# their kernelspecs live under /home/appuser (the persisted notebooks volume).
COPY workers/jupyter_server/nmtk_env_manager/ /tmp/nmtk_env_manager/
RUN pip install --no-cache-dir --no-build-isolation /tmp/nmtk_env_manager \
 && rm -rf /tmp/nmtk_env_manager

# NMTK notebook client — thin wrappers for lava-backend and suite_api.
COPY workers/jupyter_server/nmtk_client/ /tmp/nmtk_client/
RUN pip install --no-cache-dir /tmp/nmtk_client \
 && rm -rf /tmp/nmtk_client

# Starter notebooks — seeded into the persistent /home/appuser volume by entrypoint.sh
# only when the file does not already exist (preserves user edits on restart).
COPY workers/jupyter_server/notebooks/ /app/notebooks/

COPY workers/jupyter_server/entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# Pin the Jupyter data dir under the persisted /home/appuser volume so the --user
# kernelspecs written by cloned environments survive container restarts.
ENV JUPYTER_DATA_DIR=/home/appuser/.local/share/jupyter

COPY workers/jupyter_server/jupyter_server_config.py /app/jupyter_server_config.py

# Notebooks are stored in the user's home directory by default, matching
# standard JupyterLab behaviour.  Override JUPYTER_NOTEBOOK_DIR at runtime
# (e.g. via a Docker volume mount) to persist notebooks outside the container.
ENV JUPYTER_NOTEBOOK_DIR=/home/appuser

# UID/GID pinned, not `useradd --system`. Two reasons, both already load-bearing:
#   1. /home/appuser is a PERSISTED named volume (jupyter_notebooks). Docker only
#      seeds a named volume from the image when the volume is empty, so the chown
#      below never reaches an existing one — if a rebuild moved appuser to a
#      different UID, every file in the volume would become unwritable and the
#      server would crash-loop on its own runtime dir. `--system` allocates
#      dynamically from the 100-999 range, so any change to the apt/pip package
#      set above can silently shift it.
#   2. nmtk/launcher_control/deployment_k8s_renderer.py hardcodes
#      runAsUser/runAsGroup/fsGroup: 1000 for every rendered Deployment. A system
#      UID could never match that, so on Kubernetes the container would run as a
#      user with no write access to its own home.
RUN groupadd --gid 1000 appgroup \
 && useradd -m --uid 1000 --gid appgroup appuser \
 && chown -R appuser:appgroup /app /home/appuser
USER appuser

EXPOSE 8008

CMD ["/app/entrypoint.sh"]
