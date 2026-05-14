FROM python:3.11-slim
WORKDIR /app
COPY workers/neurosense_hw/ /app/
COPY Neurosense/ /repo/Neurosense/
RUN pip install --no-cache-dir -e /repo/Neurosense
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8004"]
