import io
import subprocess
import tempfile
import time
import zipfile
from unittest.mock import MagicMock, patch

import pytest

from neurochip.app.services.flash_service import (
    FlashStatus,
    clear_post_flash_hooks,
    get_flash_job,
    list_serial_ports,
    register_post_flash_hook,
    start_flash_job,
)


@pytest.fixture(autouse=True)
def _reset_post_flash_hooks():
    """Ensure post-flash hooks don't leak between tests."""
    clear_post_flash_hooks()
    yield
    clear_post_flash_hooks()


def test_list_serial_ports_empty():
    # If no serial ports are available
    with patch("serial.tools.list_ports.comports", return_value=[]):
        ports = list_serial_ports()
        assert isinstance(ports, list)


def test_list_serial_ports_mock():
    mock_port = MagicMock()
    mock_port.device = "/dev/ttyACM0"
    mock_port.description = "Teensy USB Serial"
    mock_port.hwid = "16c0:0483"

    with patch("serial.tools.list_ports.comports", return_value=[mock_port]):
        ports = list_serial_ports()
        assert len(ports) == 1
        assert ports[0]["port"] == "/dev/ttyACM0"
        assert ports[0]["is_teensy"] is True


def test_flash_job_management():
    # Test starting a job and checking its initial state
    # We won't actually run the background thread's subprocesses
    with patch("threading.Thread") as mock_thread:
        job = start_flash_job(b"fake zip", "/dev/ttyACM0")
        assert job.id is not None
        assert job.status == FlashStatus.PENDING

        retrieved_job = get_flash_job(job.id)
        assert retrieved_job == job

        assert mock_thread.called


def test_get_flash_job_not_found():
    assert get_flash_job("non-existent") is None


def _create_test_zip(contents: dict[str, str]) -> bytes:
    """Helper to create an in-memory zip file for testing."""
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as zf:
        for path, data in contents.items():
            zf.writestr(path, data)
    return buf.getvalue()


def test_list_serial_ports_no_pyserial():
    # Patch sys.modules to simulate pyserial not being installed
    with patch.dict("sys.modules", {"serial.tools.list_ports": None}):
        ports = list_serial_ports()
        assert ports == []


def test_run_flash_success():
    zip_bytes = _create_test_zip({"neurochip_firmware/platformio.ini": "[env:teensy41]"})
    mock_run = MagicMock(returncode=0, stdout="", stderr="")

    with patch("subprocess.run", return_value=mock_run):
        job = start_flash_job(zip_bytes, "/dev/ttyACM0")

        # Poll until done or timeout
        for _ in range(20):
            if job.status == FlashStatus.DONE:
                break
            time.sleep(0.1)

        assert job.status == FlashStatus.DONE
        assert job.error is None
        assert job.progress_pct == 100


def test_zip_path_traversal_blocked():
    # Zip with a path traversal attempt
    zip_bytes = _create_test_zip(
        {"../../evil.sh": "echo evil", "neurochip_firmware/platformio.ini": "[env:teensy41]"}
    )
    mock_run = MagicMock(returncode=0, stdout="", stderr="")

    with patch("subprocess.run", return_value=mock_run):
        job = start_flash_job(zip_bytes, "/dev/ttyACM0")

        # Poll until done or timeout
        for _ in range(20):
            if job.status in [FlashStatus.DONE, FlashStatus.FAILED]:
                break
            time.sleep(0.1)

        assert job.status == FlashStatus.FAILED
        assert "Unsafe ZIP member path" in (job.error or "")


def test_run_flash_unexpected_error():
    zip_bytes = _create_test_zip({"neurochip_firmware/platformio.ini": "[env:teensy41]"})

    # Patch zipfile.ZipFile to raise an unexpected error
    with patch("zipfile.ZipFile", side_effect=RuntimeError("Unexpected zip error")):
        job = start_flash_job(zip_bytes, "/dev/ttyACM0")

        # Poll until failure or timeout
        for _ in range(20):
            if job.status == FlashStatus.FAILED:
                break
            time.sleep(0.1)

        assert job.status == FlashStatus.FAILED
        assert job.error == "Unexpected zip error"


def test_run_flash_compile_failure():
    zip_bytes = _create_test_zip({"neurochip_firmware/platformio.ini": "[env:teensy41]"})
    mock_run = MagicMock(
        returncode=1, stdout="", stderr="fatal error: some_header.h: No such file or directory"
    )

    with patch("subprocess.run", return_value=mock_run):
        job = start_flash_job(zip_bytes, "/dev/ttyACM0")

        # Poll until failure or timeout
        for _ in range(20):
            if job.status == FlashStatus.FAILED:
                break
            time.sleep(0.1)

        assert job.status == FlashStatus.FAILED
        assert job.error is not None
        assert "Compilation failed" in job.error
        assert "fatal error" in job.error


def test_run_flash_upload_failure():
    zip_bytes = _create_test_zip({"neurochip_firmware/platformio.ini": "[env:teensy41]"})

    # First call (compile) succeeds, second call (upload) fails
    mock_success = MagicMock(returncode=0, stdout="", stderr="")
    mock_failure = MagicMock(returncode=1, stdout="", stderr="Upload failed: port busy")

    with patch("subprocess.run", side_effect=[mock_success, mock_failure]):
        job = start_flash_job(zip_bytes, "/dev/ttyACM0")

        # Poll until failure or timeout
        for _ in range(20):
            if job.status == FlashStatus.FAILED:
                break
            time.sleep(0.1)

        assert job.status == FlashStatus.FAILED
        assert job.error is not None
        assert "Upload failed" in job.error
        assert "port busy" in job.error


def test_run_flash_timeout():
    zip_bytes = _create_test_zip({"neurochip_firmware/platformio.ini": "[env:teensy41]"})

    with patch(
        "subprocess.run", side_effect=subprocess.TimeoutExpired(cmd=["pio", "run"], timeout=120)
    ):
        job = start_flash_job(zip_bytes, "/dev/ttyACM0")

        # Poll until failure or timeout
        for _ in range(20):
            if job.status == FlashStatus.FAILED:
                break
            time.sleep(0.1)

        assert job.status == FlashStatus.FAILED
        assert job.error is not None
        assert "timed out" in job.error


def test_run_flash_fallback_subdir():
    # Zip with a non-standard top-level directory
    zip_bytes = _create_test_zip({"my_project/platformio.ini": "[env:teensy41]"})
    mock_run = MagicMock(returncode=0, stdout="", stderr="")

    with patch("subprocess.run", return_value=mock_run):
        job = start_flash_job(zip_bytes, "/dev/ttyACM0")

        # Poll until done or timeout
        for _ in range(20):
            if job.status == FlashStatus.DONE:
                break
            time.sleep(0.1)

        assert job.status == FlashStatus.DONE
        assert job.error is None


def test_run_flash_tempdir_cleanup():
    """Temp directory is removed after a successful flash job."""
    import os

    zip_bytes = _create_test_zip({"neurochip_firmware/platformio.ini": "[env:teensy41]"})
    mock_run = MagicMock(returncode=0, stdout="", stderr="")

    captured_tmpdir = []

    original_mkdtemp = tempfile.mkdtemp

    def capturing_mkdtemp(*args, **kwargs):
        path = original_mkdtemp(*args, **kwargs)
        captured_tmpdir.append(path)
        return path

    with patch(
        "neurochip.app.services.flash_service.tempfile.mkdtemp", side_effect=capturing_mkdtemp
    ):
        with patch("subprocess.run", return_value=mock_run):
            job = start_flash_job(zip_bytes, "/dev/ttyACM0")

            for _ in range(20):
                if job.status == FlashStatus.DONE:
                    break
                time.sleep(0.1)

    assert job.status == FlashStatus.DONE
    assert len(captured_tmpdir) == 1
    assert not os.path.exists(captured_tmpdir[0]), "Temp directory should be cleaned up after flash"


def test_list_serial_ports_generic_exception():
    """A non-ImportError failure in port enumeration returns [] instead of raising."""
    with patch("serial.tools.list_ports.comports", side_effect=OSError("port enumeration failed")):
        ports = list_serial_ports()
        assert ports == []


# ---------------------------------------------------------------------------
# Post-flash hook tests
# ---------------------------------------------------------------------------


def test_post_flash_hook_called_on_done():
    """A registered hook is invoked with the completed FlashJob."""
    zip_bytes = _create_test_zip({"neurochip_firmware/platformio.ini": "[env:teensy41]"})
    mock_run = MagicMock(returncode=0, stdout="", stderr="")
    hook = MagicMock()
    register_post_flash_hook(hook)

    with patch("subprocess.run", return_value=mock_run):
        job = start_flash_job(zip_bytes, "/dev/ttyACM0")

        for _ in range(20):
            if job.status == FlashStatus.DONE:
                break
            time.sleep(0.1)

    assert job.status == FlashStatus.DONE
    hook.assert_called_once_with(job)


def test_post_flash_hook_error_does_not_affect_job_status():
    """A hook that raises must not change the job status or block other hooks."""
    zip_bytes = _create_test_zip({"neurochip_firmware/platformio.ini": "[env:teensy41]"})
    mock_run = MagicMock(returncode=0, stdout="", stderr="")

    bad_hook = MagicMock(side_effect=RuntimeError("hook failure"))
    good_hook = MagicMock()
    register_post_flash_hook(bad_hook)
    register_post_flash_hook(good_hook)

    with patch("subprocess.run", return_value=mock_run):
        job = start_flash_job(zip_bytes, "/dev/ttyACM0")

        for _ in range(20):
            if job.status in (FlashStatus.DONE, FlashStatus.FAILED):
                break
            time.sleep(0.1)

    assert job.status == FlashStatus.DONE
    bad_hook.assert_called_once_with(job)
    good_hook.assert_called_once_with(job)


def test_clear_post_flash_hooks_removes_all():
    hook = MagicMock()
    register_post_flash_hook(hook)
    clear_post_flash_hooks()

    zip_bytes = _create_test_zip({"neurochip_firmware/platformio.ini": "[env:teensy41]"})
    mock_run = MagicMock(returncode=0, stdout="", stderr="")

    with patch("subprocess.run", return_value=mock_run):
        job = start_flash_job(zip_bytes, "/dev/ttyACM0")

        for _ in range(20):
            if job.status == FlashStatus.DONE:
                break
            time.sleep(0.1)

    hook.assert_not_called()
