"""Registry community endpoints: ratings, comments, and follows (``/api/v1``)."""

from __future__ import annotations

import uuid
from datetime import datetime, UTC

from fastapi import (
    APIRouter,
    BackgroundTasks,
    Depends,
    HTTPException,
    Query,
    Request,
    Response,
    status,
)
from sqlalchemy.orm import Session

from neurohub.app.limiter import limiter
from neurohub.app.registry_security import (
    RegistryUser,
    get_registry_user,
    user_or_ip_key,
)
from neurohub.app.services import activity_feed, registry_service
from neurohub.contracts.registry_contracts import (
    CommentCreate,
    CommentResponse,
    RatingCreate,
)
from neurohub.db.database import get_db
from neurohub.db.models import ArtefactDB, CommentDB, FollowDB, RatingDB

router = APIRouter(tags=["Registry Community"])


def _now_iso() -> str:
    """Return the current UTC time as an ISO 8601 string."""
    return datetime.now(UTC).isoformat()


def _resolve_artefact(db: Session, owner: str, slug: str) -> ArtefactDB:
    """Resolve ``{owner}/{slug}`` to its latest active artefact or raise 404."""
    artefact = registry_service.get_latest(db, owner, slug)
    if artefact is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="artefact not found")
    return artefact


def _recompute_rating(db: Session, artefact: ArtefactDB) -> None:
    """Recompute and persist an artefact's rating aggregate (Property 20)."""
    ratings = db.query(RatingDB).filter(RatingDB.artefact_id == artefact.id).all()
    if ratings:
        artefact.rating_count = len(ratings)
        artefact.average_rating = round(sum(r.value for r in ratings) / len(ratings), 2)
    else:
        artefact.rating_count = 0
        artefact.average_rating = 0.0
    db.commit()


@router.post("/artefacts/{owner}/{slug}/ratings", status_code=status.HTTP_200_OK)
@limiter.limit("300/minute", key_func=user_or_ip_key)
def rate_artefact(
    request: Request,
    response: Response,
    owner: str,
    slug: str,
    body: RatingCreate,
    user: RegistryUser = Depends(get_registry_user),
    db: Session = Depends(get_db),
) -> dict[str, float | int]:
    """Submit or replace the caller's 1-5 rating and return updated aggregates."""
    del response
    artefact = _resolve_artefact(db, owner, slug)
    existing = (
        db.query(RatingDB)
        .filter(RatingDB.artefact_id == artefact.id, RatingDB.user_id == user.id)
        .first()
    )
    if existing is not None:
        existing.value = body.value
    else:
        db.add(
            RatingDB(
                id=str(uuid.uuid4()),
                artefact_id=artefact.id,
                user_id=user.id,
                value=body.value,
                created_at=_now_iso(),
            )
        )
    db.commit()
    _recompute_rating(db, artefact)
    return {"average_rating": artefact.average_rating, "rating_count": artefact.rating_count}


@router.post(
    "/artefacts/{owner}/{slug}/comments",
    response_model=CommentResponse,
    status_code=status.HTTP_201_CREATED,
)
@limiter.limit("300/minute", key_func=user_or_ip_key)
def add_comment(
    request: Request,
    response: Response,
    owner: str,
    slug: str,
    body: CommentCreate,
    user: RegistryUser = Depends(get_registry_user),
    db: Session = Depends(get_db),
) -> CommentResponse:
    """Post a comment (1-4000 chars) on an artefact."""
    del response
    artefact = _resolve_artefact(db, owner, slug)
    comment = CommentDB(
        id=str(uuid.uuid4()),
        artefact_id=artefact.id,
        author_id=user.id,
        content=body.content,
        created_at=_now_iso(),
    )
    db.add(comment)
    db.commit()
    db.refresh(comment)
    return CommentResponse.model_validate(comment)


@router.get("/artefacts/{owner}/{slug}/comments", response_model=list[CommentResponse])
@limiter.limit("60/minute")
def list_comments(
    request: Request,
    response: Response,
    owner: str,
    slug: str,
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    db: Session = Depends(get_db),
) -> list[CommentResponse]:
    """Return an artefact's comments in descending ``created_at`` order."""
    del response
    artefact = _resolve_artefact(db, owner, slug)
    rows = (
        db.query(CommentDB)
        .filter(CommentDB.artefact_id == artefact.id)
        .order_by(CommentDB.created_at.desc())
        .offset((page - 1) * page_size)
        .limit(page_size)
        .all()
    )
    return [CommentResponse.model_validate(r) for r in rows]


@router.delete(
    "/artefacts/{owner}/{slug}/comments/{comment_id}",
    status_code=status.HTTP_204_NO_CONTENT,
)
@limiter.limit("300/minute", key_func=user_or_ip_key)
def delete_comment(
    request: Request,
    response: Response,
    owner: str,
    slug: str,
    comment_id: str,
    user: RegistryUser = Depends(get_registry_user),
    db: Session = Depends(get_db),
) -> None:
    """Delete a comment (author or admin only)."""
    del response
    comment = db.query(CommentDB).filter(CommentDB.id == comment_id).first()
    if comment is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="comment not found")
    if not user.is_admin and comment.author_id != user.id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="not the comment author")
    db.delete(comment)
    db.commit()


@router.post("/users/{username}/follow", status_code=status.HTTP_201_CREATED)
@limiter.limit("300/minute", key_func=user_or_ip_key)
def follow_user(
    request: Request,
    response: Response,
    username: str,
    background_tasks: BackgroundTasks,
    user: RegistryUser = Depends(get_registry_user),
    db: Session = Depends(get_db),
) -> dict[str, str]:
    """Follow a publisher (400 on self-follow, 409 on duplicate)."""
    del response
    if username == user.username:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="cannot follow self")
    existing = (
        db.query(FollowDB)
        .filter(FollowDB.follower_id == user.id, FollowDB.followed_user_id == username)
        .first()
    )
    if existing is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="already following")
    db.add(
        FollowDB(
            id=str(uuid.uuid4()),
            follower_id=user.id,
            followed_user_id=username,
            created_at=_now_iso(),
        )
    )
    db.commit()
    background_tasks.add_task(
        activity_feed.record_follow, db, follower_id=user.id, followed_user_id=username
    )
    return {"status": "following", "user": username}


@router.delete("/users/{username}/follow", status_code=status.HTTP_204_NO_CONTENT)
@limiter.limit("300/minute", key_func=user_or_ip_key)
def unfollow_user(
    request: Request,
    response: Response,
    username: str,
    user: RegistryUser = Depends(get_registry_user),
    db: Session = Depends(get_db),
) -> None:
    """Remove a follow relationship."""
    del response
    follow = (
        db.query(FollowDB)
        .filter(FollowDB.follower_id == user.id, FollowDB.followed_user_id == username)
        .first()
    )
    if follow is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="not following")
    db.delete(follow)
    db.commit()
