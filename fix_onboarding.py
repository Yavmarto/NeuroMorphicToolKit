import re

with open('nmtk/neuro_toolkit/lib/screens/onboarding.dart', 'r') as f:
    text = f.read()

# We need to completely replace onboarding.dart to be a single screen.
# I'll just write a new simplified onboarding screen that skips the wizard chrome.
# Reading the current onboarding.dart first.
