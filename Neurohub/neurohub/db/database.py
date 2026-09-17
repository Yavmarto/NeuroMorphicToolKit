import os
from collections.abc import Generator
from typing import Any

from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker
from sqlalchemy.pool import NullPool

SQLALCHEMY_DATABASE_URL = os.getenv("NEUROHUB_DB_URL", "sqlite:///./neurohub.db")

# check_same_thread is a SQLite-only argument; passing it to PostgreSQL (Cloud SQL)
# is harmless on some SQLAlchemy builds but causes errors on others.
_is_sqlite = SQLALCHEMY_DATABASE_URL.startswith("sqlite")
_connect_args = {"check_same_thread": False} if _is_sqlite else {}

# pool_pre_ping guards against stale connections after a pooler/idle-connection
# recycle (e.g. Supabase's pgbouncer) — safe and cheap for SQLite too.
_engine_kwargs: dict[str, Any] = {"connect_args": _connect_args, "pool_pre_ping": True}

# NEUROHUB_DB_POOL_MODE=nullpool disables SQLAlchemy's own client-side pooling.
# Set this only when NEUROHUB_DB_URL points at a Transaction-mode pgbouncer
# pooler (e.g. Supabase's port-6543 pooler) — client-side pooling on top of a
# transaction-mode server-side pooler can trigger prepared-statement/protocol
# errors. Leave unset for a Session pooler or a direct connection.
if os.getenv("NEUROHUB_DB_POOL_MODE", "").lower() == "nullpool":
    _engine_kwargs["poolclass"] = NullPool

engine = create_engine(SQLALCHEMY_DATABASE_URL, **_engine_kwargs)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


class Base(DeclarativeBase):
    """Base class for SQLAlchemy models."""

    pass


def get_db() -> Generator[Session, None, None]:
    """Provide a database session.

    Yields:
        Session: SQLAlchemy session.
    """
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
