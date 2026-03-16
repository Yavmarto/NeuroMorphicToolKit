"""Sphinx configuration for neurocnl documentation."""

project = "neurocnl"
copyright = "2026, Neuro-space contributors"
author = "Neuro-space contributors"

extensions = [
    "sphinx.ext.autodoc",
    "sphinx.ext.napoleon",
    "sphinx.ext.viewcode",
    "sphinx.ext.intersphinx",
]

templates_path = ["_templates"]
exclude_patterns = ["_build"]

html_theme = "alabaster"

intersphinx_mapping = {
    "python": ("https://docs.python.org/3", None),
    "numpy": ("https://numpy.org/doc/stable/", None),
}

autodoc_member_order = "bysource"
napoleon_google_docstring = True
napoleon_numpy_docstring = True
