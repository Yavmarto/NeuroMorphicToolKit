"""Pydantic schemas for activity tracking in NeuroHub."""

from pydantic import BaseModel


class ActivityEntry(BaseModel):
    """Schema for an activity entry from a suite app."""

    id: str
    timestamp: str
    user: str
    app: str  # "neurosim", "neurochip", etc.
    project_id: str | None = None
    action: str  # e.g., "modified_network", "deployed_firmware", "ran_benchmark"
    description: str  # Human-readable: "Alice modified prosthetic_reflex in NeuroSim"
    link: str | None = None  # Deep link to the relevant view in the app
