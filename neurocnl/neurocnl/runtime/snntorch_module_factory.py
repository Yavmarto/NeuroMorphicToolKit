"""Shared factory for constructing ``snntorch.Synaptic``/``snntorch.RSynaptic`` modules.

Both call sites below need to turn a CNL-internal :class:`~neurocnl.runtime.cnl_nodes.Synaptic`
or :class:`~neurocnl.runtime.cnl_nodes.RSynaptic` node into a real ``snntorch`` module with
identical alpha/beta/threshold/reset-mechanism/bias/recurrent-weight handling:

- :mod:`neurocnl.runtime.snntorch_simulator` — fixed-weight, inference-only preview.  It calls
  this factory and then explicitly freezes the returned module's parameters
  (``requires_grad_(False)``) itself, since freezing is specific to the *preview* use case.
- :mod:`neurocnl.training.snntorch_adapter` — the trainable recurrent model builder (this is the
  higher-risk path: parameters must stay trainable so surrogate-gradient descent can update them).

This module exists so the two call sites cannot silently drift apart (e.g. one honouring
``use_bias`` and the other not).  ``torch``/``snntorch`` are always injected by the caller rather
than imported at module level, matching the rest of the codebase's "optional heavy dependency"
convention.
"""

from __future__ import annotations

from typing import Any

import numpy as np

from neurocnl.runtime.cnl_nodes import RSynaptic, Synaptic


def build_synaptic_module(
    node: Synaptic | RSynaptic,
    snntorch: Any,
    torch: Any,
    *,
    spike_grad: Any = None,
) -> Any:
    """Construct an ``snntorch.Synaptic``/``snntorch.RSynaptic`` module from a CNL node.

    Parameters
    ----------
    node : Synaptic | RSynaptic
        The CNL-internal neuron node (see ``neurocnl.runtime.cnl_nodes``).
    snntorch : module
        The ``snntorch`` module, injected to avoid a hard import at module load time.
    torch : module
        The ``torch`` module, injected for the same reason.  Only used for the
        ``torch.no_grad()``/``torch.tensor()`` calls needed to copy in a pretrained
        recurrent weight matrix (see below) — this is an in-place parameter
        initialisation, not a statement about whether the returned module is trainable.
    spike_grad : Any, optional
        A surrogate-gradient function instance (e.g.
        ``snntorch.surrogate.fast_sigmoid(slope=5)``), forwarded to the constructed
        module.  Only affects the backward pass — forward output (the thresholded
        spike train) is identical regardless of which surrogate is chosen — so the
        fixed-weight preview simulator (which never calls ``.backward()``) can
        safely omit it and get snnTorch's default surrogate.  The trainable path
        must pass the notebook's ``fast_sigmoid(slope=...)`` here to match the
        reference training dynamics; leaving this ``None`` would silently fall
        back to snnTorch's own default surrogate (``atan()``) instead.

    Returns
    -------
    Any
        A constructed ``snntorch.Synaptic`` (for a :class:`Synaptic` node) or
        ``snntorch.RSynaptic`` (for an :class:`RSynaptic` node) instance.  Parameters are
        left trainable (``requires_grad=True``, the PyTorch default) in every case —
        callers that need an inference-only, frozen copy (the fixed-weight preview
        simulator) must freeze the returned module's parameters themselves after calling
        this function.

    Raises
    ------
    TypeError
        If *node* is neither a :class:`Synaptic` nor an :class:`RSynaptic`.
    """
    alpha = float(node.alpha)
    beta = float(node.beta)
    threshold = float(node.threshold)
    reset = str(node.reset_mechanism)

    if isinstance(node, RSynaptic):
        n_neurons = int(node.n_neurons)
        use_bias = bool(node.use_bias)
        module = snntorch.RSynaptic(
            alpha=alpha,
            beta=beta,
            linear_features=n_neurons,
            threshold=threshold,
            reset_mechanism=reset,
            spike_grad=spike_grad,
            # reset_delay=False mirrors the reference training notebook
            # (Braille_training_snntorch.ipynb, cell 3) and this codebase's
            # existing hardcoded convention in
            # backend/app/routers/notebook.py's CnlRSynaptic codegen branch:
            # snn.RSynaptic defaults reset_delay=True; leaving it unset
            # diverges from the weights' training-time convention and
            # desyncs reset timing from spike timing.
            reset_delay=False,
        )
        if not use_bias and module.recurrent.bias is not None:
            module.recurrent.bias = None
        recurrent_weight = getattr(node, "recurrent_weight", None)
        if recurrent_weight is not None:
            # An imported, previously-trained graph (fused by
            # nir_topology.fuse_recurrent_pairs) carries its real recurrent weight
            # matrix — load it in place of snnTorch's random initialisation, mirroring
            # the nir.Conv2d/nir.Linear weight-copy pattern used elsewhere in this
            # codebase.  The no_grad() here only permits the in-place .copy_() on a
            # leaf tensor; it does not freeze the parameter, so the trainable path can
            # still fine-tune this weight starting from the imported value.
            with torch.no_grad():
                module.recurrent.weight.copy_(
                    torch.tensor(np.asarray(recurrent_weight, dtype=np.float32))
                )
        return module

    if isinstance(node, Synaptic):
        return snntorch.Synaptic(
            alpha=alpha,
            beta=beta,
            threshold=threshold,
            reset_mechanism=reset,
            spike_grad=spike_grad,
            # reset_delay=False — same rationale as the RSynaptic branch above.
            reset_delay=False,
        )

    raise TypeError(
        f"build_synaptic_module only supports Synaptic/RSynaptic nodes, got {type(node).__name__}."
    )
