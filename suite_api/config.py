"""Centralised configuration for suite_api.
All values are read from environment variables with safe defaults.
"""
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    # Suite API
    suite_api_port: int = 9000

    # Module backend URLs (used by health aggregator and proxy fallback)
    neurocnl_url: str = "http://localhost:8000"
    neurosim_url: str = "http://localhost:8001"
    neurochip_url: str = "http://localhost:8002"
    neurobench_url: str = "http://localhost:8003"
    neurosense_url: str = "http://localhost:8004"
    neurohub_url: str = "http://localhost:8005"

    # Neurohub database — default points to the Neurohub submodule's SQLite DB
    neurohub_db_url: str = "sqlite:///./Neurohub/neurohub.db"

    model_config = {"env_file": ".env", "extra": "ignore"}


settings = Settings()
