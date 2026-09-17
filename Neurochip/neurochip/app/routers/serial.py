import dataclasses

from fastapi import APIRouter, File, Form, HTTPException, Request, Response, UploadFile
from pydantic import BaseModel

from ..schemas.runtime import FlashJobResponse, FlashVerificationReport, PortInfo
from ..services import flash_service

router = APIRouter(prefix="/api/neurochip/serial", tags=["serial"])


class SerialVerifyRequest(BaseModel):
    """Request body for the post-flash runtime verification endpoint."""

    port: str
    """Serial port to connect to (e.g. ``"/dev/ttyACM0"``)."""
    run_demo: bool = True
    """Send 5 grip commands and count sensor frame responses."""
    run_hitl: bool = False
    """Run a short HITL latency benchmark."""
    hitl_samples: int = 10
    """Number of HITL round-trips (only used when ``run_hitl=True``)."""
    timeout_s: float = 5.0
    """Per-frame receive timeout in seconds."""


@router.get("/ports", response_model=list[PortInfo])
def list_ports(request: Request, response: Response) -> list[PortInfo]:
    return [PortInfo(**port) for port in flash_service.list_serial_ports()]


@router.post("/flash", response_model=FlashJobResponse)
async def flash(
    request: Request, response: Response, file: UploadFile = File(...), port: str = Form(...)
) -> FlashJobResponse:
    firmware_zip_bytes = await file.read()
    job = flash_service.start_flash_job(firmware_zip_bytes, port)
    return FlashJobResponse(
        job_id=job.id,
        status=job.status,
        progress_pct=job.progress_pct,
        message=job.message,
    )


@router.get("/flash/{job_id}", response_model=FlashJobResponse)
def poll_flash(request: Request, response: Response, job_id: str) -> FlashJobResponse:
    job = flash_service.get_flash_job(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="Flash job not found")
    return FlashJobResponse(
        job_id=job.id,
        status=job.status,
        progress_pct=job.progress_pct,
        message=job.message,
        error=job.error,
        verification_report=(
            FlashVerificationReport(**job.verification_report)
            if isinstance(job.verification_report, dict)
            else job.verification_report
        ),
    )


@router.post("/flash/{job_id}/verify", response_model=FlashVerificationReport)
async def verify_flash(
    request: Request, response: Response, job_id: str, req: SerialVerifyRequest
) -> FlashVerificationReport:
    """Run optional Neuro-Dream-Hand runtime verification after a successful flash.

    Returns 404 if the job does not exist, 409 if it has not yet reached
    ``DONE`` status, and 503 if ``neurodreamhand`` is not installed.
    On success the structured :class:`~neurodreamhand.toolkit_handoff.VerificationReport`
    is returned as JSON and stored on the job for later poll.
    """
    job = flash_service.get_flash_job(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="Flash job not found")
    if job.status != flash_service.FlashStatus.DONE:
        raise HTTPException(status_code=409, detail="Flash job not yet complete")

    try:
        from neurodreamhand.toolkit_handoff import (  # type: ignore[import-untyped]
            VerificationOptions,
            verify_post_flash_runtime,
        )
    except ImportError:
        raise HTTPException(
            status_code=503,
            detail=("neurodreamhand is not installed. Install it with: pip install neurodreamhand"),
        )

    opts = VerificationOptions(
        run_demo=req.run_demo,
        run_hitl=req.run_hitl,
        hitl_samples=req.hitl_samples,
        timeout_s=req.timeout_s,
    )
    report = verify_post_flash_runtime(req.port, opts)
    report_dict = dataclasses.asdict(report)
    job.verification_report = report_dict
    return FlashVerificationReport(**report_dict)
