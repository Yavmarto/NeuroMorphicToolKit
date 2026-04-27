"""neurosense domain.

The neurosense package is installed as a top-level package (pip install -e Neurosense/).
Its routers carry no prefix themselves — the original main.py applies prefixes
at include_router time. We replicate that same configuration here.

Hardware routes (devices, stream, prophesee, pynq) require physical hardware.
They return 503 when hardware is absent — the existing behavior, unchanged.
"""
