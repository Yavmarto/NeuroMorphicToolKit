"""Run the root launcher control service."""

import sys
from importlib import import_module
from pathlib import Path


def main() -> int:
    repo_root = Path(__file__).resolve().parents[1]
    if str(repo_root) not in sys.path:
        sys.path.insert(0, str(repo_root))

    launcher_main = import_module("nmtk.launcher_control.server").main
    return launcher_main()


if __name__ == "__main__":
    raise SystemExit(main())
