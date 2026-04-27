FROM python:3.11-slim
WORKDIR /app
COPY pyproject.toml .
RUN pip install --no-cache-dir fastapi uvicorn pydantic pydantic-settings
COPY . .
RUN pip install --no-cache-dir -e /repo/Neurobench/neurobench
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8003"]
