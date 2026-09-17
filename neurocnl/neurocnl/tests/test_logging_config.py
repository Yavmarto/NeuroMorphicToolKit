import logging
import os
from unittest.mock import patch

import structlog

from neurocnl.logging_config import setup_logging


def test_setup_logging_json() -> None:
    with (
        patch.dict(os.environ, {"LOG_FORMAT": "json"}),
        patch("structlog.configure") as mock_configure,
        patch("logging.basicConfig") as mock_basic_config,
    ):
        setup_logging()

        # Check if it was called
        mock_configure.assert_called_once()
        mock_basic_config.assert_called_once()

        # Check processors
        args, kwargs = mock_configure.call_args
        processors = kwargs.get("processors")

        assert structlog.processors.format_exc_info in processors
        # Ensure JSONRenderer is used
        assert any(isinstance(p, structlog.processors.JSONRenderer) for p in processors)

        # Check standard logging config
        basic_args, basic_kwargs = mock_basic_config.call_args
        assert basic_kwargs.get("format") == "%(message)s"
        assert basic_kwargs.get("level") == logging.DEBUG
        handlers = basic_kwargs.get("handlers")
        assert handlers is not None
        assert len(handlers) == 2
        assert any(isinstance(h, logging.StreamHandler) for h in handlers)
        assert any(isinstance(h, logging.FileHandler) for h in handlers)


def test_setup_logging_text() -> None:
    with (
        patch.dict(os.environ, {"LOG_FORMAT": "text"}),
        patch("structlog.configure") as mock_configure,
        patch("logging.basicConfig") as mock_basic_config,
    ):
        setup_logging()

        # Check if it was called
        mock_configure.assert_called_once()
        mock_basic_config.assert_called_once()

        # Check processors
        args, kwargs = mock_configure.call_args
        processors = kwargs.get("processors")

        # Ensure ConsoleRenderer is used
        assert any(isinstance(p, structlog.dev.ConsoleRenderer) for p in processors)


def test_setup_logging_default_text() -> None:
    # Should default to text if not set
    # Create a fresh dict without LOG_FORMAT to mock os.environ
    env_copy = dict(os.environ)
    env_copy.pop("LOG_FORMAT", None)
    with (
        patch.dict(os.environ, env_copy, clear=True),
        patch("structlog.configure") as mock_configure,
        patch("logging.basicConfig") as mock_basic_config,
    ):
        setup_logging()

        # Check processors
        args, kwargs = mock_configure.call_args
        processors = kwargs.get("processors")

        # Ensure ConsoleRenderer is used by default
        assert any(isinstance(p, structlog.dev.ConsoleRenderer) for p in processors)
