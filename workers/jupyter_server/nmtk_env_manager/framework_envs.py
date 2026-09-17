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
        "packages": [],  # snntorch + torch already in base image
    },
    {
        "slug": "nmtk-nengo",
        "display": "Python (Nengo)",
        "targets": ["nengo"],
        "packages": [],  # nengo already in base image
    },
    {
        "slug": "nmtk-rockpool",
        "display": "Python (Rockpool)",
        "targets": ["rockpool"],
        "packages": [],  # rockpool already in base image
    },
    {
        "slug": "nmtk-sinabs",
        "display": "Python (Sinabs)",
        "targets": ["sinabs"],
        "packages": [],  # sinabs + torch already in base image
    },
    {
        "slug": "nmtk-brian2",
        "display": "Python (Brian2)",
        "targets": ["brian2"],
        "packages": [],  # brian2 now in base image
    },
    {
        "slug": "nmtk-lava",
        "display": "Python (Lava)",
        "targets": ["lava_sim", "lava"],
        "packages": ["lava-nc"],  # fallback: base image skips lava-nc on Python >=3.11
    },
    {
        "slug": "nmtk-pynn",
        "display": "Python (PyNN / SpiNNaker)",
        "targets": ["pynn"],
        "packages": [],  # PyNN now in base image
    },
    {
        "slug": "nmtk-akida",
        "display": "Python (Akida)",
        "targets": ["akida"],
        "packages": [],  # akida now in base image; cnn2snn removed (unused in kernel)
    },
]

# Flat lookup: notebook target string → kernel slug.
# Targets absent from this dict (sc_neurocore_*, generic) use the base kernel.
TARGET_TO_KERNEL: dict[str, str] = {
    target: env["slug"]
    for env in FRAMEWORK_ENVS
    for target in env["targets"]
}
