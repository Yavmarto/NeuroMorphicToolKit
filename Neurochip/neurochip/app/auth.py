import os

from fastapi import Header, HTTPException, status

# Configuration from environment variables
AUTH_ENABLED = os.getenv("NEUROCHIP_AUTH_ENABLED", "false").lower() == "true"
API_KEY = os.getenv("NEUROCHIP_API_KEY", "neurochip-secret-key")

_DEFAULT_API_KEY = "neurochip-secret-key"


def validate_startup_auth_config() -> None:
    """Abort startup when auth is enabled but the default key is still in use.

    Call this at application startup (inside the lifespan handler in main.py)
    so that ``NEUROCHIP_AUTH_ENABLED=true`` with the shipped default key never
    silently degrades to an insecure deployment.

    Raises:
        RuntimeError: When auth is enabled and the API key has not been changed
            from the default development value.
    """
    if AUTH_ENABLED and API_KEY == _DEFAULT_API_KEY:
        raise RuntimeError(
            "NEUROCHIP_AUTH_ENABLED=true but NEUROCHIP_API_KEY is still the "
            "default development key ('neurochip-secret-key'). "
            "Set a strong random key via the NEUROCHIP_API_KEY environment "
            "variable before enabling authentication."
        )


async def verify_api_key(x_api_key: str | None = Header(None)) -> str | None:
    """
    Dependency to verify the API key in the X-API-Key header.
    If AUTH_ENABLED is False, authentication is skipped.
    """
    if not AUTH_ENABLED:
        return None

    if x_api_key is None or x_api_key != API_KEY:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or missing API Key",
            headers={"WWW-Authenticate": "ApiKey"},
        )
    return x_api_key
