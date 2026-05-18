
with open('lib/widgets/desktop_scaffold.dart', 'r') as f:
    text = f.read()

# Find class _UserProfileButtonState extends State<_UserProfileButton>
# and find the matching closing brace.
start_idx = text.find('class _UserProfileButtonState')
if start_idx != -1:
    end_idx = text.find('class ', start_idx + 1)
    if end_idx == -1:
        end_idx = len(text)
    # Be careful not to delete trailing code if there's no class following,
    # but _UserProfileButtonState is at the bottom usually. Let's check text[start_idx:end_idx]

    text = text[:start_idx] + text[end_idx:]

with open('lib/widgets/desktop_scaffold.dart', 'w') as f:
    f.write(text)
