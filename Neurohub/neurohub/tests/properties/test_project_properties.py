"""Property tests for ProjectConfig contract."""

import pytest
from hypothesis import given, settings
from hypothesis import strategies as st
from pydantic import ValidationError

from neurohub.contracts.project_contracts import ProjectConfig

VALID_MODULES = {"neurosim", "neurochip", "neurobench", "neurosense", "neurocnl"}


@settings(max_examples=200)
@given(
    st.text(min_size=1, max_size=50).filter(lambda s: s.strip() != ""),
    st.text(min_size=1, max_size=50).filter(lambda s: s.strip() != ""),
    st.lists(
        st.sampled_from(list(VALID_MODULES)),
        min_size=0,
        max_size=len(VALID_MODULES),
        unique=True,
    ),
)
def test_valid_project_references(name: str, owner: str, module_list: list[str]) -> None:
    """Test that project with valid module IDs is accepted."""
    config = ProjectConfig(name=name, owner=owner, module_list=module_list)
    assert all(m in VALID_MODULES for m in config.module_list)


@settings(max_examples=200)
@given(
    st.text(min_size=1, max_size=50).filter(lambda s: s.strip() != ""),
    st.text(min_size=1, max_size=50).filter(lambda s: s.strip() != ""),
    st.lists(
        st.text(min_size=1, max_size=10).filter(lambda m: m not in VALID_MODULES),
        min_size=1,
        max_size=5,
    ),
)
def test_invalid_project_references_rejected(
    name: str, owner: str, invalid_modules: list[str]
) -> None:
    """Test that project with invalid module IDs is rejected."""
    try:
        ProjectConfig(name=name, owner=owner, module_list=invalid_modules)
    except ValidationError as e:
        assert "Invalid module reference" in str(e)
        return

    pytest.fail(f"Invalid module references {invalid_modules} were accepted")
