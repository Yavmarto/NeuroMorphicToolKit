"""Property tests for ExportBundle contract."""

import hashlib

import pytest
from hypothesis import given, settings
from hypothesis import strategies as st
from pydantic import ValidationError

from neurohub.contracts.bundle_contracts import BundleFormat, ExportBundle


def calculate_sha256(content: list[str]) -> str:
    """Helper to calculate SHA-256 for a list of contents."""
    # Concatenate and hash for test purposes
    data = "".join(content).encode("utf-8")
    return hashlib.sha256(data).hexdigest()


@st.composite
def export_bundle_strategy(draw: st.DrawFn) -> ExportBundle:
    """Hypothesis strategy for generating a valid ExportBundle."""
    fmt = draw(st.sampled_from(BundleFormat))
    contents = draw(
        st.lists(
            st.text(min_size=1, max_size=100).filter(
                lambda x: not x.startswith("/") and ".." not in x and x.strip() != ""
            ),
            min_size=1,
            max_size=50,
        )
    )
    checksum = calculate_sha256(contents)
    return ExportBundle(format=fmt, contents=contents, checksum=checksum)


@settings(max_examples=200)
@given(export_bundle_strategy())
def test_bundle_round_trip(bundle: ExportBundle) -> None:
    """Test serialization round-trip for ExportBundle."""
    dumped = bundle.model_dump_json()
    reloaded = ExportBundle.model_validate_json(dumped)
    # Compare model_dump instead of models directly to handle alias/population
    assert reloaded.model_dump() == bundle.model_dump()


@settings(max_examples=200)
@given(
    st.sampled_from(BundleFormat),
    st.lists(
        st.text(min_size=1, max_size=50).filter(
            lambda x: not x.startswith("/") and ".." not in x and x.strip() != ""
        ),
        min_size=1,
        max_size=20,
    ),
)
def test_bundle_checksum_consistency(fmt: BundleFormat, contents: list[str]) -> None:
    """Test that bundle checksum matches re-computed hash."""
    checksum = calculate_sha256(contents)
    bundle = ExportBundle(format=fmt, contents=contents, checksum=checksum)

    # Re-calculate hash and verify it matches the bundle checksum
    recalculated = calculate_sha256(bundle.contents)
    assert recalculated == bundle.bundle_hash


@settings(max_examples=200)
@given(
    st.sampled_from(BundleFormat),
    st.lists(
        st.text(min_size=1, max_size=50).filter(
            lambda x: not x.startswith("/") and ".." not in x and x.strip() != ""
        ),
        min_size=1,
        max_size=20,
    ),
    st.text(min_size=1, max_size=64).filter(
        lambda x: not (len(x) == 64 and all(c in "0123456789abcdefABCDEF" for c in x))
    ),
)
def test_bundle_invalid_checksum_rejected(
    fmt: BundleFormat, contents: list[str], invalid_checksum: str
) -> None:
    """Test that invalid SHA-256 checksums are rejected."""
    try:
        ExportBundle(format=fmt, contents=contents, checksum=invalid_checksum)
    except ValidationError:
        return  # Expected

    # Should not reach here if invalid_checksum is really invalid
    pytest.fail(f"Invalid checksum '{invalid_checksum}' was accepted")
