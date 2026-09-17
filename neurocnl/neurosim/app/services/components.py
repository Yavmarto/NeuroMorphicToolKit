"""Shared utility for loading component definitions."""

import json
import logging
import os
import pathlib as _pathlib
from dataclasses import dataclass, field
from pathlib import Path
from typing import TYPE_CHECKING, Any, cast

from watchdog.events import FileSystemEvent, FileSystemEventHandler
from watchdog.observers import Observer
from watchdog.observers.api import BaseObserver

from ..schemas.components import ComponentBlock

COMPONENTS_DIR = Path(__file__).parent.parent.parent / "components"

CUSTOM_NODES_DIR: _pathlib.Path = _pathlib.Path.home() / ".nmtk" / "custom_nodes"

logger = logging.getLogger(__name__)

if TYPE_CHECKING:
    _FileSystemEventHandlerBase = object
else:
    _FileSystemEventHandlerBase = cast("type[object]", FileSystemEventHandler)


@dataclass
class _ComponentState:
    """Encapsulates the global state for the component system."""

    cache: dict[str, ComponentBlock] | None = None
    observer: BaseObserver | None = None
    warned_invalid_paths: set[str] = field(default_factory=set)


# Singleton state instance
_state = _ComponentState()


def __getattr__(name: str) -> Any:
    """Redirect access for deprecated global variables to the new state object."""
    if name == "_component_cache":
        return _state.cache
    if name == "_observer":
        return _state.observer
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")


class ComponentCacheHandler(_FileSystemEventHandlerBase):
    """Handler for component file system events."""

    def on_modified(self, event: FileSystemEvent) -> None:
        src = str(event.src_path)
        if not event.is_directory and (src.endswith((".json", ".py"))):
            logger.info("Component file modified: %s", event.src_path)
            _invalidate_cache()

    def on_created(self, event: FileSystemEvent) -> None:
        src = str(event.src_path)
        if not event.is_directory and (src.endswith((".json", ".py"))):
            logger.info("Component file created: %s", event.src_path)
            _invalidate_cache()

    def on_deleted(self, event: FileSystemEvent) -> None:
        src = str(event.src_path)
        if not event.is_directory and (src.endswith((".json", ".py"))):
            logger.info("Component file deleted: %s", event.src_path)
            _invalidate_cache()

    def on_moved(self, event: FileSystemEvent) -> None:
        src = str(event.src_path)
        dest = str(getattr(event, "dest_path", ""))
        if not event.is_directory and (
            src.endswith((".json", ".py")) or dest.endswith((".json", ".py"))
        ):
            logger.info("Component file moved: %s -> %s", event.src_path, dest)
            _invalidate_cache()


def _invalidate_cache() -> None:
    """Invalidate the component cache."""
    _state.cache = None
    _state.warned_invalid_paths.clear()


def _warn_invalid_manifest(filepath: Path, reason: str) -> None:
    """Log a single warning for a skipped invalid manifest path."""
    path_str = str(filepath)
    if path_str in _state.warned_invalid_paths:
        return

    _state.warned_invalid_paths.add(path_str)
    logger.warning("Skipping component manifest %s: %s", filepath, reason)


def _load_all_components_from_disk() -> dict[str, ComponentBlock]:
    """Read all component manifests from disk (JSON + custom Python nodes)."""
    components: dict[str, ComponentBlock] = {}
    if COMPONENTS_DIR.exists():
        for root, _, files in os.walk(COMPONENTS_DIR):
            for file in files:
                if file.endswith(".json"):
                    filepath = Path(root) / file
                    try:
                        with open(filepath, encoding="utf-8") as f:
                            raw_text = f.read()
                    except OSError as exc:
                        _warn_invalid_manifest(filepath, f"could not read file ({exc})")
                        continue

                    if not raw_text.strip():
                        _warn_invalid_manifest(filepath, "empty placeholder file")
                        continue

                    try:
                        data = json.loads(raw_text)
                    except json.JSONDecodeError as exc:
                        _warn_invalid_manifest(filepath, f"invalid JSON ({exc.msg})")
                        continue

                    try:
                        block = ComponentBlock(**data)
                    except Exception as exc:
                        _warn_invalid_manifest(filepath, f"schema validation failed ({exc})")
                        continue

                    components[block.id] = block

    # Merge custom Python nodes (custom nodes can override JSON if same id)
    custom = _load_custom_nodes_from_disk()
    components.update(custom)
    return components


def _load_custom_nodes_from_disk() -> dict[str, ComponentBlock]:
    """Load all CustomNode .py files from CUSTOM_NODES_DIR."""
    components: dict[str, ComponentBlock] = {}
    if not CUSTOM_NODES_DIR.exists():
        return components

    try:
        from nmtk_sdk.introspect import introspect_node
        from nmtk_sdk.loader import load_custom_node
        from nmtk_sdk.safety import scan_imports
    except ImportError:
        logger.debug("nmtk_sdk not available; skipping custom node loading")
        return components

    for py_file in sorted(CUSTOM_NODES_DIR.glob("*.py")):
        try:
            source = py_file.read_text(encoding="utf-8")
        except OSError as exc:
            logger.warning("Skipping custom node %s: could not read (%s)", py_file.name, exc)
            continue

        dangerous = scan_imports(source)
        if dangerous:
            logger.warning(
                "Custom node %s imports potentially dangerous modules: %s. "
                "Loading anyway — only use nodes from authors you trust.",
                py_file.name,
                ", ".join(set(dangerous)),
            )

        try:
            cls = load_custom_node(py_file)
            block = introspect_node(cls, source_path=str(py_file))
            components[block.id] = block
            logger.info("Loaded custom node '%s' from %s", block.name, py_file.name)
        except Exception as exc:
            logger.warning("Skipping custom node %s: %s", py_file.name, exc)

    return components


def _init_cache_and_watcher() -> None:
    """Initialize the cache and start the watchdog observer."""
    if _state.cache is None:
        _state.cache = _load_all_components_from_disk()

    if _state.observer is None:
        event_handler = ComponentCacheHandler()
        observer = Observer()
        if COMPONENTS_DIR.exists():
            cast("Any", observer).schedule(event_handler, str(COMPONENTS_DIR), recursive=True)
        if CUSTOM_NODES_DIR.exists():
            cast("Any", observer).schedule(event_handler, str(CUSTOM_NODES_DIR), recursive=False)
        cast("Any", observer).start()
        _state.observer = observer


def load_components() -> dict[str, ComponentBlock]:
    """Load all component manifests into a dict keyed by component id.

    Uses a cached dictionary that is automatically invalidated on file changes.

    Returns:
        Dict[str, ComponentBlock]: A dictionary mapping component IDs to their definitions.
    """
    if _state.cache is None:
        _init_cache_and_watcher()

    return _state.cache or {}


def shutdown_component_watcher() -> None:
    """Stop the watchdog observer."""
    if _state.observer is not None:
        cast("Any", _state.observer).stop()
        _state.observer.join()
        _state.observer = None
