FROM python:3.11-slim

WORKDIR /app

# Jupyter server
COPY workers/jupyter_server/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

# Install torch (CPU-only) first for cache stability, then all SNN frameworks.
# These layers only rebuild when you deliberately bump a version below.
RUN pip install --no-cache-dir \
    --index-url https://download.pytorch.org/whl/cpu \
    torch \
 && pip install --no-cache-dir \
    snntorch \
    rockpool \
    sinabs \
    norse

# Install neurocnl with all extras (brings nir and framework bindings).
# Heavy torch layer above is already cached so this is fast.
COPY neurocnl/ /tmp/neurocnl/
RUN pip install --no-cache-dir "/tmp/neurocnl/[training,rockpool,synsense,norse]" \
 && rm -rf /tmp/neurocnl

# Register the kernel so JupyterLab discovers it on startup.
# --sys-prefix writes to the current Python prefix — always visible to the
# jupyter server running in the same container.
RUN python -m ipykernel install --sys-prefix \
    --name neurocnl \
    --display-name "Python (NeuroStudio)"

COPY workers/jupyter_server/jupyter_server_config.py /app/jupyter_server_config.py

# Notebooks are stored in the user's home directory by default, matching
# standard JupyterLab behaviour.  Override JUPYTER_NOTEBOOK_DIR at runtime
# (e.g. via a Docker volume mount) to persist notebooks outside the container.
ENV JUPYTER_NOTEBOOK_DIR=/root

EXPOSE 8008

CMD ["sh", "-c", "jupyter server --config=/app/jupyter_server_config.py --notebook-dir=${JUPYTER_NOTEBOOK_DIR}"]
