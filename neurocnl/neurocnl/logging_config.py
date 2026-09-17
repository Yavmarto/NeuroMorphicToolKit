import logging
import os
import sys
from pathlib import Path

import structlog
from structlog.typing import Processor


def setup_logging() -> None:
    """Initializes structlog with JSON or Console rendering.

    Logs are written to both stdout (console) and a rotating file under
    ``logs/neurocnl.log`` in the current working directory.  The log
    directory is created automatically if it does not exist.
    """

    log_format = os.environ.get("LOG_FORMAT", "text").lower()

    processors: list[Processor] = [
        structlog.contextvars.merge_contextvars,
        structlog.processors.add_log_level,
        structlog.processors.StackInfoRenderer(),
        structlog.dev.set_exc_info,
        structlog.processors.TimeStamper(fmt="iso"),
    ]

    if log_format == "json":
        processors.append(structlog.processors.format_exc_info)
        processors.append(structlog.processors.JSONRenderer())
    else:
        processors.append(structlog.dev.ConsoleRenderer())

    # ── File logging ─────────────────────────────────────────────────────────
    log_dir = Path(os.environ.get("NEUROCNL_LOG_DIR", "logs"))
    log_dir.mkdir(parents=True, exist_ok=True)
    log_file = log_dir / "neurocnl.log"

    # Create a standard-library file handler for structured logs
    file_handler = logging.FileHandler(str(log_file), encoding="utf-8")
    file_handler.setLevel(logging.DEBUG)

    # Use a plain formatter so structlog's rendered output goes straight to file
    file_formatter = logging.Formatter("%(message)s")
    file_handler.setFormatter(file_formatter)

    # Also keep stdout for container / terminal visibility
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setLevel(logging.DEBUG)
    console_formatter = logging.Formatter("%(message)s")
    console_handler.setFormatter(console_formatter)

    structlog.configure(
        processors=processors,
        logger_factory=structlog.stdlib.LoggerFactory(),
        wrapper_class=structlog.make_filtering_bound_logger(logging.DEBUG),
        cache_logger_on_first_use=True,
    )

    # Route standard logging through the handlers we configured
    root_logger = logging.getLogger()
    root_logger.setLevel(logging.DEBUG)
    root_logger.handlers = [console_handler, file_handler]

    # Optional: Route standard logging to structlog
    logging.basicConfig(
        format="%(message)s",
        handlers=[console_handler, file_handler],
        level=logging.DEBUG,
        force=True,
    )
