import json
import logging
from typing import Any


class JSONFormatter(logging.Formatter):
    """Custom JSON formatter for structured logging."""

    def format(self, record: logging.LogRecord) -> str:
        log_record: dict[str, Any] = {
            "timestamp": self.formatTime(record, self.datefmt),
            "level": record.levelname,
            "message": record.getMessage(),
            "logger": record.name,
        }

        # Check both record.__dict__ and any extra attributes
        request_id = getattr(record, "request_id", None)
        if request_id:
            log_record["request_id"] = request_id

        # Support other attributes that might be added to the record
        # but avoid standard ones
        standard_attrs = {
            "name",
            "msg",
            "args",
            "levelname",
            "levelno",
            "pathname",
            "filename",
            "module",
            "exc_info",
            "exc_text",
            "stack_info",
            "lineno",
            "funcName",
            "created",
            "msecs",
            "relativeCreated",
            "thread",
            "threadName",
            "processName",
            "process",
            "message",
            "timestamp",
        }
        for key, value in record.__dict__.items():
            if key not in standard_attrs and key not in {"extra_fields", "request_id"}:
                log_record[key] = value

        if record.exc_info:
            log_record["exception"] = self.formatException(record.exc_info)

        # Include extra fields passed via the 'extra' parameter
        if hasattr(record, "extra_fields"):
            log_record.update(record.extra_fields)

        return json.dumps(log_record, default=str)


def setup_logging(level: int = logging.INFO) -> None:
    """Configure the root logger with the JSON formatter."""
    handler = logging.StreamHandler()
    handler.setFormatter(JSONFormatter())

    root_logger = logging.getLogger()
    root_logger.setLevel(level)
    # Remove existing handlers to avoid duplicate logs
    for h in root_logger.handlers[:]:
        root_logger.removeHandler(h)
    root_logger.addHandler(handler)

    # Also configure uvicorn loggers if they exist
    for logger_name in ["uvicorn", "uvicorn.access", "uvicorn.error"]:
        logger = logging.getLogger(logger_name)
        logger.handlers = [handler]
        logger.propagate = False
