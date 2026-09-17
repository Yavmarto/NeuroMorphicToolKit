"""SQLAlchemy engine, session, and ORM model for deployment-log persistence."""

import os
from collections.abc import Generator
from contextlib import contextmanager

from sqlalchemy import Integer, String, create_engine
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column, sessionmaker
from sqlalchemy.pool import NullPool

DB_PATH = os.environ.get(
    "NEUROCHIP_DEPLOYMENT_DB",
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "deployments.db"),
)


class Base(DeclarativeBase):
    """Base class for deployment-log SQLAlchemy models."""


class DeploymentDB(Base):
    """ORM model backing the ``deployments`` table."""

    __tablename__ = "deployments"

    id: Mapped[str] = mapped_column(String, primary_key=True)
    timestamp: Mapped[str] = mapped_column(String, nullable=False)
    network_spec_hash: Mapped[str] = mapped_column(String, nullable=False)
    target_id: Mapped[str] = mapped_column(String, nullable=False)
    quantization_bits: Mapped[int] = mapped_column(Integer, nullable=False)
    firmware_version: Mapped[str] = mapped_column(String, nullable=False)
    serial_port: Mapped[str | None] = mapped_column(String, nullable=True)
    device_id: Mapped[str | None] = mapped_column(String, nullable=True)
    notes: Mapped[str | None] = mapped_column(String, nullable=True)


# NullPool: the original raw-sqlite3 implementation opened and closed a
# fresh connection per call. Tests delete ``DB_PATH`` directly on disk
# between cases (see ``test_deployment_store.py``'s ``cleanup_db``
# fixture); a pooled connection checked out before that delete would keep
# writing to the now-unlinked file's inode instead of the file the next
# test expects to find. NullPool preserves the "always open fresh" behavior.
_engine = create_engine(
    f"sqlite:///{os.path.abspath(DB_PATH)}",
    connect_args={"check_same_thread": False},
    poolclass=NullPool,
)
_SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=_engine)


@contextmanager
def session_scope() -> Generator[Session, None, None]:
    """Yield a session, ensuring the ``deployments`` table exists first."""
    os.makedirs(os.path.dirname(os.path.abspath(DB_PATH)), exist_ok=True)
    Base.metadata.create_all(_engine)
    session = _SessionLocal()
    try:
        yield session
    finally:
        session.close()
