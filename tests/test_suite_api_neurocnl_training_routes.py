"""Source-level coverage for suite_api neurocnl training mounts."""

from pathlib import Path


def test_suite_api_neurocnl_router_mounts_training_router() -> None:
    router_source = Path("suite_api/domains/neurocnl/router.py").read_text()

    assert "training," in router_source
    assert "training.router," in router_source
