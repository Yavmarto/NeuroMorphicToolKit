"""neurochip domain.

The neurochip package is installed as a top-level package (pip install -e Neurochip/).
Its routers carry their own /api/neurochip/ prefix, so no additional prefix is needed
when mounting in suite_api.

Optional hardware integrations (Akida, Lava, PYNQ) are guarded with try/except
in router.py — suite_api starts cleanly on machines without those packages.
"""
