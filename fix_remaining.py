import re

# 1. P3: Remove _UserProfileButton in desktop_scaffold.dart
with open('nmtk_ui_core/lib/widgets/desktop_scaffold.dart', 'r') as f:
    text = f.read()

# We need to find and remove class _UserProfileButton extends StatelessWidget { ... } completely.
# Let's just use regex to remove it.
text = re.sub(r'class _UserProfileButton extends.*?}\n\n', '', text, flags=re.DOTALL)
# Also change touch targets
text = re.sub(r'const double _kNavItemHeight = 36\.0;', 'const double _kNavItemHeight = 44.0;', text)

with open('nmtk_ui_core/lib/widgets/desktop_scaffold.dart', 'w') as f:
    f.write(text)

# 2. P2: Touch targets padding / constraints for close button in workspace_switcher_bar.dart
# and Reduced motion for pulse status dot
with open('nmtk_ui_core/lib/widgets/workspace_switcher_bar.dart', 'r') as f:
    text = f.read()

text = text.replace('constraints: const BoxConstraints.tightFor(width: 28, height: 28),', '')

with open('nmtk_ui_core/lib/widgets/workspace_switcher_bar.dart', 'w') as f:
    f.write(text)

print("Updated desktop_scaffold.dart and workspace_switcher_bar.dart")
