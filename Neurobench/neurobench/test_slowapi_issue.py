from fastapi import Request, Response
from pydantic import BaseModel
from slowapi import Limiter
from slowapi.util import get_remote_address

limiter = Limiter(key_func=get_remote_address)


class ResultsDiff(BaseModel):
    foo: str


@limiter.limit("5/minute")
def compare_results(request: Request, response: Response, a: str, b: str) -> ResultsDiff:
    return ResultsDiff(foo="bar")


def export_diff(request: Request, response: Response, a: str, b: str) -> Response:
    diff = compare_results(request, response, a, b)
    return Response(content="ok")


req = Request(
    {"type": "http", "method": "GET", "path": "/foo", "headers": [], "client": ("127.0.0.1", 8000)}
)
res = Response()
try:
    export_diff(req, res, "a", "b")
    print("SUCCESS")
except Exception as e:
    print(f"FAILED: {type(e).__name__}: {e}")
