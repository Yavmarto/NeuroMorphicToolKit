"""Internal intermediate representation for normalized CNL semantics."""

from .lowering import LoweringError, lower_to_ir
from .materializer import Materializer, MaterializerError
from .types import (
    BackendHintIR,
    ConnectionIR,
    LearningRuleIR,
    NetworkIR,
    PopulationIR,
    SourceProvenance,
    TimingDeclarationIR,
    normalize_identifier,
)

__all__ = [
    "SourceProvenance",
    "TimingDeclarationIR",
    "BackendHintIR",
    "PopulationIR",
    "ConnectionIR",
    "LearningRuleIR",
    "NetworkIR",
    "Materializer",
    "MaterializerError",
    "LoweringError",
    "lower_to_ir",
    "normalize_identifier",
]
