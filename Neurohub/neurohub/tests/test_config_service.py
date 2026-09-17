"""Tests for the configuration service."""

from sqlalchemy.orm import Session

from neurohub.app.schemas.config import SuiteConfig
from neurohub.app.services import config_service


def test_get_config_default(db_session: Session) -> None:
    """Test retrieving default configuration when none exists."""
    config = config_service.get_config(db_session)
    assert config.neurosim_url == "http://localhost:8000"


def test_update_config(db_session: Session) -> None:
    """Test updating the configuration."""
    new_config = SuiteConfig(neurosim_url="http://new-neurosim:8001")
    config_service.update_config(db_session, new_config)

    config = config_service.get_config(db_session)
    assert config.neurosim_url == "http://new-neurosim:8001"


def test_update_existing_config(db_session: Session) -> None:
    """Test updating an already existing configuration."""
    # First update
    config_service.update_config(db_session, SuiteConfig(neurosim_url="v1"))
    # Second update
    config_service.update_config(db_session, SuiteConfig(neurosim_url="v2"))

    config = config_service.get_config(db_session)
    assert config.neurosim_url == "v2"
