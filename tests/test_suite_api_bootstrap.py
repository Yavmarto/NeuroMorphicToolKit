from importlib.machinery import ModuleSpec

import pytest

import suite_api.bootstrap as bootstrap


def test_validate_runtime_dependencies_reports_full_missing_set() -> None:
    missing = {"pydantic_settings", "httpx", "sqlalchemy"}

    def fake_find_spec(name: str) -> ModuleSpec | None:
        if name in missing:
            return None
        return ModuleSpec(name, loader=None)

    with pytest.raises(RuntimeError) as exc_info:
        bootstrap.validate_runtime_dependencies(find_spec=fake_find_spec)

    message = str(exc_info.value)
    assert "pydantic-settings" in message
    assert "httpx" in message
    assert "sqlalchemy" in message
    assert "python -m pip install -e suite_api/" in message
