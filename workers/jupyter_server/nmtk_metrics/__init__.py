"""Prometheus /metrics for the Jupyter Server worker."""

from __future__ import annotations

__version__ = "0.1.0"


def _jupyter_server_extension_points() -> list[dict]:
    return [{"module": "nmtk_metrics"}]


def _load_jupyter_server_extension(serverapp) -> None:
    from jupyter_server.auth.decorator import allow_unauthenticated
    from jupyter_server.base.handlers import APIHandler

    from nmtk.metrics_core import metrics_body, metrics_content_type, record_http_request

    class MetricsHandler(APIHandler):
        @allow_unauthenticated
        def get(self) -> None:
            self.set_header("Content-Type", metrics_content_type())
            self.write(metrics_body())

    serverapp.web_app.add_handlers(".*$", [(r"/metrics", MetricsHandler)])

    original_log_function = serverapp.web_app.settings.get("log_function")

    def metrics_log_function(handler) -> None:
        request = handler.request
        record_http_request(
            method=request.method,
            endpoint=request.path,
            status_code=handler.get_status(),
            latency_seconds=request.request_time(),
        )
        if callable(original_log_function):
            original_log_function(handler)

    serverapp.web_app.settings["log_function"] = metrics_log_function


load_jupyter_server_extension = _load_jupyter_server_extension
