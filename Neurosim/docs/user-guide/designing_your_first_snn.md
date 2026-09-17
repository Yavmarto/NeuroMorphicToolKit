# Designing Your First SNN Circuit

Welcome to NeuroSim! This guide will walk you through creating a simple Spiking Neural Network (SNN) circuit using the graphical interface.

## Overview

In this tutorial, we will build a basic circuit where a sensory input (Encoder) drives a population of neurons (LIF Population), and we will visualize the resulting spikes.

## Step 1: Open the Canvas

When you launch NeuroSim, you'll be presented with a blank canvas. This is your workspace for designing neural architectures.

## Step 2: Add Components

The **Component Library** is located on the left sidebar. It contains various building blocks:

1.  **Add an Encoder:**
    -   Find the **Encoders** category.
    -   Drag a **Rate Encoder** onto the canvas. This component converts constant values into spike trains.
2.  **Add a Neuron Population:**
    -   Find the **Neurons** category.
    -   Drag an **LIF Population** onto the canvas. This represents a group of Leaky Integrate-and-Fire neurons.

## Step 3: Configure Parameters

Click on a component on the canvas to open the **Property Panel** on the right.

1.  **Configure the Rate Encoder:**
    -   Set the `rate` to `50` Hz.
2.  **Configure the LIF Population:**
    -   Set `n_neurons` to `100`.
    -   Adjust `tau_rc` (membrane time constant) if desired.

## Step 4: Connect Components

To create a connection:
1.  Hover over the **Output** port of the Rate Encoder.
2.  Click and drag a line to the **Input** port of the LIF Population.
3.  A connection (synapse) is created. You can click on the connection to adjust its `weight` and `delay` in the Property Panel.

## Step 5: Run a Preview

Once your circuit is connected, you can see it in action:
1.  Click the **Preview** button (usually at the top or bottom of the screen).
2.  The backend will run a short simulation (500ms).
3.  A visualization window will appear showing the spike raster plot and membrane voltages of the neurons.

## Step 6: Using the CNL Editor

For advanced users, the **CNL Editor** (Conceptual Neural Language) allows you to define the network using natural-language-like syntax. The canvas and the CNL editor stay in sync:
-   Changes on the canvas update the CNL code.
-   Typing in the CNL editor updates the canvas layout.

## Next Steps

Experiment with different component types, such as **Adaptive LIF** neurons or different **Patterns** of connectivity. Happy simulating!
