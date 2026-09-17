FROM python:3.14-slim@sha256:cad9a2c871761c413caa6fdd6441c783451e740a48aaeba60ae62a8b53525ef6

WORKDIR /app

COPY neurocnl/backend/requirements.txt requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Install the neurocnl library
COPY pyproject.toml pyproject.toml
COPY neurocnl/ neurocnl/
RUN pip install --no-cache-dir -e ".[training]"

COPY neurocnl/backend/ backend/

RUN addgroup --system app && adduser --system --ingroup app app
RUN mkdir -p /home/app/.cache && chown -R app:app /app /home/app
ENV HOME=/home/app
ENV XDG_CACHE_HOME=/home/app/.cache
USER app

EXPOSE 8000

CMD ["uvicorn", "backend.app.main:app", "--host", "0.0.0.0", "--port", "8000"]
