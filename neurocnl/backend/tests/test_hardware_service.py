from unittest.mock import MagicMock, patch

import pytest

from backend.app.schemas.prosthetic import SensorFrame
from backend.app.services import hardware_service


@pytest.fixture(autouse=True)
def reset_serial_connection():
    """Reset the global _serial_connection before and after each test."""
    hardware_service._serial_connection = None
    yield
    hardware_service._serial_connection = None


def test_list_serial_ports_installed():
    """Test list_serial_ports when pyserial is installed."""
    mock_serial = MagicMock()
    mock_port = MagicMock()
    mock_port.device = "/dev/ttyUSB0"
    mock_serial.tools.list_ports.comports.return_value = [mock_port]

    with patch.dict(
        "sys.modules",
        {
            "serial": mock_serial,
            "serial.tools.list_ports": mock_serial.tools.list_ports,
        },
    ):
        ports = hardware_service.list_serial_ports()
        assert ports == ["/dev/ttyUSB0"]


def test_list_serial_ports_not_installed():
    """Test list_serial_ports when pyserial is not installed."""
    with patch.dict("sys.modules", {"serial.tools.list_ports": None}):
        ports = hardware_service.list_serial_ports()
        assert ports == []


def test_connect_success():
    """Test successful serial connection."""
    mock_serial_mod = MagicMock()
    mock_serial_obj = MagicMock()
    mock_serial_mod.Serial.return_value = mock_serial_obj
    with patch.dict("sys.modules", {"serial": mock_serial_mod}):
        result = hardware_service.connect("/dev/ttyUSB0", 115200)
        assert result is True
        assert hardware_service._serial_connection == mock_serial_obj


def test_connect_failure():
    """Test failed serial connection."""
    mock_serial_mod = MagicMock()
    mock_serial_mod.Serial.side_effect = Exception("Connection failed")
    with patch.dict("sys.modules", {"serial": mock_serial_mod}):
        result = hardware_service.connect("/dev/ttyUSB0", 115200)
        assert result is False
        assert hardware_service._serial_connection is None


def test_disconnect_active():
    """Test disconnecting when there's an active connection."""
    mock_serial = MagicMock()
    hardware_service._serial_connection = mock_serial

    result = hardware_service.disconnect()
    assert result is True
    assert hardware_service._serial_connection is None
    mock_serial.close.assert_called_once()


def test_disconnect_inactive():
    """Test disconnecting when there's no active connection."""
    result = hardware_service.disconnect()
    assert result is False
    assert hardware_service._serial_connection is None


def test_list_backend_targets():
    targets = hardware_service.list_backend_targets()
    assert targets == [
        "akida",
        "akida1",
        "akida2",
        "lava",
        "loihi",
        "nengo",
        "pynq",
        "rockpool",
        "spinnaker",
        "spinnaker2",
        "teensy",
    ]


def test_get_backend_capability_helper():
    profile = hardware_service.get_backend_capability("nengo")
    assert profile.name == "nengo"
    assert "threshold_firing" in profile.concept_support


@pytest.mark.asyncio
async def test_stream_sensor_data_success():
    """Test streaming valid sensor data."""
    mock_serial = MagicMock()
    mock_serial.is_open = True

    def readline_effect():
        if readline_effect.call_count == 0:
            readline_effect.call_count += 1
            return b'{"emg": [0.1, 0.2], "proximity": 0.5, "tactile": 0.3}\n'
        else:
            mock_serial.is_open = False
            return b""

    readline_effect.call_count = 0
    mock_serial.readline.side_effect = readline_effect

    hardware_service._serial_connection = mock_serial

    frames = []
    async for frame in hardware_service.stream_sensor_data():
        frames.append(frame)
        if len(frames) >= 1:
            mock_serial.is_open = False  # Break the loop

    assert len(frames) == 1
    assert isinstance(frames[0], SensorFrame)
    assert frames[0].emg_channels == [0.1, 0.2]
    assert frames[0].proximity == 0.5
    assert frames[0].tactile == 0.3


@pytest.mark.asyncio
async def test_stream_sensor_data_malformed():
    """Test streaming malformed JSON data."""
    mock_serial = MagicMock()
    mock_serial.is_open = True

    def readline_effect():
        if readline_effect.call_count == 0:
            readline_effect.call_count += 1
            return b"invalid json\n"
        elif readline_effect.call_count == 1:
            readline_effect.call_count += 1
            return b'{"emg": [1.0], "proximity": 0.1, "tactile": 0.1}\n'
        else:
            mock_serial.is_open = False
            return b""

    readline_effect.call_count = 0
    mock_serial.readline.side_effect = readline_effect

    hardware_service._serial_connection = mock_serial

    frames = []
    async for frame in hardware_service.stream_sensor_data():
        frames.append(frame)
        if len(frames) >= 1:
            mock_serial.is_open = False

    assert len(frames) == 1
    assert frames[0].emg_channels == [1.0]


@pytest.mark.asyncio
async def test_stream_sensor_data_decode_error():
    """Test streaming with decode error."""
    mock_serial = MagicMock()
    mock_serial.is_open = True

    def readline_effect():
        if readline_effect.call_count == 0:
            readline_effect.call_count += 1
            return b"\xff\xff\xff"
        elif readline_effect.call_count == 1:
            readline_effect.call_count += 1
            return b'{"emg": [1.0], "proximity": 0.1, "tactile": 0.1}\n'
        else:
            mock_serial.is_open = False
            return b""

    readline_effect.call_count = 0
    mock_serial.readline.side_effect = readline_effect

    hardware_service._serial_connection = mock_serial

    frames = []
    async for frame in hardware_service.stream_sensor_data():
        frames.append(frame)
        if len(frames) >= 1:
            mock_serial.is_open = False

    assert len(frames) == 1


@pytest.mark.asyncio
async def test_stream_sensor_data_exception():
    """Test streaming when a serial exception occurs."""
    mock_serial = MagicMock()
    mock_serial.is_open = True
    mock_serial.readline.side_effect = Exception("Serial error")

    hardware_service._serial_connection = mock_serial

    frames = []
    async for frame in hardware_service.stream_sensor_data():
        frames.append(frame)

    assert len(frames) == 0
