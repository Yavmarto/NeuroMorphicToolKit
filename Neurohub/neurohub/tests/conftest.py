"""Shared test fixtures and configuration for NeuroHub tests."""

import atexit
import os
import tempfile
from collections.abc import Generator

import pytest
from fastapi.testclient import TestClient
from neurohub.app.auth import User, get_current_user as get_current_user_auth
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker

# NEUROHUB_SECRET_KEY must be set before importing anything that pulls in
# neurohub.app.services.auth_service, which reads it at module import time.
os.environ.setdefault("NEUROHUB_SECRET_KEY", "test-only-not-a-secret-key-00000000")
from neurohub.app.main import app  # noqa: E402
import neurohub.db.database  # noqa: E402
from neurohub.app.services.auth_service import get_current_active_user  # noqa: E402
from neurohub.db import models  # noqa: E402, F401
from neurohub.db.database import Base, get_db  # noqa: E402
from neurohub.db.models import UserDB  # noqa: E402

_temp_db = tempfile.NamedTemporaryFile(delete=False, suffix=".db")
TEST_SQLALCHEMY_DATABASE_URL = f"sqlite:///{_temp_db.name}"


def _cleanup_temp_db():
    try:
        import os

        os.unlink(_temp_db.name)
    except OSError:
        pass


atexit.register(_cleanup_temp_db)


@pytest.fixture(scope="session", autouse=True)
def setup_test_database() -> Generator[None, None, None]:
    """Fixture to initialize the test database."""
    # We create a singleton engine for the entire session
    # StaticPool ensures all connections from this engine use the same in-memory DB
    engine = create_engine(
        TEST_SQLALCHEMY_DATABASE_URL,
        connect_args={"check_same_thread": False, "timeout": 15},
    )

    # Patch the global database module's engine and sessionmaker
    # This is critical for the background worker and routers
    neurohub.db.database.engine = engine
    neurohub.db.database.SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

    # Ensure tables are created before any tests run
    Base.metadata.create_all(bind=engine)

    yield

    engine.dispose()


@pytest.fixture
def db_session() -> Generator[Session, None, None]:
    """Fixture to provide a database session with automatic rollback."""
    engine = neurohub.db.database.engine
    TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    connection = engine.connect()
    # Use a transaction for rollback-based isolation in unit tests
    transaction = connection.begin()
    session = TestingSessionLocal(bind=connection)

    yield session

    session.close()
    transaction.rollback()
    connection.close()


@pytest.fixture
def client(db_session: Session) -> Generator[TestClient, None, None]:
    """Fixture to provide a FastAPI TestClient with database override."""

    def override_get_db() -> Generator[Session, None, None]:
        # We MUST yield the session from the fixture to participate in the rollback transaction
        try:
            yield db_session
        finally:
            pass

    # Create a dummy user for authentication bypass in tests
    test_user_db = UserDB(
        id="admin",
        username="admin",
        email="test@example.com",
        full_name="Test User",
        hashed_password="hashed_password",
        is_active=True,
        is_admin=True,
    )
    db_session.add(test_user_db)
    db_session.commit()

    def override_get_current_user() -> User:
        return User(user_id="testuser", role="admin")

    # Default overrides for unit tests
    # ONLY apply if not already in overrides (allows test-specific overrides like test_auth.py)
    # Actually, the TestClient context manager is where we should do this
    # if we want the overrides to be easily replaceable.
    # But conftest is loaded first.

    app.dependency_overrides[get_db] = override_get_db
    app.dependency_overrides[get_current_user_auth] = override_get_current_user
    app.dependency_overrides[get_current_active_user] = override_get_current_user

    with TestClient(app) as c:
        yield c

    # Do NOT clear overrides if we want test-specific ones to stay?
    # No, each test should start fresh.
    app.dependency_overrides.clear()
