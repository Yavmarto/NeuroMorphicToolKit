from pydantic import Field
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """Configuration settings for the NeuroBench application."""

    auth_enabled: bool = Field(default=False, alias="NB_AUTH_ENABLED")
    api_key: str = Field(default="neurobench-secret-key", alias="NB_API_KEY")

    # Hardware target endpoints
    neurosim_api_url: str = Field(
        default="http://neurocnl-backend:8000/api/neurosim/preview",
        alias="NEUROSIM_API_URL",
    )
    neurochip_api_url: str = Field(
        default="http://neurochip-backend:8002/execute", alias="NEUROCHIP_API_URL"
    )
    hardware_timeout_seconds: float = Field(default=30.0, alias="NB_HARDWARE_TIMEOUT")
    snn_mlir_compiler_url: str = Field(
        default="http://snn-mlir-compiler:8007",
        alias="SNN_MLIR_COMPILER_WORKER_URL",
    )

    model_config = {
        "env_file": ".env",
        "env_file_encoding": "utf-8",
        "extra": "ignore",  # allow suite-level env vars without validation errors
    }


settings = Settings()
