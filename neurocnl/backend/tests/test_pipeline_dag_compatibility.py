"""Compatibility coverage for backend pipeline-DAG imports."""

from backend.app.schemas import pipeline_dag
from neurocnl.training import dag_schema


def test_legacy_pipeline_dag_reexports_node_type_vocabulary() -> None:
    """Suite API notebook routes retain their legacy schema import contract."""
    assert pipeline_dag._LOADER_TYPES is dag_schema._LOADER_TYPES
    assert pipeline_dag._LOSS_TYPES is dag_schema._LOSS_TYPES
    assert pipeline_dag._OPTIMISER_TYPES is dag_schema._OPTIMISER_TYPES
    assert pipeline_dag._SCHEDULER_TYPES is dag_schema._SCHEDULER_TYPES
