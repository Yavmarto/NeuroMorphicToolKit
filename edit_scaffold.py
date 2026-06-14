import sys

with open('nmtk_ui_core/lib/widgets/desktop_scaffold.dart', 'r') as f:
    lines = f.readlines()

new_lines = []
skip = False

for i, line in enumerate(lines):
    # Add imports
    if line.startswith("import 'package:nmtk_ui_core/shell_tokens.dart';"):
        new_lines.append(line)
        new_lines.append("import 'package:nmtk_ui_core/models/scaffold_models.dart';\n")
        new_lines.append("import 'package:nmtk_ui_core/widgets/mobile_scaffold.dart';\n")
        continue

    # Skip models
    if line.startswith("class NmtkSidebarItem {"):
        skip = True
    if skip and line.startswith("}") and i > 125 and i <= 131:
        # Check if we reached the end of NmtkFileActionDelegate
        if "void onSaveFileAs();" in lines[i-1]:
            skip = False
            continue

    if skip:
        continue

    # Replace _buildLayout
    if line.strip() == "return _buildMobileLayout(context);":
        indent = line[:line.find("return")]
        new_lines.append(indent + "return NmtkMobileScaffold(\n")
        new_lines.append(indent + "  navItems: widget.navItems,\n")
        new_lines.append(indent + "  selectedIndex: widget.selectedIndex,\n")
        new_lines.append(indent + "  child: widget.child,\n")
        new_lines.append(indent + "  onNavItemSelected: widget.onNavItemSelected,\n")
        new_lines.append(indent + "  userProfile: widget.userProfile,\n")
        new_lines.append(indent + "  sidebarBrand: widget.sidebarBrand,\n")
        new_lines.append(indent + "  mode: widget.mode,\n")
        new_lines.append(indent + "  showBackButton: widget.showBackButton,\n")
        new_lines.append(indent + "  onBack: widget.onBack,\n")
        new_lines.append(indent + "  fileActions: widget.fileActions,\n")
        new_lines.append(indent + "  onSettingsPressed: widget.onSettingsPressed,\n")
        new_lines.append(indent + "  pageTitle: widget.pageTitle,\n")
        new_lines.append(indent + "  footerNavItems: widget.footerNavItems,\n")
        new_lines.append(indent + "  onFooterNavItemSelected: widget.onFooterNavItemSelected,\n")
        new_lines.append(indent + ");\n")
        continue

    # Skip _buildMobileLayout and mobile UI classes
    if line.startswith("  Widget _buildMobileLayout(BuildContext context) {"):
        skip = True
    if skip and line.startswith("class _NmtkMobileDrawer extends StatelessWidget {"):
        # this is the last class to skip
        pass
    if skip and line.startswith("}") and i > 690 and i < 700:
        # Check if we are at the end of _NmtkMobileDrawer
        if i < len(lines) - 2 and "RAIL COLUMN" in lines[i+2]:
            skip = False
            continue
            
    if skip:
        continue

    # Skip the data models docstrings and comments before them
    if line.startswith("/// A single navigation destination"):
        skip = True
        continue
    if line.startswith("/// One entry in the [NmtkUserProfile]"):
        skip = True
        continue
    if line.startswith("/// User identity shown"):
        skip = True
        continue
    if line.startswith("/// Abstract interface for New/Open"):
        skip = True
        continue

    new_lines.append(line)

with open('nmtk_ui_core/lib/widgets/desktop_scaffold.dart', 'w') as f:
    f.writelines(new_lines)
