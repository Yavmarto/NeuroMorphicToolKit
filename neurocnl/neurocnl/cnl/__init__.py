"""CNL parsing module — NIR-native Controlled Natural Language parser for neuromorphic specs."""

# The NIR-native parser is being rebuilt by task 6.1 of the nir-native-cnl
# spec.  Until that rebuild lands, ``neurocnl.nir_cnl.parser`` retains a
# dangling import of the deleted ``neurocnl.nir_cnl.grammar`` module, so
# importing it eagerly would break ``import neurocnl`` for every consumer
# of this package.  Re-export the new parser names lazily so this package
# imports cleanly during the transition, mirroring the pattern used in
# ``neurocnl.nir_cnl.__init__``.
try:
    from neurocnl.nir_cnl.parser import NIR_CNL_Parser, ParseError
except ImportError:  # pragma: no cover — parser rebuilt in task 6.1
    NIR_CNL_Parser = None  # type: ignore[assignment,misc]
    ParseError = None  # type: ignore[assignment,misc]

__all__ = ["NIR_CNL_Parser", "ParseError"]
