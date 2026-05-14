FROM python:3.11-slim
WORKDIR /app
COPY workers/neurobench_runner/ /app/
COPY Neurobench/neurobench/ /repo/Neurobench/neurobench/
RUN pip install --no-cache-dir -e /repo/Neurobench/neurobench
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8003"]
