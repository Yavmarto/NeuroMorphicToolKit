from pydantic import BaseModel

from .canvas import CanvasGraph


class TemplateSummary(BaseModel):
    id: str
    name: str
    description: str
    thumbnail: str | None = None
    use_case: str


class StarterTemplate(TemplateSummary):
    graph: CanvasGraph
    cnl_spec: str
    version: str
