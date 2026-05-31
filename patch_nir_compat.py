import re

with open("/Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/neurocnl/_nir_compat.py", "r") as f:
    content = f.read()

# Add NIR_HAS_INPUT_METADATA and NIR_HAS_OUTPUT_METADATA
insert_params = """
_NIR_INPUT_PARAMS: frozenset[str] = frozenset(
    inspect.signature(nir.Input).parameters.keys()
)
_NIR_OUTPUT_PARAMS: frozenset[str] = frozenset(
    inspect.signature(nir.Output).parameters.keys()
)

#: ``True`` when the installed nir build accepts the ``metadata`` kwarg on Input nodes.
NIR_HAS_INPUT_METADATA: bool = "metadata" in _NIR_INPUT_PARAMS

#: ``True`` when the installed nir build accepts the ``metadata`` kwarg on Output nodes.
NIR_HAS_OUTPUT_METADATA: bool = "metadata" in _NIR_OUTPUT_PARAMS
"""

content = content.replace(
    "NIR_HAS_V_RESET: bool = \"v_reset\" in _NIR_LIF_PARAMS",
    "NIR_HAS_V_RESET: bool = \"v_reset\" in _NIR_LIF_PARAMS\n" + insert_params
)

insert_funcs = """

# ---------------------------------------------------------------------------
# Helper: build nir.Input with optional metadata
# ---------------------------------------------------------------------------


def make_nir_input(
    *,
    input_type: dict[str, np.ndarray],
    **kwargs: Any,
) -> nir.Input:
    \"\"\"Construct a :class:`nir.Input`, omitting ``metadata`` on older nir builds.\"\"\"
    if "metadata" in kwargs and not NIR_HAS_INPUT_METADATA:
        kwargs.pop("metadata")
    return nir.Input(input_type=input_type, **kwargs)


# ---------------------------------------------------------------------------
# Helper: build nir.Output with optional metadata
# ---------------------------------------------------------------------------


def make_nir_output(
    *,
    output_type: dict[str, np.ndarray],
    **kwargs: Any,
) -> nir.Output:
    \"\"\"Construct a :class:`nir.Output`, omitting ``metadata`` on older nir builds.\"\"\"
    if "metadata" in kwargs and not NIR_HAS_OUTPUT_METADATA:
        kwargs.pop("metadata")
    return nir.Output(output_type=output_type, **kwargs)
"""

content = content + insert_funcs

with open("/Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/neurocnl/_nir_compat.py", "w") as f:
    f.write(content)
