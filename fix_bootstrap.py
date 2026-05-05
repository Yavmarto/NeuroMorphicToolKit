import re

with open('nmtk/neuro_toolkit/lib/main.dart', 'r') as f:
    text = f.read()

# According to the audit: "The `const Text('CONTROL API HOST')` is a plain Text widget placed above ShadInput. There's no labelText, semanticsLabel on the input..."
# But wait, looking at the previous grep, it was using ShadInputFormField with label.
# Let's double check what's actually there.
