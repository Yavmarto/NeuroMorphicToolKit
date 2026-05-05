import re

with open('nmtk_ui_core/lib/app_theme.dart', 'r') as f:
    text = f.read()

# remove final Color glassmorphismColor;
text = re.sub(r'\s*final Color glassmorphismColor;', '', text)
# remove required this.glassmorphismColor,
text = re.sub(r'\s*required this.glassmorphismColor,', '', text)
# remove glassmorphismColor: ...
text = re.sub(r'\s*glassmorphismColor:[\s\S]*?,(?=\s*variant:|\s*synKeyword:)', '', text)

with open('nmtk_ui_core/lib/app_theme.dart', 'w') as f:
    f.write(text)

print("Updated app_theme.dart")
