"""Activity feed service for registry follow / new-artefact events.

Records :class:`RegistryActivityEntryDB` entries for followers when a publisher
they follow registers a new artefact (Requirement 6.6). Intended to run inside a
FastAPI ``BackgroundTasks`` job so it does not block the triggering request.
"""

from __future__ import annotations

import logging
import uuid
from datetime import datetime, UTC

from sqlalchemy.orm import Session

from neurohub.db.models import FollowDB, RegistryActivityEntryDB

logger = logging.getLogger(__name__)


def _now_iso() -> str:
    """Return the current UTC time as an ISO 8601 string."""
    return datetime.now(UTC).isoformat()


def record_follow(db: Session, *, follower_id: str, followed_user_id: str) -> None:
    """Record a follow event in the activity feed.

    Args:
        db: The database session.
        follower_id: The user who initiated the follow.
        followed_user_id: The publisher being followed.
    """
    entry = RegistryActivityEntryDB(
        id=str(uuid.uuid4()),
        follower_id=follower_id,
        followed_user_id=followed_user_id,
        artefact_id="",
        event_type="follow",
        created_at=_now_iso(),
    )
    db.add(entry)
    db.commit()


def record_new_artefact(db: Session, *, owner: str, artefact_id: str) -> None:
    """Fan out a new-artefact event to every follower of the publisher.

    Args:
        db: The database session.
        owner: The publisher who registered the artefact.
        artefact_id: The new artefact's id.
    """
    followers = db.query(FollowDB).filter(FollowDB.followed_user_id == owner).all()
    now = _now_iso()
    for follow in followers:
        db.add(
            RegistryActivityEntryDB(
                id=str(uuid.uuid4()),
                follower_id=follow.follower_id,
                followed_user_id=owner,
                artefact_id=artefact_id,
                event_type="new_artefact",
                created_at=now,
            )
        )
    db.commit()
    logger.info("Recorded new_artefact activity for %d followers of %s", len(followers), owner)
