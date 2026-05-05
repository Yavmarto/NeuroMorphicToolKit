FROM python:3.11-slim
WORKDIR /app
# Install core deps
COPY pyproject.toml .
RUN pip install --no-cache-dir fastapi uvicorn
# Copy worker code
COPY . .
# Install neurosense package from repo root (mounted via compose volume)
RUN pip install --no-cache-dir -e /repo/Neurosense
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8004"]
