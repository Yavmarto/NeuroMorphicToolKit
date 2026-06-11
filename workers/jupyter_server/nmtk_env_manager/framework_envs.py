"""Static registry of preconfigured per-framework Jupyter kernel environments.

Each entry maps to a ``--system-site-packages`` clone of the immutable base
kernel (``neurocnl``) that is provisioned automatically at Jupyter startup.

Targets not listed here fall back to the base ``neurocnl`` kernel.
"""
from __future__ import annotations

FRAMEWORK_ENVS: list[dict] = [
    {
        "slug": "nmtk-snntorch",
        "display": "Python (snnTorch)",
        "targets": ["snntorch_sim"],
    },
    {
        "slug": "nmtk-nengo",
        "display": "Python (Nengo)",
        "targets": ["nengo"],
    },
    {
        "slug": "nmtk-rockpool",
        "display": "Python (Rockpool)",
        "targets": ["rockpool"],
    },
    {
        "slug": "nmtk-sinabs",
        "display": "Python (Sinabs)",
        "targets": ["sinabs"],
    },
    {
        "slug": "nmtk-brian2",
        "display": "Python (Brian2)",
        "targets": ["brian2"],
    },
    {
        "slug": "nmtk-lava",
        "display": "Python (Lava)",
        "targets": ["lava_sim", "lava"],
    },
    {
        "slug": "nmtk-pynn",
        "display": "Python (PyNN / SpiNNaker)",
        "targets": ["pynn"],
    },
    {
        "slug": "nmtk-akida",
        "display": "Python (Akida)",
        "targets": ["akida"],
    },
]

# Flat lookup: notebook target string → kernel slug.
# Targets absent from this dict (sc_neurocore_*, generic) use the base kernel.
TARGET_TO_KERNEL: dict[str, str] = {
    target: env["slug"]
    for env in FRAMEWORK_ENVS
    for target in env["targets"]
}
