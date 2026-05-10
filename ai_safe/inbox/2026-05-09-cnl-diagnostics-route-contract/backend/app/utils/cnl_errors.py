"""
Shared helpers for normalizing CNL diagnostic payloads across routes.
"""

from typing import Any


def build_parse_failure_detail(parse_results: list[dict[str, Any]]) -> dict[str, Any]:
    """
    Build a structured parse failure detail from parse results.
    
    Preserves structured error_detail fields (code, message, hint, examples, line, raw, source)
    rather than flattening to plain strings.
    
    Args:
        parse_results: List of parse result dicts with 'valid' and 'error_detail' keys
        
    Returns:
        Dict with 'error' and 'items' keys, where items contains structured error details
    """
    parse_errors = [r["error_detail"] for r in parse_results if not r["valid"] and r.get("error_detail")]
    
    if not parse_errors:
        return {"error": "parse_failed", "items": []}
    
    # Preserve the full structured error details
    items = []
    for error_detail in parse_errors:
        if error_detail is not None:
            items.append(error_detail)
    
    return {"error": "parse_failed", "items": items}


def build_validation_failure_detail(validation_errors: list[dict[str, Any]]) -> dict[str, Any]:
    """
    Build a structured validation failure detail.
    
    Args:
        validation_errors: List of validation error dicts with structured fields
        
    Returns:
        Dict with 'error' and 'items' keys
    """
    return {"error": "validation_failed", "items": validation_errors}


def build_lowering_failure_detail(exc: Exception) -> dict[str, Any]:
    """
    Build a lowering failure detail.
    
    Lowering errors currently lack richer structure, so we preserve the message-based format.
    
    Args:
        exc: The lowering exception
        
    Returns:
        Dict with 'error' and 'messages' keys
    """
    return {"error": "lowering_failed", "messages": [str(exc)]}


def build_backend_failure_detail(message: str, error_type: str = "backend_error") -> dict[str, Any]:
    """
    Build a generic backend failure detail.
    
    Args:
        message: Error message
        error_type: Error category identifier
        
    Returns:
        Dict with 'error' and 'messages' keys
    """
    return {"error": error_type, "messages": [message]}
