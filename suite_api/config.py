"""Centralised configuration for suite_api.
All values are read from environment variables with safe defaults.
"""
import os

from pydantic_settings import BaseSettings

_data_dir = os.environ.get("NEUROCNL_DATA_DIR", ".")


class Settings(BaseSettings):
    # Suite API
    suite_api_port: int = 9000

    # Module backend URLs (used by health aggregator and proxy fallback)
    neurocnl_url: str = "http://localhost:8000"
    neurosim_url: str = "http://localhost:8000"
    neurochip_url: str = "http://localhost:8002"
    neurobench_url: str = "http://localhost:8003"
    neurosense_url: str = "http://localhost:8004"
    neurohub_url: str = "http://localhost:8005"

    # Neurohub database — writable path resolved from NEUROCNL_DATA_DIR (Docker)
    # or cwd (local dev)
    neurohub_db_url: str = f"sqlite:///{_data_dir}/neurohub.db"

    # Phase 4: optional worker URLs (started only with the matching Docker profile)
    neurosense_hw_worker_url: str = "http://localhost:8004"   # profile: hardware
    neurobench_runner_url: str = "http://localhost:8003"       # profile: jobs
    neurochip_hw_worker_url: str = "http://localhost:8002"    # profile: hardware
    # API key sent to the Akida hardware worker as X-API-Key. Required when
    # pointing at the native neurochip.service (NEUROCHIP_AUTH_ENABLED=true
    # there); left empty for the unauthenticated Docker stub worker.
    neurochip_hw_worker_api_key: str = ""
    neurocnl_physics_worker_url: str = "http://localhost:8006" # profile: physics
    jupyter_worker_url: str = "http://localhost:8008"          # internal URL suite_api uses to probe Jupyter
    # Public URL returned to the Flutter app so its WebView can load JupyterLab.
    # In Docker deployments this must point to the host-accessible address
    # (e.g. http://my-server:8008/lab).  Override via JUPYTER_PUBLIC_URL env var.
    jupyter_public_url: str = "http://localhost:8008/lab"

    model_config = {"env_file": ".env", "extra": "ignore"}


settings = Settings()
