"""Backpropagation Through Time (BPTT) utility for Rockpool models.

Allows training exported SNN graphs using PyTorch autograd.
"""

from collections.abc import Callable

import torch


def train_with_bptt(
    model: torch.nn.Module,
    inputs: torch.Tensor,
    targets: torch.Tensor,
    loss_fn: Callable[[torch.Tensor, torch.Tensor], torch.Tensor],
    optimizer: torch.optim.Optimizer,
    epochs: int = 1,
) -> list[float]:
    """Train a Rockpool TorchModule using BPTT.

    Parameters
    ----------
    model : torch.nn.Module
        The Rockpool model to train (must support PyTorch forward passes and return (out, state, info)).
    inputs : torch.Tensor
        The input sequence tensor. Shape: (batch_size, timesteps, features)
    targets : torch.Tensor
        The target tensor for the loss function.
    loss_fn : Callable
        A PyTorch loss function (e.g., `torch.nn.MSELoss()`).
    optimizer : torch.optim.Optimizer
        A PyTorch optimizer (e.g., `torch.optim.Adam`).
    epochs : int, optional
        The number of training epochs, by default 1.

    Returns
    -------
    list[float]
        A list of loss values per epoch.
    """
    losses = []

    # Ensure model is in training mode
    if hasattr(model, "train"):
        model.train()

    for epoch in range(epochs):
        optimizer.zero_grad()

        # Rockpool modules typically return (output, new_state, record_dict)
        # We only need the output for basic BPTT
        out, _, _ = model(inputs)

        loss = loss_fn(out, targets)
        loss.backward()
        optimizer.step()

        losses.append(loss.item())

    return losses
