import hashlib
import json
import logging
import os
from pathlib import Path
from typing import Any

from ..schemas.estimation import NetworkInput

logger = logging.getLogger(__name__)

# Resolve from env (NEUROCHIP_CACHE_DIR) with a home-relative default. The
# previous CWD-relative ".cache/compilation" crashed on import inside Docker,
# where WORKDIR=/repo is intentionally root-owned and the runtime user can't
# create subdirs there.
_DEFAULT_CACHE_DIR = Path.home() / ".cache" / "neurochip" / "compilation"
CACHE_DIR = Path(os.environ.get("NEUROCHIP_CACHE_DIR", str(_DEFAULT_CACHE_DIR)))


class CacheManager:
    def __init__(self, cache_dir: Path = CACHE_DIR) -> None:
        self.cache_dir = cache_dir

    def _generate_key(
        self,
        network: NetworkInput,
        generator_name: str,
        **kwargs: Any,
    ) -> str:
        # Create a stable representation of the network input
        network_data = network.model_dump()
        # Ensure consistent ordering for hashing
        network_json = json.dumps(network_data, sort_keys=True)

        # Combine with generator name and other parameters
        params_json = json.dumps(kwargs, sort_keys=True)

        combined = f"{generator_name}:{network_json}:{params_json}"
        return hashlib.sha256(combined.encode()).hexdigest()

    def get_cached_artifact(
        self,
        network: NetworkInput,
        generator_name: str,
        **kwargs: Any,
    ) -> bytes | None:
        key = self._generate_key(network, generator_name, **kwargs)
        cache_file = self.cache_dir / f"{key}.zip"

        try:
            if cache_file.exists():
                return cache_file.read_bytes()
        except OSError as exc:
            logger.warning("Neurochip cache read unavailable at %s: %s", cache_file, exc)
        return None

    def cache_artifact(
        self,
        network: NetworkInput,
        generator_name: str,
        artifact: bytes,
        **kwargs: Any,
    ) -> None:
        key = self._generate_key(network, generator_name, **kwargs)
        cache_file = self.cache_dir / f"{key}.zip"
        try:
            self.cache_dir.mkdir(parents=True, exist_ok=True)
            cache_file.write_bytes(artifact)
        except OSError as exc:
            logger.warning("Neurochip cache write unavailable at %s: %s", cache_file, exc)


cache_manager = CacheManager()
