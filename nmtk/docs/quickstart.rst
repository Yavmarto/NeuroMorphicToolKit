Quick Start
===========

Installation
------------

.. code-block:: bash

   pip install neurocnl

Basic Usage
-----------

.. code-block:: python

   from neurocnl import parse, validate, generate, export

   # Parse a CNL spec
   spec = parse("The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0")

   # Validate against biological invariants
   params = {"threshold": 1.0, "resting_potential": 0.0,
             "refractory_period": 0.002, "tau": 0.02,
             "reset_potential": 0.0, "current_voltage": 0.5}
   report = validate([spec], params)

   # Generate a Nengo network
   net = generate([spec], params)

   # Export to C header for Teensy
   c_code = export(net, format="c_header")
