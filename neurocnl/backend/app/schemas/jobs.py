"""Pydantic models for the job system."""

from enum import StrEnum
from typing import Annotated, Any, Literal

from pydantic import BaseModel, Field


class JobStatus(StrEnum):
    queued = "queued"
    running = "running"
    complete = "complete"
    failed = "failed"


class JobBase(BaseModel):
    job_id: str
    request_id: str | None = None


class JobQueued(JobBase):
    status: Literal[JobStatus.queued] = JobStatus.queued
    result: None = None
    error: None = None


class JobRunning(JobBase):
    status: Literal[JobStatus.running] = JobStatus.running
    result: None = None
    error: None = None


class JobComplete(JobBase):
    status: Literal[JobStatus.complete] = JobStatus.complete
    result: Any
    error: None = None


class JobFailed(JobBase):
    status: Literal[JobStatus.failed] = JobStatus.failed
    result: None = None
    error: Any


JobState = Annotated[
    JobQueued | JobRunning | JobComplete | JobFailed, Field(discriminator="status")
]


class PaginatedJobsResponse(BaseModel):
    items: list[JobState]
    total: int
    page: int
    size: int
    pages: int
