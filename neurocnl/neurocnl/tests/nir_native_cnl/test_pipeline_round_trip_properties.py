"""Property test: pipeline config round-trips through render/parse.

For any random `PipelineConfig`, rendering it to CNL and parsing that
text back must reproduce the same `PipelineConfig`. Companion to the
existing round-trip properties for `nir.NIRGraph` in
`test_round_trip_properties.py`.

_Validates: pipeline CNL grammar extension (Train/Evaluate/Export)_
"""

from __future__ import annotations

from hypothesis import given, settings

from neurocnl.nir_cnl.parser import NIR_CNL_Parser
from neurocnl.nir_cnl.pipeline_config import PipelineConfig, extract_pipeline_config
from neurocnl.nir_cnl.renderer import NIR_Renderer

from ._strategies import pipeline_config_strategy


@given(cfg=pipeline_config_strategy())
@settings(max_examples=100, deadline=None)
def test_property_14_pipeline_config_round_trip_identity(cfg: PipelineConfig) -> None:
    text = NIR_Renderer().render_pipeline_config(cfg)
    if text == "":
        # An empty PipelineConfig renders to "" and there is nothing to
        # parse back — this is the degenerate case of the property.
        assert cfg == PipelineConfig()
        return
    records = NIR_CNL_Parser().parse(text)
    assert extract_pipeline_config(records) == cfg
