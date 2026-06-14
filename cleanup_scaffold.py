with open('nmtk_ui_core/lib/widgets/desktop_scaffold.dart', 'r') as f:
    text = f.read()

# 1. Imports
text = text.replace(
    "import 'package:nmtk_ui_core/shell_tokens.dart';",
    "import 'package:nmtk_ui_core/shell_tokens.dart';\nimport 'package:nmtk_ui_core/models/scaffold_models.dart';\nimport 'package:nmtk_ui_core/widgets/mobile_scaffold.dart';"
)

# 2. Models
s1 = text.find("// ─────────────────────────────────────────────────────────────────────────────\n// DATA MODELS")
e1 = text.find("// ─────────────────────────────────────────────────────────────────────────────\n// FILE ACTION DELEGATE")
if s1 != -1 and e1 != -1:
    text = text[:s1] + text[e1:]

s1b = text.find("// ─────────────────────────────────────────────────────────────────────────────\n// FILE ACTION DELEGATE")
e1b = text.find("// ─────────────────────────────────────────────────────────────────────────────\n// DESKTOP SCAFFOLD")
if s1b != -1 and e1b != -1:
    text = text[:s1b] + text[e1b:]

# 3. _buildLayout replacement
old_build = """  Widget _buildLayout(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth < _kMobileBreakpoint) {
      return _buildMobileLayout(context);
    }
    return _buildDesktopLayout(context);
  }"""
new_build = """  Widget _buildLayout(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth < _kMobileBreakpoint) {
      return NmtkMobileScaffold(
        navItems: widget.navItems,
        selectedIndex: widget.selectedIndex,
        child: widget.child,
        onNavItemSelected: widget.onNavItemSelected,
        userProfile: widget.userProfile,
        sidebarBrand: widget.sidebarBrand,
        mode: widget.mode,
        showBackButton: widget.showBackButton,
        onBack: widget.onBack,
        fileActions: widget.fileActions,
        onSettingsPressed: widget.onSettingsPressed,
        pageTitle: widget.pageTitle,
        footerNavItems: widget.footerNavItems,
        onFooterNavItemSelected: widget.onFooterNavItemSelected,
      );
    }
    return _buildDesktopLayout(context);
  }"""
text = text.replace(old_build, new_build)

# 4. Mobile layout removal
s2 = text.find("  Widget _buildMobileLayout(BuildContext context) {")
e2 = text.find("// ─────────────────────────────────────────────────────────────────────────────\n// RAIL COLUMN")
if s2 != -1 and e2 != -1:
    text = text[:s2] + text[e2:]

with open('nmtk_ui_core/lib/widgets/desktop_scaffold.dart', 'w') as f:
    f.write(text)
