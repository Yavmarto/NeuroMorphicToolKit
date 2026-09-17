from typing import ClassVar

from pydantic import BaseModel, Field, model_validator

from neurochip._compat import StrEnum


class TargetDevice(StrEnum):
    TEENSY_41 = "Teensy 4.1"
    LOIHI_2 = "Intel Loihi 2"
    AKIDA = "BrainChip Akida"
    SPINNAKER = "SpiNNaker"
    BRAINSCALES = "BrainScaleS"
    LAVA = "Lava"
    NEUROML = "NeuroML"
    PYNQ_Z2 = "PYNQ-Z2"


class DeploymentManifest(BaseModel):
    """
    Contract for deployment manifests, including target device, firmware version, and checksum.
    Enforces target compatibility invariants for firmware versions.
    """

    target_device: TargetDevice
    core_count: int = Field(
        ..., ge=1, le=128, description="Number of cores used by the deployment."
    )
    firmware_version: str = Field(
        ...,
        pattern=r"^\d+\.\d+\.\d+$",
        description="Firmware version in SemVer format (e.g., 0.1.0).",
    )
    checksum_sha256: str = Field(
        ..., pattern=r"^[a-fA-F0-9]{64}$", description="SHA-256 checksum of the firmware."
    )

    # Minimum required firmware versions per target
    MIN_VERSIONS: ClassVar[dict[TargetDevice, str]] = {
        TargetDevice.TEENSY_41: "1.0.0",
        TargetDevice.LOIHI_2: "2.0.0",
        TargetDevice.AKIDA: "1.2.0",
        TargetDevice.SPINNAKER: "2.0.0",
        TargetDevice.BRAINSCALES: "2.0.0",
        TargetDevice.LAVA: "1.0.0",
        TargetDevice.NEUROML: "1.0.0",
        TargetDevice.PYNQ_Z2: "1.0.0",
    }

    @model_validator(mode="after")
    def validate_target_compatibility(self) -> "DeploymentManifest":
        """
        Enforce invariant: firmware version must be compatible with the target device.
        For this contract, we ensure the version meets the minimum required for the target.
        """
        min_v = self.MIN_VERSIONS.get(self.target_device)
        if min_v:
            # Simple SemVer comparison (splitting by dot)
            current = [int(x) for x in self.firmware_version.split(".")]
            required = [int(x) for x in min_v.split(".")]
            if current < required:
                raise ValueError(
                    f"Firmware version {self.firmware_version} is incompatible with "
                    f"{self.target_device.value}. Minimum version required: {min_v}."
                )
        return self
