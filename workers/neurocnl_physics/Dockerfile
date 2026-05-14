FROM python:3.11-slim
WORKDIR /app
RUN pip install --no-cache-dir fastapi uvicorn mujoco
COPY workers/neurocnl_physics/ /app/
COPY neurocnl/ /repo/neurocnl/
RUN pip install --no-cache-dir -e /repo/neurocnl
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8006"]
