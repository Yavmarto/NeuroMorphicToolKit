# Adding a New Component Type

NeuroSim uses a modular system for defining neural components. Each component is defined by a JSON manifest located in `neurosim/components/`.

## Component Manifest Format

The JSON manifest describes the component's properties, parameters, ports, and how it maps to the Conceptual Neural Language (CNL).

### Example Manifest

Save the following as `neurosim/components/neurons/my_new_neuron.json`:

```json
{
  "id": "my_new_neuron",
  "name": "My New Neuron",
  "category": "Neurons",
  "description": "A custom neuron model with unique dynamics.",
  "icon": "settings",
  "parameters": [
    {
      "name": "threshold",
      "label": "Firing Threshold",
      "description": "The membrane voltage at which the neuron fires a spike.",
      "type": "float",
      "default": 1.0,
      "min": 0.5,
      "max": 2.0,
      "unit": "mV"
    }
  ],
  "ports": [
    {
      "id": "in",
      "direction": "input",
      "label": "Input"
    },
    {
      "id": "out",
      "direction": "output",
      "label": "Output"
    }
  ],
  "cnl_template": "Create a population '{name}' of MyNewNeuron with threshold={threshold}."
}
```

## Key Fields

-   **`id`**: A unique identifier for the component.
-   **`name`**: The display name in the UI.
-   **`category`**: The category folder (e.g., `Neurons`, `Encoders`, `Synapses`).
-   **`description`**: A plain-language description shown in tooltips.
-   **`icon`**: A Material Icon name used in the UI sidebar.
-   **`parameters`**: A list of configurable parameters.
    -   `type`: One of `float`, `int`, `bool`, or `enum`.
    -   `default`: The default value.
    -   `min`/`max`: (Optional) Validation bounds for numeric types.
    -   `unit`: (Optional) The unit of measurement (e.g., `s`, `mV`, `Hz`).
-   **`ports`**: A list of input and output ports for connections.
-   **`cnl_template`**: A template string used to generate the CNL specification. Placeholders like `{name}` and `{parameter_name}` will be replaced with actual values.

## Registration

New components are automatically discovered by the backend. Simply add your JSON file to the appropriate subdirectory in `neurosim/components/`, and it will appear in the UI the next time the frontend fetches the component list.

## Backend Implementation

While the JSON manifest defines the UI and validation rules, you must also ensure the backend (Nengo-based simulation) knows how to handle the new component:

1.  **Update `neurosim/app/services/preview_runner.py`**: Add logic to translate the `CanvasNode` with your new `component_id` into a Nengo object.
2.  **Update `neurocnl` Integration**: If you want the component to be correctly parsed/generated via CNL, ensure the `neurocnl` library supports the corresponding syntax defined in your `cnl_template`.
