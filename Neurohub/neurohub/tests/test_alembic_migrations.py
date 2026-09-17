"""Tests to ensure the integrity and idempotency of Alembic migrations."""

import os
from pathlib import Path

import pytest
from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, inspect

from neurohub.db.models import Base

ALEMBIC_INI_PATH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(__file__))), "alembic.ini"
)
MIGRATIONS_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "db", "migrations")

# Test DB URL
TEST_DB_PATH = "test_alembic_migrations.db"
TEST_DB_URL = f"sqlite:///{TEST_DB_PATH}"


@pytest.fixture(scope="module")
def alembic_config() -> Config:
    """Fixture to provide Alembic configuration pointed at a test database."""
    config = Config(ALEMBIC_INI_PATH)
    config.set_main_option("script_location", MIGRATIONS_DIR)
    os.environ["NEUROHUB_DB_URL"] = TEST_DB_URL

    # Ensure any previous db is cleaned up
    if Path(TEST_DB_PATH).exists():
        Path(TEST_DB_PATH).unlink()

    yield config

    # Clean up after all tests in this module run
    if Path(TEST_DB_PATH).exists():
        Path(TEST_DB_PATH).unlink()


def get_tables(db_url: str) -> set[str]:
    """Helper to get a set of table names in the current database."""
    engine = create_engine(db_url)
    inspector = inspect(engine)
    return set(inspector.get_table_names())


def test_migration_up_down_cycle_and_idempotency(alembic_config: Config) -> None:
    """Validate Alembic migrations can run up, down, and are idempotent."""
    # Step 1: Upgrade to head (from clean state)
    command.upgrade(alembic_config, "head")

    tables_after_upgrade = get_tables(TEST_DB_URL)
    # Exclude alembic_version table from our check against models
    tables_after_upgrade.discard("alembic_version")

    # Ensure all models are present as tables
    expected_tables = set(Base.metadata.tables.keys())
    assert (
        tables_after_upgrade == expected_tables
    ), f"Tables mismatch. Found: {tables_after_upgrade}"

    # Step 2: Idempotency of upgrade
    # Running upgrade head again should not throw an error
    command.upgrade(alembic_config, "head")

    # Step 3: Downgrade to base
    command.downgrade(alembic_config, "base")

    tables_after_downgrade = get_tables(TEST_DB_URL)
    # Depending on DB dialect, alembic_version might still exist, or be empty.
    # But all other tables should be dropped.
    tables_after_downgrade.discard("alembic_version")
    assert not tables_after_downgrade, f"Expected clean DB, but found: {tables_after_downgrade}"

    # Step 4: Idempotency of downgrade
    command.downgrade(alembic_config, "base")

    # Step 5: Upgrade back to head to prepare for other possible checks
    command.upgrade(alembic_config, "head")
