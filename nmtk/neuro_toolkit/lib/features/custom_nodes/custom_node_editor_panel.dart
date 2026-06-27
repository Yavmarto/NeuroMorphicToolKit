import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:nmtk_ui_core/shell_tokens.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

import 'package:neuro_toolkit/features/custom_nodes/custom_node_repository.dart';

const _kStarterTemplate = r'''
from nmtk_sdk import CustomNode, param, port

class MyNode(CustomNode):
    name = "My Node"
    category = "neurons"
    canvases = ["model"]        # model | training | eval | inference
    frameworks = ["nengo"]      # nengo | norse | spikingjelley | brian2
    description = "Describe your node"
    author = ""
    version = "1.0.0"

    @param(type="float", default=0.02, label="Membrane time constant", unit="s")
    def tau_m(self): ...

    @port(direction="input", label="Spikes in")
    def spikes_in(self): ...

    @port(direction="output", label="Spikes out")
    def spikes_out(self): ...

    def to_nengo(self, params):
        import nengo
        return nengo.LIF(tau_rc=params["tau_m"])
''';

/// Extracts the first class name from Python source.
///
/// Returns `null` if no `class` statement is found.
String? _extractClassName(String source) {
  final classPattern = RegExp(r'^\s*class\s+(\w+)', multiLine: true);
  final match = classPattern.firstMatch(source);
  return match?.group(1);
}

/// Full-screen panel that embeds a Monaco editor (via [InAppWebView]) for
/// editing custom SNN node Python files and saves them to Neurosim via
/// [CustomNodeRepository].
class CustomNodeEditorPanel extends StatefulWidget {
  const CustomNodeEditorPanel({
    required this.repository,
    this.initialSource,
    super.key,
  });

  final CustomNodeRepository repository;

  /// Optional pre-populated source code. When omitted, the starter template is
  /// injected once the Monaco editor has finished loading.
  final String? initialSource;

  @override
  State<CustomNodeEditorPanel> createState() => _CustomNodeEditorPanelState();
}

class _CustomNodeEditorPanelState extends State<CustomNodeEditorPanel> {
  InAppWebViewController? _controller;
  // Acceptable ephemeral UI state: _saving gates the AppBar save button during
  // the async Monaco→repository round-trip. It has no cross-widget semantics
  // and is correctly scoped to this panel's lifetime. (architecture skill §3)
  bool _saving = false;

  String get _startingSource => widget.initialSource ?? _kStarterTemplate;

  Future<void> _injectCode(String source) async {
    final controller = _controller;
    if (controller == null) return;

    // Escape the source for safe JS string injection.
    final escaped = source
        .replaceAll(r'\', r'\\')
        .replaceAll("'", r"\'")
        .replaceAll('\n', r'\n')
        .replaceAll('\r', '');

    await controller.evaluateJavascript(source: "setCode('$escaped')");
  }

  Future<String?> _fetchCode() async {
    final controller = _controller;
    if (controller == null) return null;
    final result = await controller.evaluateJavascript(source: 'getCode()');
    return result?.toString();
  }

  Future<void> _onSave() async {
    final source = await _fetchCode();
    if (source == null || source.isEmpty) {
      _showSnackBar('Editor returned no code — nothing to save.',
          isError: true);
      return;
    }

    final className = _extractClassName(source);
    if (className == null) {
      _showSnackBar(
        'Could not find a class definition in the source. '
        'Make sure your node declares a class.',
        isError: true,
      );
      return;
    }

    final filename = '${_toSnakeCase(className)}.py';

    setState(() => _saving = true);
    try {
      final installedPath = await widget.repository.save(
        filename: filename,
        source: source,
      );
      if (!mounted) return;
      _showSnackBar('Saved to $installedPath');
      Navigator.of(context).pop(filename);
    } on Exception catch (e) {
      if (!mounted) return;
      _showSnackBar('Save failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    final colorToken = isError
        // P0-1 fix: NmtkShellTokens.errorColor replaces Colors.red.shade700
        ? NmtkShellTokens.of(context).errorColor
        : null;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: colorToken,
      ),
    );
  }

  /// Converts `CamelCase` to `snake_case`.
  String _toSnakeCase(String name) {
    return name
        .replaceAllMapped(
          RegExp(r'([A-Z])'),
          (m) => '_${m.group(1)!.toLowerCase()}',
        )
        .replaceFirst(RegExp(r'^_'), '');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      // P0-2 fix: style the AppBar using colorScheme tokens (no raw Material defaults)
      appBar: AppBar(
        backgroundColor: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Custom Node Editor',
          style: Zeta.of(context).textStyles.titleMedium.copyWith(
                color: scheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
        ),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            // P1-3 fix: ZetaButton replaces the banned TextButton.icon
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ZetaButton(
                label: 'Save',
                leadingIcon: ZetaIcons.save,
                onPressed: _onSave,
                type: ZetaButtonType.text,
              ),
            ),
        ],
      ),
      body: InAppWebView(
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          isInspectable: false,
        ),
        onWebViewCreated: (controller) {
          _controller = controller;
          controller.loadFile(assetFilePath: 'assets/custom_node_editor.html');
        },
        onLoadStop: (controller, url) async {
          await _injectCode(_startingSource);
        },
      ),
    );
  }
}
