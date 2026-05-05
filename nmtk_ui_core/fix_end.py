with open('lib/widgets/desktop_scaffold.dart', 'r') as f:
    text = f.read()

legacy_str = "// LEGACY — kept only for backward compatibility"
idx = text.find(legacy_str)

if idx != -1:
    # Just truncate the file right before the legacy section comment block
    end_idx = text.rfind('// ─────────────────────────────────────────────────────────────────────────────', 0, idx)
    if end_idx != -1:
        text = text[:end_idx].rstrip() + '\n'
        
with open('lib/widgets/desktop_scaffold.dart', 'w') as f:
    f.write(text)

