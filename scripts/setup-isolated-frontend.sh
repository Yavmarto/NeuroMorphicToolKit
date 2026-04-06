#!/bin/bash
# setup-isolated-frontend.sh - Mocks nmtk_ui_core for isolated Flutter analysis.
set -e

# Target directory (usually ../../nmtk_ui_core from submodule/frontend).
# If it already exists, assume we are in the monorepo or already set up.
TARGET_DIR="../../nmtk_ui_core"

if [ -d "$TARGET_DIR" ]; then
  echo ">>> [nmtk_ui_core] Found at $TARGET_DIR. Skipping setup."
  exit 0
fi

echo ">>> [nmtk_ui_core] Not found. Creating mock at $TARGET_DIR..."

mkdir -p "$TARGET_DIR/lib/models"
mkdir -p "$TARGET_DIR/lib/widgets"

# Create pubspec.yaml
cat > "$TARGET_DIR/pubspec.yaml" <<EOF
name: nmtk_ui_core
version: 0.6.0+3
environment:
  sdk: '>=3.0.0 <4.0.0'
  flutter: ">=3.0.0"
dependencies:
  flutter:
    sdk: flutter
EOF

# Create dummy lib files
cat > "$TARGET_DIR/lib/nmtk_ui_core.dart" <<EOF
library nmtk_ui_core;
export 'app_theme.dart';
EOF

cat > "$TARGET_DIR/lib/app_theme.dart" <<EOF
import 'package:flutter/material.dart';
class NMTKTheme {
  static ThemeData get darkTheme => ThemeData.dark();
  static ThemeData get lightTheme => ThemeData.light();
}
EOF

# Create empty mocks for other expected files to satisfy exports if needed.
touch "$TARGET_DIR/lib/models/energy_report.dart"
touch "$TARGET_DIR/lib/models/quantization_report.dart"
touch "$TARGET_DIR/lib/models/sensor_frame.dart"
touch "$TARGET_DIR/lib/widgets/buttons.dart"
touch "$TARGET_DIR/lib/widgets/energy_bar_chart.dart"
touch "$TARGET_DIR/lib/widgets/pipeline_stepper.dart"
touch "$TARGET_DIR/lib/widgets/quantization_table.dart"
touch "$TARGET_DIR/lib/widgets/sparkline_chart.dart"
touch "$TARGET_DIR/lib/widgets/nmtk_navigation_rail.dart"

echo ">>> Mock nmtk_ui_core successfully created at $TARGET_DIR."
echo ">>> NOTE: This dummy package will NOT be tracked by Git (it is outside the repository root)."
