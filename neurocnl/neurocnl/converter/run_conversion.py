"""CLI for neurocnl Model Converter.

Allows converting models between Nengo, Lava, PyNN, and Brian2 via NIR.
"""

import argparse
import importlib.util
import os
import sys
import types

import structlog

logger = structlog.get_logger(__name__)

from neurocnl.converter.brian2_io import Brian2IO
from neurocnl.converter.lava_io import LavaIO
from neurocnl.converter.nengo_io import NengoIO
from neurocnl.converter.pivot import ModelConverter
from neurocnl.converter.pynn_io import PyNNIO


def load_module_from_file(filepath: str) -> types.ModuleType | None:
    """Safely load a Python module from a file path."""
    module_name = os.path.splitext(os.path.basename(filepath))[0]
    spec = importlib.util.spec_from_file_location(module_name, filepath)
    if spec is None or spec.loader is None:
        return None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main() -> None:
    parser = argparse.ArgumentParser(description="NeuroCNL Model Converter (NIR-based)")
    parser.add_argument("source_file", help="Path to the source model file (.py)")
    parser.add_argument(
        "--source-fw",
        required=True,
        choices=["nengo", "lava", "pynn", "brian2"],
        help="Source framework",
    )
    parser.add_argument(
        "--target-fw",
        required=True,
        choices=["nengo", "lava", "pynn", "brian2"],
        help="Target framework",
    )
    parser.add_argument("--output", "-o", help="Output file path")
    parser.add_argument(
        "--pynn-backend", default="spiNNaker", help="PyNN backend (default: spiNNaker)"
    )

    args = parser.parse_args()

    # Initialize converter
    converter = ModelConverter()
    converter.register_framework("nengo", NengoIO())
    converter.register_framework("lava", LavaIO())
    converter.register_framework("pynn", PyNNIO())
    converter.register_framework("brian2", Brian2IO())

    # Load source model
    try:
        module = load_module_from_file(args.source_file)
        if module is None:
            logger.error("module_load_failed", source_file=args.source_file)
            sys.exit(1)

        # Look for typical model variable names
        source_model = (
            getattr(module, "model", None)
            or getattr(module, "net", None)
            or getattr(module, "network", None)
            or getattr(module, "objs", None)
        )

        if source_model is None:
            logger.error("model_variable_not_found", source_file=args.source_file)
            sys.exit(1)
    except Exception as e:
        logger.error("source_file_load_error", error=str(e))
        sys.exit(1)

    # Perform conversion
    logger.info("starting_conversion", source_fw=args.source_fw, target_fw=args.target_fw)
    try:
        kwargs = {}
        if args.target_fw == "pynn":
            kwargs["backend"] = args.pynn_backend

        result = converter.convert(source_model, args.source_fw, args.target_fw, **kwargs)
    except Exception as e:
        logger.error("conversion_failed", error=str(e))
        import traceback

        traceback.print_exc()
        sys.exit(1)

    # Output result
    if isinstance(result, str):
        if args.output:
            with open(args.output, "w") as f:
                f.write(result)
            logger.info("output_saved", path=args.output)
        else:
            logger.info("conversion_result", content=result)
    else:
        logger.info("conversion_produced_object", type=str(type(result)))
        if args.output:
            logger.warning("file_output_not_implemented", type=str(type(result)))

    # Show warnings
    if converter.warnings:
        for w in converter.warnings:
            logger.warning("conversion_warning", message=w)


if __name__ == "__main__":
    main()
