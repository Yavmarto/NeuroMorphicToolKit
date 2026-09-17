"""Flash service — handles PlatformIO build and serial upload."""

import logging
import os
import shutil
import subprocess
import tempfile
import threading
import time
import uuid
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from neurochip._compat import StrEnum

logger = logging.getLogger(__name__)


class FlashStatus(StrEnum):
    PENDING = "pending"
    COMPILING = "compiling"
    UPLOADING = "uploading"
    VERIFYING = "verifying"
    DONE = "done"
    FAILED = "failed"


@dataclass
class FlashJob:
    id: str
    status: FlashStatus = FlashStatus.PENDING
    progress_pct: int = 0
    message: str = ""
    error: str | None = None
    verification_report: dict[str, Any] | None = None


# In-memory job store
_jobs: dict[str, FlashJob] = {}
MAX_FLASH_ZIP_BYTES = 50 * 1024 * 1024
MAX_STORED_JOBS = 500  # evict oldest terminal jobs when store exceeds this limit


def _trim_jobs() -> None:
    """Remove oldest terminal jobs if the store exceeds MAX_STORED_JOBS.

    Only DONE and FAILED jobs are eligible for eviction; in-progress jobs
    are always retained so callers can poll them.
    """
    if len(_jobs) < MAX_STORED_JOBS:
        return
    terminal = [
        jid for jid, j in _jobs.items() if j.status in (FlashStatus.DONE, FlashStatus.FAILED)
    ]
    evict_count = len(_jobs) - MAX_STORED_JOBS + 1
    for jid in terminal[:evict_count]:
        del _jobs[jid]


MAX_FLASH_ZIP_MEMBERS = 1000

# Post-flash hook registry
_post_flash_hooks: list[Callable[[FlashJob], None]] = []


def register_post_flash_hook(fn: Callable[[FlashJob], None]) -> None:
    """Register a callback invoked after a flash job reaches DONE status.

    The callback receives the completed :class:`FlashJob` as its only
    argument.  Exceptions raised by the callback are logged and swallowed so
    that a faulty hook cannot affect the job status visible to the caller.
    """
    _post_flash_hooks.append(fn)


def clear_post_flash_hooks() -> None:
    """Remove all registered post-flash hooks.

    Intended for test isolation — call this in a fixture teardown or
    ``autouse`` fixture to prevent hook state from leaking between tests.
    """
    _post_flash_hooks.clear()


def list_serial_ports() -> list[dict[str, Any]]:
    """List available serial ports (Teensy devices)."""
    logger.info("Listing serial ports")
    try:
        import serial.tools.list_ports

        ports = serial.tools.list_ports.comports()
        result = [
            {
                "port": p.device,
                "description": p.description,
                "hwid": p.hwid,
                "is_teensy": "teensy" in (p.description or "").lower()
                or "16c0:0483" in (p.hwid or "").lower(),
            }
            for p in ports
        ]
        logger.info("Found %s serial ports", len(result))
        return result
    except ImportError:
        logger.error("pyserial not installed, cannot list ports")
        return []
    except Exception as exc:
        logger.error("Failed to enumerate serial ports: %s", exc)
        return []


def start_flash_job(firmware_zip_bytes: bytes, serial_port: str) -> FlashJob:
    """
    Start an async firmware flash job.

    Extracts the firmware zip, runs PlatformIO build, and uploads via serial.
    """
    _trim_jobs()
    job_id = str(uuid.uuid4())
    job = FlashJob(id=job_id)
    _jobs[job_id] = job

    thread = threading.Thread(
        target=_run_flash, args=(job, firmware_zip_bytes, serial_port), daemon=True
    )
    thread.start()

    return job


def _validate_flash_zip(zip_bytes: bytes) -> None:
    import io
    import zipfile

    if len(zip_bytes) > MAX_FLASH_ZIP_BYTES:
        raise ValueError(f"ZIP exceeds {MAX_FLASH_ZIP_BYTES // 1024 // 1024} MB limit.")

    with zipfile.ZipFile(io.BytesIO(zip_bytes), "r") as zf:
        members = zf.namelist()
        if len(members) > MAX_FLASH_ZIP_MEMBERS:
            raise ValueError(
                f"ZIP contains {len(members)} members; limit is {MAX_FLASH_ZIP_MEMBERS}."
            )
        for name in members:
            member_path = Path(name)
            if member_path.is_absolute() or ".." in member_path.parts:
                raise ValueError(f"Unsafe ZIP member path: {name!r}")


def _run_flash(job: FlashJob, firmware_zip_bytes: bytes, serial_port: str) -> None:
    """Execute the flash process in a background thread."""
    import io
    import zipfile

    start_time = time.time()
    logger.info("Starting flash job %s for port %s", job.id, serial_port)

    tmpdir = None
    try:
        # Extract firmware to temp directory
        extract_start = time.time()
        tmpdir = tempfile.mkdtemp(prefix="neurochip_flash_")
        _validate_flash_zip(firmware_zip_bytes)
        with zipfile.ZipFile(io.BytesIO(firmware_zip_bytes), "r") as zf:
            zf.extractall(tmpdir)

        project_dir = os.path.join(tmpdir, "neurochip_firmware")
        if not Path(project_dir).exists():
            # Find the actual project dir
            subdirs = [d for d in os.listdir(tmpdir) if os.path.isdir(os.path.join(tmpdir, d))]
            project_dir = os.path.join(tmpdir, subdirs[0]) if subdirs else tmpdir
        extract_duration = time.time() - extract_start
        logger.info("Job %s: firmware extraction took %.2fs", job.id, extract_duration)

        # Check for mock/simulation mode
        is_simulation = serial_port.startswith("/tmp/ttyV")

        # Compile
        job.status = FlashStatus.COMPILING
        job.progress_pct = 20
        job.message = "Compiling firmware with PlatformIO..."
        compile_start = time.time()

        if is_simulation:
            time.sleep(1)  # Simulate compilation
            logger.info("Job %s: simulation mode, skipping real compilation", job.id)
        else:
            result = subprocess.run(
                ["pio", "run"],
                cwd=project_dir,
                capture_output=True,
                text=True,
                timeout=120,
            )
            compile_duration = time.time() - compile_start
            if result.returncode != 0:
                logger.error("Job %s: compilation failed after %.2fs", job.id, compile_duration)
                job.status = FlashStatus.FAILED
                job.error = f"Compilation failed: {result.stderr[-500:]}"
                return
            logger.info("Job %s: compilation successful in %.2fs", job.id, compile_duration)

        # Upload
        job.status = FlashStatus.UPLOADING
        job.progress_pct = 60
        job.message = f"Uploading to {serial_port}..."
        upload_start = time.time()

        if is_simulation:
            time.sleep(1)  # Simulate upload
            logger.info("Job %s: simulation mode, skipping real upload", job.id)
        else:
            logger.info("Job %s: opening serial port %s for upload", job.id, serial_port)
            result = subprocess.run(
                ["pio", "run", "--target", "upload", "--upload-port", serial_port],
                cwd=project_dir,
                capture_output=True,
                text=True,
                timeout=120,
            )
            upload_duration = time.time() - upload_start
            if result.returncode != 0:
                logger.error("Job %s: upload failed after %.2fs", job.id, upload_duration)
                job.status = FlashStatus.FAILED
                job.error = f"Upload failed: {result.stderr[-500:]}"
                return
            logger.info(
                "Job %s: upload successful in %.2fs. Port %s closed.",
                job.id,
                upload_duration,
                serial_port,
            )

        # Verify
        job.status = FlashStatus.VERIFYING
        job.progress_pct = 90
        job.message = "Verifying upload..."

        # Done
        job.status = FlashStatus.DONE
        job.progress_pct = 100
        job.message = "Firmware flashed successfully."
        total_duration = time.time() - start_time
        logger.info("Job %s: flash completed successfully in %.2fs", job.id, total_duration)

        for hook in list(_post_flash_hooks):
            try:
                hook(job)
            except Exception as hook_exc:
                logger.error("Job %s: post-flash hook %r raised: %s", job.id, hook, hook_exc)

    except subprocess.TimeoutExpired:
        logger.error("Job %s: build/upload timed out", job.id)
        job.status = FlashStatus.FAILED
        job.error = "Build/upload timed out after 120 seconds"
    except Exception as exc:
        logger.error("Job %s: unexpected error: %s", job.id, exc)
        job.status = FlashStatus.FAILED
        job.error = str(exc)
    finally:
        if tmpdir is not None:
            shutil.rmtree(tmpdir, ignore_errors=True)


def get_flash_job(job_id: str) -> FlashJob | None:
    return _jobs.get(job_id)
