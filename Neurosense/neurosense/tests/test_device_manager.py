from __future__ import annotations

from unittest.mock import patch

import pytest

from neurosense.app.services.device_manager import DeviceManager
from neurosense.tests.mock_device import MockBoardShim


@pytest.mark.anyio
async def test_scan_devices() -> None:
    manager = DeviceManager()
    with patch.object(manager, "_sampling_rate_for_board", return_value=250):
        devices = await manager.scan_devices()
        assert len(devices) == 1
        assert devices[0].type == "synthetic"
        assert devices[0].support_level == "validated"


@pytest.mark.anyio
async def test_scan_devices_exposes_cyton_when_configured() -> None:
    manager = DeviceManager()
    with (
        patch.dict("os.environ", {"NEUROSENSE_CYTON_SERIAL_PORT": "/dev/cu.usbserial-CYTON"}),
        patch.object(manager, "_sampling_rate_for_board", return_value=250),
    ):
        devices = await manager.scan_devices()

    assert {device.type for device in devices} == {"synthetic", "cyton"}
    cyton = next(device for device in devices if device.type == "cyton")
    assert cyton.serial_port == "/dev/cu.usbserial-CYTON"
    assert cyton.support_level == "experimental"


@pytest.mark.anyio
async def test_connect_disconnect() -> None:
    manager = DeviceManager()
    manager.set_mock_board_shim(MockBoardShim)
    with patch.object(manager, "_sampling_rate_for_board", return_value=250):
        devices = await manager.scan_devices()

    device_id = devices[0].id
    connected_device = await manager.connect(device_id, allow_experimental=True)

    assert connected_device.connected is True
    current_device = manager.get_connected_device()
    assert current_device is not None
    assert current_device.id == device_id

    disconnected_device = await manager.disconnect(device_id)
    assert disconnected_device.connected is False
    assert manager.get_connected_device() is None
    manager.set_mock_board_shim(None)


@pytest.mark.anyio
async def test_connect_already_connected() -> None:
    manager = DeviceManager()
    manager.set_mock_board_shim(MockBoardShim)
    with patch.object(manager, "_sampling_rate_for_board", return_value=250):
        devices = await manager.scan_devices()

    await manager.connect(devices[0].id, allow_experimental=True)
    with pytest.raises(RuntimeError, match="already connected"):
        await manager.connect(devices[0].id, allow_experimental=True)
    manager.set_mock_board_shim(None)


@pytest.mark.anyio
async def test_get_current_data() -> None:
    manager = DeviceManager()
    manager.set_mock_board_shim(MockBoardShim)
    with patch.object(manager, "_sampling_rate_for_board", return_value=250):
        devices = await manager.scan_devices()

    device_id = devices[0].id
    await manager.connect(device_id, allow_experimental=True)
    data = await manager.get_current_data(device_id, num_samples=64)

    assert len(data) == 8
    assert len(data[0]) == 64
    manager.set_mock_board_shim(None)


@pytest.mark.anyio
async def test_scan_devices_exposes_muse_when_configured() -> None:
    manager = DeviceManager()
    with (
        patch.dict("os.environ", {"NEUROSENSE_MUSE_MODEL": "muse2"}),
        patch.object(manager, "_sampling_rate_for_board", return_value=256),
    ):
        devices = await manager.scan_devices()

    assert {device.type for device in devices} == {"synthetic", "muse"}
    muse = next(device for device in devices if device.type == "muse")
    assert muse.channels == 4
    assert muse.sampling_rate_hz == 256
    assert muse.support_level == "experimental"


@pytest.mark.anyio
async def test_scan_devices_exposes_pieeg_when_stream_host_configured() -> None:
    manager = DeviceManager()
    with (
        patch.dict("os.environ", {"NEUROSENSE_PIEEG_STREAM_HOST": "225.1.1.1"}),
        patch.object(manager, "_sampling_rate_for_board", return_value=250),
    ):
        devices = await manager.scan_devices()

    assert {device.type for device in devices} == {"synthetic", "pieeg"}
    pieeg = next(device for device in devices if device.type == "pieeg")
    assert pieeg.channels == 8
    assert pieeg.sampling_rate_hz == 250


@pytest.mark.anyio
async def test_connect_disconnect_muse_with_mock_board() -> None:
    from neurosense.tests.mock_device import MockBoardShim

    manager = DeviceManager()
    manager.set_mock_board_shim(MockBoardShim)
    with (
        patch.dict("os.environ", {"NEUROSENSE_MUSE_MODEL": "muse2"}),
        patch.object(manager, "_sampling_rate_for_board", return_value=256),
    ):
        devices = await manager.scan_devices()
        muse = next(device for device in devices if device.type == "muse")
        connected = await manager.connect(muse.id, allow_experimental=True)
        assert connected.connected is True
        data = await manager.get_current_data(muse.id, num_samples=64)
        assert len(data) == 4
        disconnected = await manager.disconnect(muse.id)
        assert disconnected.connected is False
    manager.set_mock_board_shim(None)


@pytest.mark.anyio
async def test_connect_disconnect_pieeg_with_mock_board() -> None:
    manager = DeviceManager()
    manager.set_mock_board_shim(MockBoardShim)
    with (
        patch.dict("os.environ", {"NEUROSENSE_PIEEG_STREAM_HOST": "225.1.1.1"}),
        patch.object(manager, "_sampling_rate_for_board", return_value=250),
    ):
        devices = await manager.scan_devices()
        pieeg = next(device for device in devices if device.type == "pieeg")
        connected = await manager.connect(pieeg.id, allow_experimental=True)
        assert connected.connected is True
        data = await manager.get_current_data(pieeg.id, num_samples=64)
        assert len(data) == 8
        disconnected = await manager.disconnect(pieeg.id)
        assert disconnected.connected is False
    manager.set_mock_board_shim(None)


@pytest.mark.anyio
async def test_check_impedance() -> None:
    manager = DeviceManager()
    manager.set_mock_board_shim(MockBoardShim)
    with patch.object(manager, "_sampling_rate_for_board", return_value=250):
        devices = await manager.scan_devices()

    device_id = devices[0].id
    await manager.connect(device_id, allow_experimental=True)
    result = await manager.check_impedance(device_id)

    assert result["device_id"] == device_id
    assert "channels" in result
    assert result["status"] == "completed"
    manager.set_mock_board_shim(None)
