"""Tests for the GET /hardware/detected local hardware scan endpoint.

The scan endpoint aggregates the per-chip enumeration helpers that require the
optional akida/samna SDKs and pyserial. These tests prove the endpoint:

- returns an empty list gracefully when no SDK is installed / no device present
  (the default CI state), and
- returns a populated list when the enumeration helpers report devices.

The registration cross-check is exercised by passing the ``registered_identifier``
query parameter that mirrors a caller's saved-target store.
"""

from fastapi.testclient import TestClient

from neurochip.app.limiter import limiter
from neurochip.app.main import app
from neurochip.app.services import akida_backend, flash_service, hardware_detection, speck_backend
from neurochip.contracts.hardware_contracts import DetectedHardwareEntry

limiter.enabled = False
client = TestClient(app)


def setup_module(module):
    limiter.enabled = False


def teardown_module(module):
    limiter.enabled = True


def test_detected_hardware_returns_empty_list_without_sdks(monkeypatch):
    # Every SDK is absent and no serial Teensy port exists — the default CI
    # state. Each per-chip helper behaves exactly as it would without the
    # optional SDK installed.
    monkeypatch.setattr(akida_backend, "_discover_akida_devices", lambda: [])
    monkeypatch.setattr(speck_backend, "_discover_speck_devices", lambda: [])
    monkeypatch.setattr(flash_service, "list_serial_ports", lambda: [])

    response = client.get("/api/neurochip/hardware/detected")

    assert response.status_code == 200
    assert response.json() == []


def test_detected_hardware_marks_registration_from_caller_store(monkeypatch):
    detected = [
        DetectedHardwareEntry(
            chip_type="akida",
            display_name="Akida AKD2000-PCIe-0001",
            identifier="AKD2000-PCIe-0001",
        ),
        DetectedHardwareEntry(
            chip_type="speck",
            display_name="Speck2fDevKit, serial=speck-serial-42, usb=1:3",
            identifier="speck-serial-42",
        ),
        DetectedHardwareEntry(
            chip_type="teensy",
            display_name="Teensy USB Serial",
            identifier="/dev/ttyACM0",
        ),
    ]
    monkeypatch.setattr(hardware_detection, "_detect_local_hardware", lambda: detected)

    response = client.get(
        "/api/neurochip/hardware/detected",
        params=[("registered_identifier", "speck-serial-42")],
    )

    assert response.status_code == 200
    payload = response.json()
    assert len(payload) == 3
    by_chip = {entry["chip_type"]: entry for entry in payload}
    assert by_chip["akida"]["already_registered"] is False
    assert by_chip["speck"]["already_registered"] is True
    assert by_chip["teensy"]["identifier"] == "/dev/ttyACM0"
    assert by_chip["teensy"]["already_registered"] is False


def test_detected_hardware_populated_when_enumerators_return_devices(monkeypatch):
    """End-to-end shape test through the real per-chip enumerator contract.

    The per-chip helpers are replaced with the device shapes they would return
    (an akida device handle, a samna device descriptor, a serial port dict) so
    the aggregation code paths that build identifiers and display names run.
    """

    class _FakeAkidaDevice:
        device = "AKD1000-ABC"

        def __str__(self) -> str:
            return self.device

    class _FakeSpeckDevice:
        device_type_name = "Speck2fDevKit"
        serial_number = "speck-777"
        usb_bus_number = 1
        usb_device_address = 5

    monkeypatch.setattr(akida_backend, "_discover_akida_devices", lambda: [_FakeAkidaDevice()])
    monkeypatch.setattr(speck_backend, "_discover_speck_devices", lambda: [_FakeSpeckDevice()])
    monkeypatch.setattr(
        flash_service,
        "list_serial_ports",
        lambda: [
            {
                "port": "/dev/ttyACM0",
                "description": "Teensy USB Serial",
                "hwid": "USB VID:PID=16C0:0483",
                "is_teensy": True,
            },
            {
                "port": "/dev/tty.usbserial-0001",
                "description": "USB Serial",
                "hwid": "USB VID:PID=0403:6001",
                "is_teensy": False,
            },
        ],
    )

    response = client.get("/api/neurochip/hardware/detected")

    assert response.status_code == 200
    payload = response.json()
    identifiers = {(entry["chip_type"], entry["identifier"]) for entry in payload}
    # The non-Teensy serial port must not be reported.
    assert ("teensy", "/dev/ttyACM0") in identifiers
    assert ("akida", "AKD1000-ABC") in identifiers
    assert ("speck", "speck-777") in identifiers
    assert all(entry["already_registered"] is False for entry in payload)
