from typing import Literal

from pydantic import BaseModel, Field

from neurosense.contracts.encoding_contracts import EncodingConfig
from neurosense.contracts.signal_contracts import FilterConfig


class AcquisitionPreset(BaseModel):
    """Acquisition preset contract defining a complete recording configuration."""

    id: str = Field(..., description="Unique preset identifier (e.g., 'emg_prosthetic')")
    name: str = Field(..., description="Human-readable name")
    signal_type: Literal["emg", "eeg", "eog", "ecg", "tactile"] = Field(
        ..., description="Signal type: emg, eeg, eog, ecg, tactile"
    )
    description: str = Field(..., description="Detailed description of the preset")
    electrode_placement: str = Field(..., description="Markdown with placement instructions")
    electrode_diagram: str = Field(..., description="Path to diagram image")
    channel_mapping: dict[int, str] = Field(..., description="Mapping from channel index to label")
    filter_config: FilterConfig = Field(..., description="Filtering configuration")
    encoding_config: EncodingConfig = Field(..., description="Spike encoding configuration")
    recommended_device: str = Field(..., description="Recommended device type (e.g., 'ganglion')")
