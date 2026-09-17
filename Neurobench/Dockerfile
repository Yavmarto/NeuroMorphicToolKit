FROM python:3.14-slim

ENV PYTHONUNBUFFERED=1

WORKDIR /app

# Pre-install CPU-only PyTorch so neurocnl and neurobench dependencies
# do not pull multi-gigabyte NVIDIA CUDA runtime packages.
RUN pip install --no-cache-dir \
    --index-url https://download.pytorch.org/whl/cpu \
    torch \
 && pip install --no-cache-dir \
    "nir>=1.0.5" \
    snntorch \
    "sc-neurocore>=3.13.0,<4"

COPY nmtk_contracts/ /nmtk_contracts/
RUN pip install --no-cache-dir /nmtk_contracts

COPY neurocnl/ /neurocnl/
RUN pip install --no-cache-dir --no-deps /neurocnl

COPY Neurobench/neurobench/ /app/neurobench/
RUN pip install --no-cache-dir /app/neurobench

# Run as a non-root user for container security
RUN groupadd --system appgroup && useradd --system --gid appgroup appuser
RUN chown -R appuser:appgroup /app
USER appuser

EXPOSE 8000

CMD ["uvicorn", "neurobench.app.main:app", "--host", "0.0.0.0", "--port", "8000"]
