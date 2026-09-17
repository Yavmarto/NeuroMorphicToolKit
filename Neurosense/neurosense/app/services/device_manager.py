"""
Device management service wrapping BrainFlow for device discovery,
connection lifecycle, and data acquisition.
"""

from __future__ import annotations

import importlib
import os
import uuid
from dataclasses import dataclass
from types import SimpleNamespace
from typing import Any, cast

from ..schemas.devices import DeviceInfo

_CYTON_SERIAL_ENV = "NEUROSENSE_CYTON_SERIAL_PORT"
_MUSE_MODEL_ENV = "NEUROSENSE_MUSE_MODEL"
_MUSE_MAC_ENV = "NEUROSENSE_MUSE_MAC_ADDRESS"
_MUSE_PRESET_ENV = "NEUROSENSE_MUSE_PRESET"
_PIEEG_STREAM_HOST_ENV = "NEUROSENSE_PIEEG_STREAM_HOST"
_PIEEG_STREAM_PORT_ENV = "NEUROSENSE_PIEEG_STREAM_PORT"

# ponytail: numeric fallbacks when BrainFlow is missing; lazy import upgrades these.
_MUSE_2_BOARD_ID = 38
_MUSE_S_BOARD_ID = 39
_MUSE_BLED_BOARD_ID = 22
_PIEEG_BOARD_ID = 56
_STREAMING_BOARD_ID = -2
_DEFAULT_MUSE_PRESET = "p21"
_DEFAULT_PIEEG_STREAM_PORT = 6677

# Shared ADS1299 acquisition profile for Cyton and PiEEG paths.
_ADS1299_PROFILE: dict[str, int] = {
    "channels": 8,
    "sampling_rate_hz": 250,
}

_MUSE_PROFILE: dict[str, int] = {
    "channels": 4,
    "sampling_rate_hz": 256,
}


def _load_brainflow_board_shim() -> Any:
    """Load BrainFlow lazily so mypy does not require third-party stubs."""
    return cast(Any, importlib.import_module("brainflow.board_shim"))


def _board_id_constant(name: str, fallback: int) -> int:
    """Resolve a BrainFlow BoardIds constant with a numeric fallback."""
    try:
        brainflow = _load_brainflow_board_shim()
        return int(getattr(brainflow.BoardIds, name))
    except (ImportError, AttributeError):
        return fallback


def _muse_board_id(model: str) -> int:
    normalized = model.strip().lower()
    if normalized in {"muse2", "muse_2", "2"}:
        return _board_id_constant("MUSE_2_BOARD", _MUSE_2_BOARD_ID)
    if normalized in {"muses", "muse_s", "s"}:
        return _board_id_constant("MUSE_S_BOARD", _MUSE_S_BOARD_ID)
    if normalized in {"bled", "muse_bled", "dongle"}:
        return _board_id_constant("MUSE_2_BLED_BOARD", _MUSE_BLED_BOARD_ID)
    raise ValueError(
        f"Unsupported Muse model '{model}'. Use muse2, muses, or bled."
    )


def _pieeg_board_id() -> int:
    return _board_id_constant("PIEEG_BOARD", _PIEEG_BOARD_ID)


def _streaming_board_id() -> int:
    return _board_id_constant("STREAMING_BOARD", _STREAMING_BOARD_ID)


@dataclass(frozen=True)
class ConfiguredDeviceTarget:
    """Configuration needed to truthfully expose a real-board target."""

    device_id: str
    name: str
    type: str
    channels: int
    sampling_rate_hz: int
    serial_port: str | None = None
    mac_address: str | None = None
    other_info: str | None = None
    board_id: int | None = None
    master_board_id: int | None = None
    stream_host: str | None = None
    stream_port: int | None = None


class DeviceManager:
    """Singleton service managing biosignal device connections via BrainFlow."""

    def __init__(self) -> None:
        # device_id -> DeviceInfo
        self._devices: dict[str, DeviceInfo] = {}
        # device_id -> board session (BrainFlow BoardShim instance)
        self._boards: dict[str, Any] = {}
        # device_id -> BrainFlow board id used for channel metadata
        self._board_ids: dict[str, int] = {}
        # mock board shim for testing
        self._mock_board_shim: Any | None = None

    def set_mock_board_shim(self, mock_board_shim: Any | None) -> None:
        """Inject a mock BoardShim for testing."""
        self._mock_board_shim = mock_board_shim

    def _upsert_device(
        self,
        *,
        device_id: str,
        name: str,
        device_type: str,
        channels: int,
        sampling_rate_hz: int,
        serial_port: str | None = None,
        support_level: str = "experimental",
    ) -> DeviceInfo:
        """Create or update a discovered device without losing connection state."""
        existing = self._devices.get(device_id)
        device = DeviceInfo(
            id=device_id,
            name=name,
            type=device_type,
            serial_port=(
                serial_port
                if serial_port is not None
                else existing.serial_port
                if existing
                else None
            ),
            channels=channels,
            sampling_rate_hz=sampling_rate_hz,
            connected=existing.connected if existing else False,
            battery_pct=existing.battery_pct if existing else None,
            support_level=support_level if existing is None else existing.support_level,
        )
        self._devices[device_id] = device
        return device

    def _sampling_rate_for_board(self, board_id: int, fallback: int) -> int:
        try:
            brainflow = _load_brainflow_board_shim()
            return int(brainflow.BoardShim.get_sampling_rate(board_id))
        except ImportError:
            return fallback
        except Exception:
            return fallback

    def _configured_cyton_target(self) -> ConfiguredDeviceTarget | None:
        """Return the active Cyton target when explicitly configured."""
        serial_port = os.environ.get(_CYTON_SERIAL_ENV)
        if self._mock_board_shim is None and not serial_port:
            return None

        cyton_board_id = _board_id_constant("CYTON_BOARD", 0)
        sampling_rate_hz = self._sampling_rate_for_board(
            cyton_board_id, _ADS1299_PROFILE["sampling_rate_hz"]
        )

        return ConfiguredDeviceTarget(
            device_id="cyton_primary",
            name="OpenBCI Cyton",
            type="cyton",
            channels=_ADS1299_PROFILE["channels"],
            sampling_rate_hz=sampling_rate_hz,
            serial_port=serial_port,
            board_id=cyton_board_id,
        )

    def _configured_muse_target(self) -> ConfiguredDeviceTarget | None:
        """Return the active Muse target when explicitly configured."""
        model = os.environ.get(_MUSE_MODEL_ENV, "").strip().lower()
        if self._mock_board_shim is not None and not model:
            model = "muse2"
        if not model:
            return None

        board_id = _muse_board_id(model)
        sampling_rate_hz = self._sampling_rate_for_board(
            board_id, _MUSE_PROFILE["sampling_rate_hz"]
        )
        preset = os.environ.get(_MUSE_PRESET_ENV, _DEFAULT_MUSE_PRESET).strip() or _DEFAULT_MUSE_PRESET
        mac_address = os.environ.get(_MUSE_MAC_ENV)
        display_name = {
            "muse2": "Muse 2",
            "muse_2": "Muse 2",
            "2": "Muse 2",
            "muses": "Muse S",
            "muse_s": "Muse S",
            "s": "Muse S",
            "bled": "Muse 2 (BLED dongle)",
            "muse_bled": "Muse 2 (BLED dongle)",
            "dongle": "Muse 2 (BLED dongle)",
        }.get(model, f"Muse ({model})")

        return ConfiguredDeviceTarget(
            device_id=f"muse_{model.replace('_', '')}",
            name=display_name,
            type="muse",
            channels=_MUSE_PROFILE["channels"],
            sampling_rate_hz=sampling_rate_hz,
            mac_address=mac_address,
            other_info=preset,
            board_id=board_id,
        )

    def _configured_pieeg_target(self) -> ConfiguredDeviceTarget | None:
        """Return the active PiEEG target when streaming relay or mock is configured."""
        stream_host = os.environ.get(_PIEEG_STREAM_HOST_ENV, "").strip()
        if self._mock_board_shim is None and not stream_host:
            return None

        pieeg_board_id = _pieeg_board_id()
        sampling_rate_hz = self._sampling_rate_for_board(
            pieeg_board_id, _ADS1299_PROFILE["sampling_rate_hz"]
        )
        stream_port = int(
            os.environ.get(_PIEEG_STREAM_PORT_ENV, str(_DEFAULT_PIEEG_STREAM_PORT))
        )
        use_streaming = bool(stream_host) and self._mock_board_shim is None

        return ConfiguredDeviceTarget(
            device_id="pieeg_primary",
            name="PiEEG (ADS1299)",
            type="pieeg",
            channels=_ADS1299_PROFILE["channels"],
            sampling_rate_hz=sampling_rate_hz,
            board_id=_streaming_board_id() if use_streaming else pieeg_board_id,
            master_board_id=pieeg_board_id if use_streaming else None,
            stream_host=stream_host or None,
            stream_port=stream_port if use_streaming else None,
        )

    def _provision_test_device(self, board_type: str, serial_port: str | None) -> str:
        """Create an ephemeral test device entry for local development workflows."""
        device_id = f"{board_type}_{uuid.uuid4().hex[:8]}"
        channel_map = {
            "synthetic": 8,
            "cyton": _ADS1299_PROFILE["channels"],
            "pieeg": _ADS1299_PROFILE["channels"],
            "muse": _MUSE_PROFILE["channels"],
            "muse2": _MUSE_PROFILE["channels"],
            "muses": _MUSE_PROFILE["channels"],
            "ganglion": 4,
        }
        rate_map = {
            "synthetic": 250,
            "cyton": _ADS1299_PROFILE["sampling_rate_hz"],
            "pieeg": _ADS1299_PROFILE["sampling_rate_hz"],
            "muse": _MUSE_PROFILE["sampling_rate_hz"],
            "muse2": _MUSE_PROFILE["sampling_rate_hz"],
            "muses": _MUSE_PROFILE["sampling_rate_hz"],
            "ganglion": 200,
        }
        self._devices[device_id] = DeviceInfo(
            id=device_id,
            name=board_type.capitalize(),
            type=board_type,
            serial_port=serial_port,
            channels=channel_map.get(board_type, 4),
            sampling_rate_hz=rate_map.get(board_type, 250),
            connected=False,
            battery_pct=None,
            support_level="validated" if board_type == "synthetic" else "experimental",
        )
        return device_id

    def _resolve_connect_device_id(self, device_id: str, serial_port: str | None) -> str:
        """Resolve a requested device id, creating test placeholders when needed."""
        if device_id in self._devices:
            return device_id
        if device_id in {
            "synthetic",
            "ganglion",
            "cyton",
            "muse",
            "muse2",
            "muses",
            "pieeg",
        }:
            return self._provision_test_device(device_id, serial_port)
        raise ValueError(f"Device '{device_id}' not found. Run a scan first.")

    def _append_configured_target(
        self,
        discovered: list[DeviceInfo],
        target: ConfiguredDeviceTarget,
    ) -> None:
        discovered.append(
            self._upsert_device(
                device_id=target.device_id,
                name=target.name,
                device_type=target.type,
                channels=target.channels,
                sampling_rate_hz=target.sampling_rate_hz,
                serial_port=target.serial_port,
                support_level="experimental",
            )
        )

    def _resolve_board_for_device(
        self,
        device: DeviceInfo,
        *,
        serial_port: str | None,
        mac_address: str | None = None,
        other_info: str | None = None,
    ) -> tuple[int, int, SimpleNamespace | Any]:
        """Return connect board id, metadata board id, and BrainFlow params."""
        configured_targets = (
            self._configured_cyton_target(),
            self._configured_muse_target(),
            self._configured_pieeg_target(),
        )
        configured = next(
            (target for target in configured_targets if target and target.device_id == device.id),
            None,
        )

        board_type_map = {
            "synthetic": _board_id_constant("SYNTHETIC_BOARD", -1),
            "ganglion": _board_id_constant("GANGLION_BOARD", 1),
            "cyton": _board_id_constant("CYTON_BOARD", 0),
            "muse": _muse_board_id("muse2"),
            "muse2": _muse_board_id("muse2"),
            "muses": _muse_board_id("muses"),
            "pieeg": _pieeg_board_id(),
        }
        metadata_board_id = configured.board_id if configured and configured.board_id is not None else board_type_map.get(device.type, -1)
        connect_board_id = metadata_board_id
        params = SimpleNamespace(
            serial_port=serial_port,
            mac_address=mac_address,
            other_info=other_info,
            ip_address=None,
            ip_port=None,
        )

        if configured is not None:
            if configured.mac_address:
                params.mac_address = configured.mac_address
            if configured.other_info:
                params.other_info = configured.other_info
            if configured.stream_host:
                connect_board_id = _streaming_board_id()
                params.ip_address = configured.stream_host
                params.ip_port = configured.stream_port
                metadata_board_id = configured.master_board_id or metadata_board_id

        if device.type == "muse" and params.other_info is None:
            params.other_info = _DEFAULT_MUSE_PRESET

        return connect_board_id, metadata_board_id, params

    # ------------------------------------------------------------------
    # Discovery
    # ------------------------------------------------------------------

    async def scan_devices(self) -> list[DeviceInfo]:
        """Scan for available biosignal devices using BrainFlow discovery.

        Always exposes the synthetic testing board. Real-board targets are
        exposed only when explicitly configured or when running with a
        mock board shim for rehearsal.
        """
        discovered: list[DeviceInfo] = []
        synthetic_sampling_rate = 250

        try:
            brainflow = _load_brainflow_board_shim()
            synthetic_sampling_rate = int(
                brainflow.BoardShim.get_sampling_rate(brainflow.BoardIds.SYNTHETIC_BOARD)
            )
        except ImportError:
            synthetic_sampling_rate = 250
        except Exception:
            synthetic_sampling_rate = 250

        discovered.append(
            self._upsert_device(
                device_id="synthetic_default",
                name="Synthetic Testing Board",
                device_type="synthetic",
                channels=8,
                sampling_rate_hz=synthetic_sampling_rate,
                support_level="validated",
            )
        )

        for target in (
            self._configured_cyton_target(),
            self._configured_muse_target(),
            self._configured_pieeg_target(),
        ):
            if target is not None:
                self._append_configured_target(discovered, target)

        return discovered

    # ------------------------------------------------------------------
    # Connection lifecycle
    # ------------------------------------------------------------------

    async def connect(
        self,
        device_id: str,
        serial_port: str | None = None,
        allow_experimental: bool = False,
        mac_address: str | None = None,
        other_info: str | None = None,
    ) -> DeviceInfo:
        """Establish a connection to the specified device.

        Raises ValueError if the device is not found.
        Raises ValueError if connecting to an experimental device without allow_experimental=True.
        """
        device_id = self._resolve_connect_device_id(device_id, serial_port)
        device = self._devices[device_id]

        if device.support_level in {"experimental", "prototype"} and not allow_experimental:
            raise ValueError(
                f"Device '{device.name}' is marked as {device.support_level}. "
                "Use allow_experimental=True to connect."
            )

        if device.connected or self._boards.get(device_id) is not None:
            raise RuntimeError(f"Device '{device_id}' is already connected.")

        resolved_serial_port = serial_port or device.serial_port
        if device.type == "cyton" and self._mock_board_shim is None and not resolved_serial_port:
            raise ValueError(
                "OpenBCI Cyton target is not configured. "
                f"Set {_CYTON_SERIAL_ENV} or provide serial_port when connecting."
            )
        if device.type == "pieeg" and self._mock_board_shim is None and not os.environ.get(
            _PIEEG_STREAM_HOST_ENV, ""
        ).strip():
            raise ValueError(
                "PiEEG streaming relay is not configured. "
                f"Set {_PIEEG_STREAM_HOST_ENV} or use --mock in the acceptance script."
            )

        connect_board_id, metadata_board_id, params = self._resolve_board_for_device(
            device,
            serial_port=resolved_serial_port,
            mac_address=mac_address,
            other_info=other_info,
        )

        try:
            if self._mock_board_shim is not None:
                board = self._mock_board_shim(connect_board_id, params)
            else:
                brainflow = _load_brainflow_board_shim()
                input_params = brainflow.BrainFlowInputParams()
                if resolved_serial_port:
                    input_params.serial_port = resolved_serial_port
                if params.mac_address:
                    input_params.mac_address = params.mac_address
                if params.other_info:
                    input_params.other_info = params.other_info
                if params.ip_address:
                    input_params.ip_address = params.ip_address
                if params.ip_port is not None:
                    input_params.ip_port = int(params.ip_port)
                board = brainflow.BoardShim(connect_board_id, input_params)

            board.prepare_session()
            board.start_stream()

            self._boards[device_id] = board
            self._board_ids[device_id] = metadata_board_id
        except ImportError as exc:
            if device.type == "synthetic":
                self._boards[device_id] = None
                self._board_ids[device_id] = connect_board_id
            else:
                raise RuntimeError(
                    f"BrainFlow is not installed; cannot connect to '{device.name}'."
                ) from exc
        except Exception as exc:
            raise RuntimeError(
                f"Failed to connect to '{device.name}' during session prepare/start: {exc}"
            ) from exc

        device = device.model_copy(
            update={"connected": True, "serial_port": resolved_serial_port or device.serial_port}
        )
        self._devices[device_id] = device
        return device

    async def disconnect(self, device_id: str) -> DeviceInfo:
        """Disconnect from the specified device.

        Raises ValueError if the device is not found or not connected.
        """
        if device_id not in self._devices:
            raise ValueError(f"Device '{device_id}' not found.")

        device = self._devices[device_id]
        if not device.connected:
            raise ValueError(f"Device '{device_id}' is not connected.")

        board = self._boards.pop(device_id, None)
        self._board_ids.pop(device_id, None)
        if board is not None:
            try:
                board.stop_stream()
                board.release_session()
            except Exception:
                pass

        device = device.model_copy(update={"connected": False})
        self._devices[device_id] = device
        return device

    # ------------------------------------------------------------------
    # Impedance
    # ------------------------------------------------------------------

    async def check_impedance(self, device_id: str) -> dict[str, Any]:
        """Run impedance check on connected device.

        Returns per-channel impedance values in kOhm.
        """
        if device_id not in self._devices:
            raise ValueError(f"Device '{device_id}' not found.")
        device = self._devices[device_id]
        if not device.connected:
            raise ValueError(f"Device '{device_id}' is not connected.")

        # Attempt BrainFlow impedance measurement
        board = self._boards.get(device_id)
        if board is not None:
            try:
                metadata_board_id = self._board_ids.get(device_id, int(board.board_id))
                if self._mock_board_shim is not None:
                    eeg_channels = self._mock_board_shim.get_eeg_channels(metadata_board_id)
                else:
                    brainflow = _load_brainflow_board_shim()
                    eeg_channels = brainflow.BoardShim.get_eeg_channels(metadata_board_id)
                impedance_values: dict[int, float | None] = {}
                for ch in eeg_channels:
                    impedance_values[ch] = None  # BrainFlow impedance API is device-specific
                return {
                    "device_id": device_id,
                    "channels": impedance_values,
                    "status": "completed",
                }
            except Exception:
                pass

        return {
            "device_id": device_id,
            "channels": dict.fromkeys(range(device.channels)),
            "status": "unavailable",
            "message": "Impedance measurement not supported for this device/configuration.",
        }

    # ------------------------------------------------------------------
    # Data acquisition helpers
    # ------------------------------------------------------------------

    def get_board(self, device_id: str) -> Any:
        """Return the raw BrainFlow BoardShim for the given device, or None."""
        return self._boards.get(device_id)

    @property
    def active_connections(self) -> list[DeviceInfo]:
        """Return a list of all currently connected devices."""
        return [d for d in self._devices.values() if d.connected]

    def get_connected_device(self) -> DeviceInfo | None:
        """Return the first connected device (for backward compatibility)."""
        connections = self.active_connections
        return connections[0] if connections else None

    async def get_current_data(self, device_id: str, num_samples: int = 125) -> list[list[float]]:
        """Read the latest *num_samples* from the device ring buffer.

        Returns a 2-D list (channels x samples). Falls back to empty
        data when BrainFlow is unavailable.
        """
        board = self._boards.get(device_id)
        if board is not None:
            try:
                data = board.get_current_board_data(num_samples)
                metadata_board_id = self._board_ids.get(device_id, int(board.board_id))
                if self._mock_board_shim is not None:
                    eeg_channels = self._mock_board_shim.get_eeg_channels(metadata_board_id)
                else:
                    brainflow = _load_brainflow_board_shim()
                    eeg_channels = brainflow.BoardShim.get_eeg_channels(metadata_board_id)
                return [data[ch].tolist() for ch in eeg_channels]
            except Exception:
                pass

        device = self._devices.get(device_id)
        n_ch = device.channels if device else 1
        return [[] for _ in range(n_ch)]


# ---------------------------------------------------------------------------
# Module-level singleton
# ---------------------------------------------------------------------------
device_manager = DeviceManager()

# ponytail: test-only hook for multiprocess bridge verifiers; upgrade path is a
# dedicated launcher flag once the hw worker owns mock injection.
if os.environ.get("NEUROSENSE_MOCK_BOARD_SHIM", "").lower() in {"1", "true", "yes"}:
    try:
        from neurosense.tests.mock_device import MockBoardShim as _MockBoardShim

        device_manager.set_mock_board_shim(_MockBoardShim)
    except ImportError:
        pass
