import json
import logging
import sys
from datetime import datetime, UTC
from typing import Any


class JSONFormatter(logging.Formatter):
    """Custom logging formatter that outputs JSON."""

    def format(self, record: logging.LogRecord) -> str:
        """Format the log record as a JSON string.

        Args:
            record: The logging record to format.

        Returns:
            str: The JSON-formatted log record.
        """
        log_record: dict[str, Any] = {
            "timestamp": datetime.fromtimestamp(record.created, tz=UTC).isoformat(),
            "level": record.levelname,
            "message": record.getMessage(),
            "logger": record.name,
        }

        # Add extra fields if they exist
        if hasattr(record, "request_id"):
            log_record["request_id"] = record.request_id

        if record.exc_info:
            log_record["exception"] = self.formatException(record.exc_info)

        # Include other attributes passed via 'extra'
        standard_attrs = {
            "args",
            "asctime",
            "created",
            "exc_info",
            "exc_text",
            "filename",
            "funcName",
            "levelname",
            "levelno",
            "lineno",
            "module",
            "msecs",
            "message",
            "msg",
            "name",
            "pathname",
            "process",
            "processName",
            "relativeCreated",
            "stack_info",
            "thread",
            "threadName",
        }
        for key, value in record.__dict__.items():
            if key not in standard_attrs and not key.startswith("_"):
                log_record[key] = value

        return json.dumps(log_record)


def setup_logging() -> None:
    """Configure the root logger and uvicorn loggers to use JSON formatting."""
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JSONFormatter())

    # Configure root logger
    root_logger = logging.getLogger()
    root_logger.setLevel(logging.INFO)
    for h in root_logger.handlers[:]:
        root_logger.removeHandler(h)
    root_logger.addHandler(handler)

    # Configure uvicorn loggers to use the same handler
    for logger_name in ("uvicorn", "uvicorn.access", "uvicorn.error"):
        logger = logging.getLogger(logger_name)
        logger.handlers = [handler]
        logger.propagate = False
