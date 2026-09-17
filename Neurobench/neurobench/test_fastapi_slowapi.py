from fastapi import APIRouter, FastAPI, Request, Response
from fastapi.testclient import TestClient
from pydantic import BaseModel
from slowapi import Limiter
from slowapi.util import get_remote_address

limiter = Limiter(key_func=get_remote_address)


class ResultsDiff(BaseModel):
    foo: str


app = FastAPI()
app.state.limiter = limiter

router = APIRouter()


@router.get("/compare")
@limiter.limit("5/minute")
def compare_results(request: Request, response: Response, a: str, b: str) -> ResultsDiff:
    return ResultsDiff(foo="bar")


@router.get("/export")
def export_diff(request: Request, response: Response, a: str, b: str) -> Response:
    print("export_diff response type:", type(response))
    diff = compare_results(request, response, a, b)
    return Response(content="ok")


app.include_router(router)

client = TestClient(app)
res = client.get("/export?a=1&b=2")
print("Status:", res.status_code)
print(res.text)
