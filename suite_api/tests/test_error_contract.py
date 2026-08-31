"""Public Suite API error envelope tests."""

import asyncio
import json
from types import SimpleNamespace

from fastapi import HTTPException
from fastapi.testclient import TestClient

from suite_api.main import app, http_exception_handler


def test_unknown_route_has_correlated_structured_error() -> None:
    response = TestClient(app).get(
        "/api/does-not-exist", headers={"X-Request-ID": "missing-route-1"}
    )

    assert response.status_code == 404
    assert response.json() == {
        "detail": {
            "code": "not_found",
            "message": "Not Found",
            "request_id": "missing-route-1",
            "retryable": False,
        }
    }


def _fake_request() -> SimpleNamespace:
    """Return the minimal Request surface ``http_exception_handler`` consumes."""
    return SimpleNamespace(
        state=SimpleNamespace(request_id="error-contract-test"),
        headers={"X-Request-ID": "error-contract-test"},
    )


def _run_handler(detail: object, status_code: int = 400) -> dict[str, object]:
    response = asyncio.run(
        http_exception_handler(
            _fake_request(), HTTPException(status_code=status_code, detail=detail)
        )
    )
    return json.loads(response.body.decode())


def test_dict_detail_uses_error_key_and_messages_list() -> None:
    """The ``error`` shorthand and ``messages`` list both feed the envelope."""
    body = _run_handler({"error": "bad_request", "messages": ["Field is required."]})
    assert body == {
        "detail": {
            "code": "bad_request",
            "message": "Field is required.",
            "request_id": "error-contract-test",
            "retryable": False,
        }
    }


def test_dict_detail_code_and_message_take_precedence() -> None:
    """A canonical ``code`` wins over ``error``; ``message`` wins over list."""
    body = _run_handler(
        {
            "code": "rate_limited",
            "error": "bad_request",
            "message": "Too many attempts.",
            "messages": ["Ignored."],
            "retryable": True,
        },
        status_code=429,
    )
    assert body == {
        "detail": {
            "code": "rate_limited",
            "message": "Too many attempts.",
            "request_id": "error-contract-test",
            "retryable": True,
        }
    }


def test_dict_detail_without_code_falls_back_safely() -> None:
    """A detail with only a free-form message keeps the default code."""
    body = _run_handler({"message": "Generic failure."})
    assert body == {
        "detail": {
            "code": "request_failed",
            "message": "Generic failure.",
            "request_id": "error-contract-test",
            "retryable": False,
        }
    }
