"""Service for managing suite-wide configurations."""

from sqlalchemy.orm import Session

from neurohub.app.schemas.config import SuiteConfig
from neurohub.db.models import SuiteConfigDB


def get_config(db: Session) -> SuiteConfig:
    """Get the suite configuration, creating defaults if none exists.

    Args:
        db: SQLAlchemy database session.

    Returns:
        The current suite configuration.
    """
    db_config = db.query(SuiteConfigDB).first()
    if db_config:
        return SuiteConfig(
            neurosim_url=db_config.neurosim_url,
            neurochip_url=db_config.neurochip_url,
            neurobench_url=db_config.neurobench_url,
            neurosense_url=db_config.neurosense_url,
            neurocnl_url=db_config.neurocnl_url,
            shared_storage_path=db_config.shared_storage_path,
            default_project_settings=db_config.default_project_settings or {},
        )
    return SuiteConfig()


def update_config(db: Session, config: SuiteConfig) -> SuiteConfig:
    """Update the suite configuration (upsert).

    Args:
        db: SQLAlchemy database session.
        config: The new suite configuration to apply.

    Returns:
        The updated suite configuration.
    """
    db_config = db.query(SuiteConfigDB).first()
    if db_config:
        db_config.neurosim_url = config.neurosim_url
        db_config.neurochip_url = config.neurochip_url
        db_config.neurobench_url = config.neurobench_url
        db_config.neurosense_url = config.neurosense_url
        db_config.neurocnl_url = config.neurocnl_url
        db_config.shared_storage_path = config.shared_storage_path
        db_config.default_project_settings = config.default_project_settings
    else:
        db_config = SuiteConfigDB(
            neurosim_url=config.neurosim_url,
            neurochip_url=config.neurochip_url,
            neurobench_url=config.neurobench_url,
            neurosense_url=config.neurosense_url,
            neurocnl_url=config.neurocnl_url,
            shared_storage_path=config.shared_storage_path,
            default_project_settings=config.default_project_settings,
        )
        db.add(db_config)
    db.commit()
    db.refresh(db_config)
    return config
