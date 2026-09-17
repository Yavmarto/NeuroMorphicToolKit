from typing import Literal

from pydantic import BaseModel


class ReportGenerationResult(BaseModel):
    """Contract for benchmark report generation results."""

    report_id: str
    status: Literal["pending", "completed", "failed"]
    download_url: str | None = None
    format: Literal["pdf", "html", "json"]
    timestamp: str
