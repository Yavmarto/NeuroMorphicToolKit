"""Tests for common schemas."""

import pytest
from pydantic import ValidationError

from backend.app.schemas.common import (
    BackendSupport,
    ErrorDetail,
    GeneratorFidelityAnnotation,
    GeneratorFidelitySummary,
    SpecRequest,
)


def test_spec_request_valid():
    """Test SpecRequest with valid data."""
    data = {"spec": "The neuron MUST fire."}
    request = SpecRequest(**data)
    assert request.spec == data["spec"]


def test_spec_request_invalid():
    """Test SpecRequest with invalid data."""
    with pytest.raises(ValidationError):
        SpecRequest()  # Missing required field


def test_error_detail_valid():
    """Test ErrorDetail with valid data."""
    data = {
        "code": "parser_error",
        "message": "Missing semicolon",
        "name": "ParserError",
        "reason": "Missing semicolon",
        "lines": [3],
    }
    error = ErrorDetail(**data)
    assert error.code == data["code"]
    assert error.message == data["message"]
    assert error.lines == [3]


def test_backend_support_valid():
    support = BackendSupport(
        backend="loihi",
        verdict="approximate",
        warnings=["Declared network_timestep differs from backend timing resolution."],
    )
    assert support.backend == "loihi"
    assert support.verdict == "approximate"
    assert len(support.warnings) == 1


def test_generator_fidelity_summary_valid():
    summary = GeneratorFidelitySummary(
        annotations=[
            GeneratorFidelityAnnotation(
                concept="homeostatic_plasticity",
                subject="sensory neuron",
                fidelity="placeholder",
                reason="Open-loop bias node.",
            )
        ]
    )
    assert summary.annotations[0].concept == "homeostatic_plasticity"


def test_error_detail_invalid():
    """Test ErrorDetail with invalid data."""
    with pytest.raises(ValidationError):
        ErrorDetail(line="three")  # type: ignore[arg-type]
