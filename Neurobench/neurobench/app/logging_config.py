import json
import logging
import sys
from contextvars import ContextVar
from typing import Any

# Context variable to store the request ID for the current task/thread
request_id_ctx: ContextVar[str | None] = ContextVar("request_id", default=None)


class StructuredFormatter(logging.Formatter):
    """Formatter that outputs JSON-structured logs."""

    def format(self, record: logging.LogRecord) -> str:
        """Format the log record as a JSON string.

        Args:
            record (logging.LogRecord): The log record to format.

        Returns:
            str: The JSON-formatted log string.
        """
        log_record: dict[str, Any] = {
            "timestamp": self.formatTime(record, self.datefmt),
            "level": record.levelname,
            "name": record.name,
            "message": record.getMessage(),
            "module": record.module,
            "funcName": record.funcName,
            "line": record.lineno,
        }

        # Pull request_id from context if not explicitly in the record
        rid = getattr(record, "request_id", request_id_ctx.get())
        if rid:
            log_record["request_id"] = rid

        # Include any extra attributes passed to the log call (flattened)
        # We skip standard LogRecord attributes
        standard_attrs = {
            "args",
            "asctime",
            "created",
            "exc_info",
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
            "request_id",
        }
        for key, value in record.__dict__.items():
            if key not in standard_attrs and not key.startswith("_"):
                log_record[key] = value

        return json.dumps(log_record)


def setup_logging(level: int = logging.INFO) -> None:
    """Sets up the root logger with a structured JSON formatter.

    Args:
        level (int): The logging level to set. Defaults to logging.INFO.
    """
    root_logger = logging.getLogger()
    root_logger.setLevel(level)

    # Remove existing handlers to prevent duplicate or unstructured output
    for handler in root_logger.handlers[:]:
        root_logger.removeHandler(handler)

    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(StructuredFormatter())
    root_logger.addHandler(handler)
