FROM python:3.11-slim

WORKDIR /app

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

# Full NeuroStudio kernel environment: Jupyter stack + scientific stack + all
# neuromorphic/SNN frameworks. Single source of truth shared with standalone
# mode (see requirements.txt header).
COPY workers/jupyter_server/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

# Install neurocnl with all extras (brings nir and framework bindings).
# Heavy torch/framework layers above are already cached so this is fast.
COPY neurocnl/ /tmp/neurocnl/
RUN pip install --no-cache-dir "/tmp/neurocnl/[training,rockpool,synsense,norse]" \
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
# their kernelspecs live under /root (the persisted notebooks volume).
COPY workers/jupyter_server/nmtk_env_manager/ /tmp/nmtk_env_manager/
RUN pip install --no-cache-dir /tmp/nmtk_env_manager \
 && rm -rf /tmp/nmtk_env_manager

# NMTK notebook client — thin wrappers for lava-backend and suite_api.
COPY workers/jupyter_server/nmtk_client/ /tmp/nmtk_client/
RUN pip install --no-cache-dir /tmp/nmtk_client \
 && rm -rf /tmp/nmtk_client

# Starter notebooks — seeded into the persistent /root volume by entrypoint.sh
# only when the file does not already exist (preserves user edits on restart).
COPY workers/jupyter_server/notebooks/ /app/notebooks/

COPY workers/jupyter_server/entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# Pin the Jupyter data dir under the persisted /root volume so the --user
# kernelspecs written by cloned environments survive container restarts.
ENV JUPYTER_DATA_DIR=/root/.local/share/jupyter

COPY workers/jupyter_server/jupyter_server_config.py /app/jupyter_server_config.py

# Notebooks are stored in the user's home directory by default, matching
# standard JupyterLab behaviour.  Override JUPYTER_NOTEBOOK_DIR at runtime
# (e.g. via a Docker volume mount) to persist notebooks outside the container.
ENV JUPYTER_NOTEBOOK_DIR=/root

EXPOSE 8008

CMD ["/app/entrypoint.sh"]
