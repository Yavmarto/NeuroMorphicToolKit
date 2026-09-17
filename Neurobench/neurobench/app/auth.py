from fastapi import HTTPException, Security, status
from fastapi.security.api_key import APIKeyHeader

from app.config import settings

api_key_header = APIKeyHeader(name="X-API-Key", auto_error=False)


async def get_api_key(
    api_key_from_header: str = Security(api_key_header),
) -> str | None:
    """Validate the API key from the request header.

    Args:
        api_key_from_header (str): The API key from the X-API-Key header.

    Returns:
        str | None: The validated API key, or None if authentication is disabled.

    Raises:
        HTTPException: If the API key is invalid or missing when auth is enabled.
    """
    if not settings.auth_enabled:
        return None

    if api_key_from_header == settings.api_key:
        return api_key_from_header

    raise HTTPException(
        status_code=status.HTTP_403_FORBIDDEN,
        detail="Could not validate credentials",
    )
