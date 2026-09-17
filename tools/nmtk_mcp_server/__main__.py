from __future__ import annotations

import argparse
from pathlib import Path

from .mcp_runtime import run
from .runtime_config import RuntimeConfig


def main() -> None:
    parser = argparse.ArgumentParser(description="Run the NMTK MCP server.")
    parser.add_argument(
        "--transport",
        choices=("stdio", "streamable-http"),
        default=None,
        help="MCP transport to run. Defaults to NMTK_MCP_TRANSPORT or stdio.",
    )
    parser.add_argument("--repo-root", type=Path, default=None)
    parser.add_argument("--suite-api-url", default=None)
    parser.add_argument("--launcher-url", default=None)
    parser.add_argument("--state-path", type=Path, default=None)
    parser.add_argument("--host", default=None)
    parser.add_argument("--port", type=int, default=None)
    args = parser.parse_args()

    config = RuntimeConfig.from_env()
    config = config.model_copy(
        update={
            key: value
            for key, value in {
                "repo_root": args.repo_root,
                "suite_api_base_url": args.suite_api_url,
                "launcher_base_url": args.launcher_url,
                "state_path": args.state_path,
                "transport": args.transport,
                "host": args.host,
                "port": args.port,
            }.items()
            if value is not None
        }
    )
    run(config)


if __name__ == "__main__":
    main()
