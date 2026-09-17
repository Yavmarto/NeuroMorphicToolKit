"""Mock suite server for integration testing NeuroHub registry and metadata endpoints."""

import threading
import time
from typing import Any

import uvicorn
from fastapi import FastAPI

app = FastAPI()

# Stores for activity and status
activities: dict[str, list[dict[str, Any]]] = {
    "neurosim": [],
    "neurochip": [],
    "neurobench": [],
    "neurosense": [],
    "neurocnl": [],
}


@app.get("/health")
async def health() -> dict[str, str]:
    """Return a fixed healthy status using the real suite health route."""
    return {"status": "ok", "version": "1.0.0-mock"}


@app.get("/api/{app_name}/activity")
async def get_activity(
    app_name: str,
    since: str | None = None,
    limit: int = 50,
) -> list[dict[str, Any]]:
    """Return mock activity entries for the requested app."""
    return activities.get(app_name, [])[:limit]


@app.post("/api/neurocnl/validate")
async def validate_cnl() -> dict[str, Any]:
    """Return a successful mock validation response."""
    return {"status": "valid", "errors": []}


@app.post("/api/neurosim/preview")
async def neurosim_preview() -> dict[str, str]:
    """Return a mock NeuroSim preview response."""
    return {"status": "ok", "preview_url": "http://mock/preview/123"}


@app.post("/api/neurochip/quantize")
async def neurochip_quantize() -> dict[str, float | str]:
    """Return a mock NeuroChip quantization response."""
    return {"status": "success", "accuracy_loss": 0.01}


@app.post("/api/neurobench/benchmark")
async def neurobench_benchmark() -> dict[str, float | str]:
    """Return a mock NeuroBench benchmark response."""
    return {"status": "completed", "score": 0.95}


@app.post("/api/neurochip/deploy")
async def neurochip_deploy() -> dict[str, str]:
    """Return a mock NeuroChip deployment response."""
    return {"status": "deployed", "firmware_id": "fw_mock_1"}


def run_server(port: int = 8081) -> None:
    """Run the mock suite server on the given port."""
    uvicorn.run(app, host="127.0.0.1", port=port, log_level="error")


class MockSuiteServer:
    """Utility wrapper for starting the mock suite server in tests."""

    def __init__(self, port: int = 8081):
        """Initialize the mock suite server wrapper."""
        self.port = port
        self.thread: threading.Thread | None = None

    def start(self) -> None:
        """Start the mock suite server in a daemon thread."""
        self.thread = threading.Thread(target=run_server, args=(self.port,), daemon=True)
        if self.thread is not None:
            self.thread.start()
        # Give it a moment to start
        time.sleep(1)

    def stop(self) -> None:
        """Stop the mock suite server wrapper."""
        # Since it's a daemon thread, it will exit when the main process exits.
        # uvicorn doesn't have a very simple way to stop from a thread without more complexity.
        pass

    @property
    def base_url(self) -> str:
        """Return the base URL for the running mock suite server."""
        return f"http://127.0.0.1:{self.port}"


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Run Mock Suite Server")
    parser.add_argument("--port", type=int, default=8081, help="Port to run on")
    args = parser.parse_args()

    print(f"Starting Mock Suite Server on port {args.port}...")
    run_server(port=args.port)
