FROM python:3.12-slim@sha256:3d5ed973e45820f5ba5e46bd065bd88b3a504ff0724d85980dcd05eab361fcf4

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
