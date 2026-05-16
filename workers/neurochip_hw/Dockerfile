FROM python:3.11-slim
WORKDIR /app

# Pre-install Neurochip base deps before copying source — cache survives
# all source edits; only re-runs when you bump versions here.
RUN pip install --no-cache-dir \
    "fastapi[standard]>=0.111" \
    "uvicorn[standard]>=0.29" \
    "pydantic>=2" \
    "python-multipart>=0.0.22" \
    "jinja2>=3.1" \
    "pyserial>=3.5" \
    "slowapi>=0.1.9"

COPY workers/neurochip_hw/ /app/
COPY Neurochip/ /repo/Neurochip/
RUN pip install --no-cache-dir /repo/Neurochip
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8002"]
