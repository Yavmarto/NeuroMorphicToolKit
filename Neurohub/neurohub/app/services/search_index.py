"""Full-text search and indexing for registry artefacts.

Uses MeiliSearch when ``SEARCH_INDEX_URL`` is configured and reachable, and falls
back to a SQLAlchemy/Python query on ``slug`` + ``description`` otherwise. The
fallback applies every requested filter so results are always filter-consistent
(Property 15); the ``search_degraded`` flag is set only when a configured
MeiliSearch index was expected but is unreachable (Requirement 4.7).
"""

from __future__ import annotations

import logging
import os
from typing import Any

from sqlalchemy import func
from sqlalchemy.orm import Session

from neurohub.app.utils.uri_parser import ArtefactType, NeurohubURI, build_uri
from neurohub.contracts.registry_contracts import ArtefactListItem, SearchResponse
from neurohub.db.models import ArtefactDB

logger = logging.getLogger(__name__)

INDEX_NAME = "registry_artefacts"


def artefact_uri(artefact: ArtefactDB) -> str:
    """Build the canonical ``neurohub://`` URI for an artefact row."""
    return build_uri(
        NeurohubURI(
            scheme="neurohub",
            type=ArtefactType(artefact.type),
            owner=artefact.owner,
            slug=artefact.slug,
            version=artefact.version,
        )
    )


def _to_list_item(artefact: ArtefactDB) -> ArtefactListItem:
    """Project an artefact row into a card-grid list item."""
    return ArtefactListItem(
        type=ArtefactType(artefact.type),
        owner=artefact.owner,
        slug=artefact.slug,
        version=artefact.version,
        description=artefact.description,
        average_rating=artefact.average_rating,
        rating_count=artefact.rating_count,
        download_count=artefact.download_count,
        neurohub_uri=artefact_uri(artefact),
    )


def _model_card_value(artefact: ArtefactDB, *keys: str) -> list[str]:
    """Extract a list-valued field from an artefact's model card, if present."""
    card = artefact.model_card or {}
    for key in keys:
        value = card.get(key)
        if isinstance(value, list):
            return [str(v).lower() for v in value]
        if isinstance(value, str):
            return [value.lower()]
    return []


class SearchIndexService:
    """Indexes artefacts in MeiliSearch and answers search queries."""

    def __init__(self) -> None:
        """Initialise from ``SEARCH_INDEX_URL`` / ``SEARCH_INDEX_KEY`` env vars."""
        self._url = os.environ.get("SEARCH_INDEX_URL")
        self._key = os.environ.get("SEARCH_INDEX_KEY")
        self._client: Any | None = None

    @property
    def configured(self) -> bool:
        """Whether a MeiliSearch endpoint is configured."""
        return bool(self._url)

    def _index(self) -> Any:
        """Return the MeiliSearch index handle, raising on connection failure."""
        if self._url is None:
            raise RuntimeError("MeiliSearch is not configured")
        if self._client is None:
            import meilisearch

            self._client = meilisearch.Client(self._url, self._key)
        client = self._client
        client.health()
        index = client.index(INDEX_NAME)
        return index

    def search(
        self,
        db: Session,
        *,
        q: str | None = None,
        type_: str | None = None,
        owner: str | None = None,
        tags: list[str] | None = None,
        hardware_target: str | None = None,
        neuron_model: str | None = None,
        page: int = 1,
        page_size: int = 20,
    ) -> SearchResponse:
        """Search active artefacts, applying all filters consistently.

        Args:
            db: The database session.
            q: Free-text query matched against slug and description.
            type_: Exact (case-insensitive) artefact type filter.
            owner: Exact (case-insensitive) owner filter.
            tags: OR-semantics tag filter (match any).
            hardware_target: Match against the model card's hardware targets.
            neuron_model: Match against the model card's neuron model.
            page: 1-based page number.
            page_size: Page size (1-100).

        Returns:
            A :class:`SearchResponse` with the page of results and total count.
        """
        degraded = self.configured and not self._index_reachable()

        query = db.query(ArtefactDB).filter(ArtefactDB.deleted_at.is_(None))
        if type_:
            query = query.filter(func.lower(ArtefactDB.type) == type_.lower())
        if owner:
            query = query.filter(func.lower(ArtefactDB.owner) == owner.lower())
        if q:
            like = f"%{q.lower()}%"
            query = query.filter(
                func.lower(ArtefactDB.slug).like(like)
                | func.lower(func.coalesce(ArtefactDB.description, "")).like(like)
            )

        candidates = query.order_by(ArtefactDB.created_at.desc()).all()

        # Filters that depend on JSON columns are applied in Python for correctness.
        wanted_tags = {t.lower() for t in tags} if tags else None
        matched: list[ArtefactDB] = []
        for artefact in candidates:
            if wanted_tags is not None:
                row_tags = {str(t).lower() for t in (artefact.tags or [])}
                if wanted_tags.isdisjoint(row_tags):
                    continue
            if hardware_target:
                hw = _model_card_value(artefact, "hardware_targets", "hardware_target")
                if hardware_target.lower() not in hw:
                    continue
            if neuron_model:
                nm = _model_card_value(artefact, "neuron_model", "neuron_models")
                if neuron_model.lower() not in nm:
                    continue
            matched.append(artefact)

        total = len(matched)
        start = (page - 1) * page_size
        page_rows = matched[start : start + page_size]
        next_cursor = str(page + 1) if start + page_size < total else None

        return SearchResponse(
            items=[_to_list_item(a) for a in page_rows],
            total=total,
            page=page,
            page_size=page_size,
            next_cursor=next_cursor,
            search_degraded=degraded,
        )

    def _index_reachable(self) -> bool:
        """Return whether the configured MeiliSearch index responds to health."""
        try:
            self._index()
            return True
        except Exception:  # noqa: BLE001
            return False


_search: SearchIndexService | None = None


def get_search_index() -> SearchIndexService:
    """Return the process-wide :class:`SearchIndexService` singleton."""
    global _search
    if _search is None:
        _search = SearchIndexService()
    return _search
