from pydantic import BaseModel


class DeviceInfo(BaseModel):
    id: str  # Unique device identifier
    name: str  # e.g., "OpenBCI Ganglion"
    type: str  # e.g., "ganglion", "cyton", "muse"
    serial_port: str | None  # e.g., "/dev/ttyACM0"
    channels: int  # Number of analog channels
    sampling_rate_hz: int  # Native sampling rate
    connected: bool
    battery_pct: int | None  # If available
    support_level: str = "experimental"  # e.g., "validated", "experimental", "prototype"
