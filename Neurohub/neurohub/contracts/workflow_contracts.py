"""Pydantic contracts for workflows in NeuroHub."""

from typing import Any, Literal

from pydantic import BaseModel, model_validator


class ContractWorkflowStep(BaseModel):
    """Contract for a single workflow step."""

    id: str
    depends_on: list[str] = []


class WorkflowDefinition(BaseModel):
    """Contract for workflow definition (basic DAG)."""

    steps: list[ContractWorkflowStep]
    execution_order: list[str]

    @model_validator(mode="after")
    def validate_references(self) -> "WorkflowDefinition":
        """Validate that all step references resolve."""
        step_ids = {step.id for step in self.steps}
        for step in self.steps:
            for dep in step.depends_on:
                if dep not in step_ids:
                    raise ValueError(f"Dependency step reference not found: {dep}")

        for order_id in self.execution_order:
            if order_id not in step_ids:
                raise ValueError(f"Execution order step reference not found: {order_id}")

        return self

    @model_validator(mode="after")
    def validate_no_cycles(self) -> "WorkflowDefinition":
        """Validate that the workflow graph is a DAG (no cycles)."""
        adj = {step.id: step.depends_on for step in self.steps}
        visited = set()
        path = set()

        def has_cycle(v: str) -> bool:
            visited.add(v)
            path.add(v)
            for neighbor in adj.get(v, []):
                if neighbor not in visited:
                    if has_cycle(neighbor):
                        return True
                elif neighbor in path:
                    return True
            path.remove(v)
            return False

        for step_id in adj:
            if step_id not in visited:
                if has_cycle(step_id):
                    raise ValueError("Workflow graph contains cycles")

        return self


class WorkflowStep(BaseModel):
    """Detailed contract for a single step within a workflow template."""

    id: str
    name: str  # e.g., "Validate CNL Spec"
    app: str  # e.g., "neurocnl", "neurochip", "neurobench"
    endpoint: str  # e.g., "/api/neurocnl/validate"
    method: Literal["GET", "POST"]
    parameters: dict[str, Any]  # Static params; dynamic params injected from project context
    success_criteria: str  # e.g., "status == 'valid'" or "accuracy > 0.90"
    on_failure: Literal["halt", "warn", "skip"]
    depends_on: list[str] = []
    timeout_seconds: int = 300
    retries: int = 0
    retry_delay_seconds: int = 60


class WorkflowTemplate(BaseModel):
    """Detailed contract for a reusable workflow template (full DAG)."""

    id: str
    name: str  # e.g., "Full Validation Pipeline"
    description: str
    steps: list[WorkflowStep]
    builtin: bool
    schedule: str | None = None

    @model_validator(mode="after")
    def validate_workflow_dag(self) -> "WorkflowTemplate":
        """Validate that the workflow template defines a valid DAG."""
        step_ids = {step.id for step in self.steps}
        adj = {step.id: step.depends_on for step in self.steps}

        # 1. Validate references
        for step in self.steps:
            for dep in step.depends_on:
                if dep not in step_ids:
                    raise ValueError(f"Dependency step reference not found: {dep}")

        # 2. Validate no cycles
        visited = set()
        path = set()

        def has_cycle(v: str) -> bool:
            visited.add(v)
            path.add(v)
            for neighbor in adj.get(v, []):
                if neighbor not in visited:
                    if has_cycle(neighbor):
                        return True
                elif neighbor in path:
                    return True
            path.remove(v)
            return False

        for step_id in adj:
            if step_id not in visited:
                if has_cycle(step_id):
                    raise ValueError(f"Workflow template '{self.id}' contains cycles")

        return self

    @model_validator(mode="after")
    def validate_no_isolated_steps(self) -> "WorkflowTemplate":
        """Validate that there are no isolated steps (except if only one step)."""
        if len(self.steps) <= 1:
            return self

        step_ids = {step.id for step in self.steps}
        referenced_as_dep = {dep for step in self.steps for dep in step.depends_on}
        has_deps = {step.id for step in self.steps if step.depends_on}

        for step_id in step_ids:
            if step_id not in referenced_as_dep and step_id not in has_deps:
                # This step is isolated
                msg = f"Step '{step_id}' is isolated (no dependencies and not a dependency)"
                raise ValueError(msg)

        return self
