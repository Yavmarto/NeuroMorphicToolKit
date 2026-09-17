from pydantic import BaseModel, Field

from neurohub.app.schemas.activity import ActivityEntry


class DashboardProjectSummary(BaseModel):
    """Project summary shown on the dashboard."""

    id: str
    name: str
    description: str | None = None
    updated_at: str
    owner: str
    tags: list[str] = Field(default_factory=list)
    links: dict[str, str] = Field(default_factory=dict)


class DashboardResponse(BaseModel):
    """Aggregated dashboard payload."""

    projects: list[DashboardProjectSummary] = Field(default_factory=list)
    recent_activity: list[ActivityEntry] = Field(default_factory=list)


class CollectedActivityResponse(BaseModel):
    """Activity collection summary."""

    collected: int
