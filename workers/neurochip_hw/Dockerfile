FROM python:3.11-slim
WORKDIR /app
COPY workers/neurochip_hw/ /app/
COPY Neurochip/ /repo/Neurochip/
RUN pip install --no-cache-dir -e /repo/Neurochip
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8002"]
