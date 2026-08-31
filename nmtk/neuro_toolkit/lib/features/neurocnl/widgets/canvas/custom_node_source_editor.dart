import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/component.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/pipeline_dag.dart';
import 'package:neuro_toolkit/features/neurocnl/models/custom_node_source.dart';
import 'package:neuro_toolkit/features/neurocnl/models/nir_node_type.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/component_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/nir_types_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/sync_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/utils/canvas_projection_utils.dart';

class CustomNodeEditorOutcome {
  const CustomNodeEditorOutcome({
    required this.result,
    required this.replacedSelectedNode,
  });

  final CustomNodeSaveResult result;
  final bool replacedSelectedNode;
}

Future<CustomNodeEditorOutcome?> showCustomNodeSourceEditor({
  required BuildContext context,
  required CanvasNode node,
  required NirNodeType? nodeType,
}) {
  final editor = CustomNodeSourceEditor(node: node, nodeType: nodeType);
  return _showSourceEditor(context, editor);
}

Future<CustomNodeEditorOutcome?> showPipelineNodeSourceEditor({
  required BuildContext context,
  required PipelineDagNode node,
  required PipelinePhaseId phase,
}) {
  return _showSourceEditor(
    context,
    CustomNodeSourceEditor.pipeline(node: node, phase: phase),
  );
}

Future<CustomNodeEditorOutcome?> _showSourceEditor(
  BuildContext context,
  Widget editor,
) {
  final compact =
      MediaQuery.sizeOf(context).width < NmtkShellTokens.compactBreakpoint;
  if (compact) {
    return Navigator.of(context).push<CustomNodeEditorOutcome>(
      MaterialPageRoute<CustomNodeEditorOutcome>(
        fullscreenDialog: true,
        builder: (_) => editor,
      ),
    );
  }
  return showDialog<CustomNodeEditorOutcome>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext dialogContext) {
      final size = MediaQuery.sizeOf(dialogContext);
      return Dialog(
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: math.min(1080, size.width - 64),
          height: math.min(760, size.height - 64),
          child: editor,
        ),
      );
    },
  );
}

class _SourceEditorTarget {
  const _SourceEditorTarget({
    required this.nodeId,
    required this.componentId,
    required this.displayName,
    required this.category,
    required this.parameters,
    required this.parameterDefinitions,
    required this.ports,
    this.nirType,
    this.pipelineType,
    this.pipelinePhase,
  });

  factory _SourceEditorTarget.model(CanvasNode node, NirNodeType? nodeType) {
    final definitions =
        nodeType?.parameters
            .map(
              (NirParameterDef parameter) => <String, dynamic>{
                'name': parameter.name,
                'label': parameter.label,
                'description': parameter.description,
                'type': parameter.type,
                'default':
                    node.parameters[parameter.name] ?? parameter.defaultValue,
                'min': parameter.min,
                'max': parameter.max,
                'unit': parameter.unit,
                'enum_values': parameter.enumValues,
              },
            )
            .toList(growable: false) ??
        const <Map<String, dynamic>>[];
    final ports =
        nodeType?.ports
            .map(
              (NirPortDef port) => <String, dynamic>{
                'id': port.id,
                'direction': port.direction,
                'label': port.label,
              },
            )
            .toList(growable: false) ??
        const <Map<String, dynamic>>[];
    return _SourceEditorTarget(
      nodeId: node.id,
      componentId: node.componentId,
      displayName: resolveNodeDisplayName(node),
      category:
          nodeType?.category ??
          node.metadata['category']?.toString() ??
          'custom',
      parameters: node.parameters,
      parameterDefinitions: definitions,
      ports: ports,
      nirType: node.nirType,
    );
  }

  factory _SourceEditorTarget.pipeline(
    PipelineDagNode node,
    PipelinePhaseId phase,
  ) {
    final parameters = <String, dynamic>{
      ...node.type.defaultParameters,
      ...node.parameters,
    };
    String parameterType(Object? value) => switch (value) {
      bool() => 'bool',
      int() => 'int',
      num() => 'float',
      _ => 'text',
    };
    String label(String name) => name
        .split('_')
        .map(
          (part) => part.isEmpty
              ? part
              : '${part[0].toUpperCase()}${part.substring(1)}',
        )
        .join(' ');
    final definitions = parameters.entries
        .map(
          (entry) => <String, dynamic>{
            'name': entry.key,
            'label': label(entry.key),
            'type': parameterType(entry.value),
            'default': entry.value,
          },
        )
        .toList(growable: false);
    final ports = <Map<String, dynamic>>[
      for (final port in node.type.inputPorts)
        {'id': port.id, 'direction': 'input', 'label': label(port.id)},
      for (final port in node.type.outputPorts)
        {'id': port.id, 'direction': 'output', 'label': label(port.id)},
    ];
    return _SourceEditorTarget(
      nodeId: node.id,
      componentId: node.customComponentId ?? node.type.name,
      displayName: node.type.label,
      category: node.type.category.name,
      parameters: parameters,
      parameterDefinitions: definitions,
      ports: ports,
      pipelineType: node.type.name,
      pipelinePhase: phase,
    );
  }

  final String nodeId;
  final String componentId;
  final String displayName;
  final String category;
  final Map<String, dynamic> parameters;
  final List<Map<String, dynamic>> parameterDefinitions;
  final List<Map<String, dynamic>> ports;
  final String? nirType;
  final String? pipelineType;
  final PipelinePhaseId? pipelinePhase;

  String? get canvasContext => switch (pipelinePhase) {
    PipelinePhaseId.train => 'training',
    PipelinePhaseId.eval => 'eval',
    PipelinePhaseId.infer => 'inference',
    null => null,
  };
}

class CustomNodeSourceEditor extends ConsumerStatefulWidget {
  CustomNodeSourceEditor({
    required CanvasNode this.node,
    required this.nodeType,
    super.key,
  }) : _target = _SourceEditorTarget.model(node, nodeType);

  CustomNodeSourceEditor.pipeline({
    required PipelineDagNode node,
    required PipelinePhaseId phase,
    super.key,
  }) : node = null,
       nodeType = null,
       _target = _SourceEditorTarget.pipeline(node, phase);

  final CanvasNode? node;
  final NirNodeType? nodeType;
  final _SourceEditorTarget _target;

  @override
  ConsumerState<CustomNodeSourceEditor> createState() =>
      _CustomNodeSourceEditorState();
}

class _CustomNodeSourceEditorState
    extends ConsumerState<CustomNodeSourceEditor> {
  late final CodeLineEditingController _controller;
  late final CodeFindController _findController;
  late final FocusNode _editorFocus;
  Timer? _validationTimer;
  CustomNodeSource? _source;
  CustomNodeValidation? _validation;
  Object? _loadError;
  Object? _validationError;
  bool _loading = true;
  bool _validating = false;
  bool _saving = false;
  bool _dirty = false;
  bool _allowClose = false;
  int _validationSequence = 0;

  @override
  void initState() {
    super.initState();
    _controller = CodeLineEditingController();
    _findController = CodeFindController(_controller);
    _editorFocus = FocusNode();
    unawaited(_loadSource());
  }

  @override
  void dispose() {
    _validationTimer?.cancel();
    _findController.dispose();
    _controller.dispose();
    _editorFocus.dispose();
    super.dispose();
  }

  Future<void> _loadSource() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final source = await ref
          .read(apiClientProvider)
          .fetchCustomNodeSource(
            componentId: widget._target.componentId,
            nirType: widget._target.nirType,
            pipelineType: widget._target.pipelineType,
            canvasContext: widget._target.canvasContext,
            displayName: widget._target.displayName,
            category: widget._target.category,
            parameters: widget._target.parameters,
            parameterDefinitions: widget._target.parameterDefinitions,
            ports: widget._target.ports,
          );
      if (!mounted) return;
      _controller.text = source.source;
      setState(() {
        _source = source;
        _dirty = false;
        _loading = false;
      });
      await _validateNow();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  void _onCodeChanged(CodeLineEditingValue _) {
    if (_loading) return;
    setState(() {
      _dirty = _controller.text != _source?.source;
      _validating = true;
      _validationError = null;
    });
    _validationTimer?.cancel();
    _validationTimer = Timer(
      const Duration(milliseconds: 400),
      () => unawaited(_validateNow()),
    );
  }

  Future<void> _validateNow() async {
    final sequence = ++_validationSequence;
    _validationTimer?.cancel();
    setState(() {
      _validating = true;
      _validationError = null;
    });
    try {
      final validation = await ref
          .read(apiClientProvider)
          .validateCustomNodeSource(_controller.text);
      if (!mounted || sequence != _validationSequence) return;
      setState(() {
        _validation = validation;
        _validating = false;
      });
    } on Object catch (error) {
      if (!mounted || sequence != _validationSequence) return;
      setState(() {
        _validationError = error;
        _validating = false;
      });
    }
  }

  bool _portsAreCompatible(ComponentBlock component) {
    final inputPorts = component.ports
        .where((PortDef port) => port.direction == 'input')
        .map((PortDef port) => port.id)
        .toSet();
    final outputPorts = component.ports
        .where((PortDef port) => port.direction == 'output')
        .map((PortDef port) => port.id)
        .toSet();
    final phase = widget._target.pipelinePhase;
    final edges = phase == null
        ? ref
              .read(canvasProvider)
              .graph
              .edges
              .map(
                (edge) => (
                  sourceNodeId: edge.sourceNodeId,
                  sourcePort: edge.sourcePort,
                  targetNodeId: edge.targetNodeId,
                  targetPort: edge.targetPort,
                ),
              )
        : ref
              .read(canvasProvider)
              .pipelinePhases
              .dagFor(phase)
              .edges
              .map(
                (edge) => (
                  sourceNodeId: edge.sourceNodeId,
                  sourcePort: edge.sourcePort,
                  targetNodeId: edge.targetNodeId,
                  targetPort: edge.targetPort,
                ),
              );
    for (final edge in edges) {
      if (edge.sourceNodeId == widget._target.nodeId &&
          !outputPorts.contains(edge.sourcePort)) {
        return false;
      }
      if (edge.targetNodeId == widget._target.nodeId &&
          !inputPorts.contains(edge.targetPort)) {
        return false;
      }
    }
    return true;
  }

  Future<void> _save({required bool saveAs}) async {
    if (_saving || _validating || _validation?.valid != true) return;
    setState(() => _saving = true);
    try {
      final source = _source;
      final result = await ref
          .read(apiClientProvider)
          .saveCustomNodeSource(
            source: _controller.text,
            saveAs: saveAs,
            targetComponentId: source?.isCustom == true
                ? source!.componentId
                : null,
            expectedRevision: source?.revision,
          );
      ref.invalidate(componentsProvider);
      ref.invalidate(customNirNodeTypesProvider);

      var replaced = false;
      if (saveAs && result.component != null) {
        if (_portsAreCompatible(result.component!)) {
          final phase = widget._target.pipelinePhase;
          if (phase == null) {
            ref
                .read(canvasProvider.notifier)
                .replaceNodeComponent(
                  widget._target.nodeId,
                  result.componentId,
                  baseNirType: result.component!.baseNirType,
                );
          } else {
            ref
                .read(canvasProvider.notifier)
                .replacePipelineDagNodeComponent(
                  phase,
                  widget._target.nodeId,
                  result.componentId,
                );
          }
          replaced = true;
        }
      }
      if (!mounted) return;
      _allowClose = true;
      Navigator.of(context).pop(
        CustomNodeEditorOutcome(result: result, replacedSelectedNode: replaced),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _requestClose() async {
    if (!_dirty) {
      _allowClose = true;
      Navigator.of(context).pop();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (BuildContext confirmationContext) => AlertDialog(
        title: const Text('Discard Python changes?'),
        content: const Text(
          'Your edits have not been saved as a reusable custom node.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(confirmationContext).pop(false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(confirmationContext).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      _allowClose = true;
      Navigator.of(context).pop();
    }
  }

  Future<void> _handleBack(bool didPop, Object? result) async {
    if (!didPop) await _requestClose();
  }

  void _focusDiagnostic(CustomNodeDiagnostic diagnostic) {
    final index = math.max(0, diagnostic.line - 1);
    final safeIndex = math.min(index, _controller.codeLines.length - 1);
    _controller.selection = CodeLineSelection.collapsed(
      index: safeIndex,
      offset: math.max(0, diagnostic.column - 1),
    );
    _editorFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _allowClose || !_dirty,
      onPopInvokedWithResult: _handleBack,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          titleSpacing: 20,
          title: Row(
            children: [
              const Icon(Icons.code, size: 20),
              const SizedBox(width: 10),
              const Text('Node source'),
              const SizedBox(width: 12),
              if (_source != null)
                _SourceKindBadge(isCustom: _source!.isCustom),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Close editor',
              onPressed: _requestClose,
              icon: const Icon(Icons.close),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return _EditorLoadError(onRetry: _loadSource);
    }

    final scheme = Theme.of(context).colorScheme;
    final validation = _validation;
    final canSave =
        !_saving &&
        !_validating &&
        _validationError == null &&
        validation?.valid == true;
    final bindings = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () =>
          _save(saveAs: _source?.isCustom != true),
      const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
          _save(saveAs: _source?.isCustom != true),
    };

    return CallbackShortcuts(
      bindings: bindings,
      child: Column(
        children: [
          Container(
            color: scheme.surfaceContainerLow,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _source?.isCustom == true
                        ? 'Editing reusable custom node'
                        : 'Built-in node — changes save as a new custom node',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                _ValidationStatus(
                  validating: _validating,
                  validation: validation,
                  error: _validationError,
                ),
              ],
            ),
          ),
          Expanded(
            child: _PythonCodeEditor(
              controller: _controller,
              findController: _findController,
              focusNode: _editorFocus,
              onChanged: _onCodeChanged,
            ),
          ),
          if (validation != null && validation.diagnostics.isNotEmpty)
            _DiagnosticsPanel(
              diagnostics: validation.diagnostics,
              onSelected: _focusDiagnostic,
            ),
          if (_validationError != null)
            MaterialBanner(
              content: const Text(
                'Python validation is unavailable. Reconnect to the backend and retry.',
              ),
              actions: [
                TextButton(onPressed: _validateNow, child: const Text('Retry')),
              ],
            ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Row(
              children: [
                TextButton(
                  onPressed: _saving ? null : _requestClose,
                  child: const Text('Cancel'),
                ),
                const Spacer(),
                if (_source?.isCustom == true) ...[
                  OutlinedButton.icon(
                    onPressed: canSave ? () => _save(saveAs: true) : null,
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Save as custom'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: canSave ? () => _save(saveAs: false) : null,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save, size: 18),
                    label: const Text('Save'),
                  ),
                ] else
                  FilledButton.icon(
                    onPressed: canSave ? () => _save(saveAs: true) : null,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add, size: 18),
                    label: const Text('Save as custom'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PythonCodeEditor extends StatelessWidget {
  const _PythonCodeEditor({
    required this.controller,
    required this.findController,
    required this.focusNode,
    required this.onChanged,
  });

  final CodeLineEditingController controller;
  final CodeFindController findController;
  final FocusNode focusNode;
  final ValueChanged<CodeLineEditingValue> onChanged;

  static const prompts = <CodePrompt>[
    CodeKeywordPrompt(word: 'CustomNode'),
    CodeKeywordPrompt(word: 'param'),
    CodeKeywordPrompt(word: 'port'),
    CodeKeywordPrompt(word: 'base_component_id'),
    CodeKeywordPrompt(word: 'base_nir_type'),
    CodeKeywordPrompt(word: 'node_id'),
    CodeFunctionPrompt(word: 'to_nengo', type: 'Any'),
    CodeFunctionPrompt(word: 'to_norse', type: 'Any'),
    CodeFunctionPrompt(word: 'to_brian2', type: 'Any'),
  ];

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    return CodeAutocomplete(
      promptsBuilder: DefaultCodeAutocompletePromptsBuilder(
        language: langPython,
        directPrompts: prompts,
      ),
      viewBuilder:
          (
            BuildContext context,
            ValueNotifier<CodeAutocompleteEditingValue> notifier,
            ValueChanged<CodeAutocompleteResult> onSelected,
          ) => _AutocompletePopup(notifier: notifier, onSelected: onSelected),
      child: CodeEditor(
        controller: controller,
        findController: findController,
        focusNode: focusNode,
        autofocus: true,
        wordWrap: false,
        onChanged: onChanged,
        chunkAnalyzer: const _PythonChunkAnalyzer(),
        style: CodeEditorStyle(
          fontSize: 13,
          fontHeight: 1.55,
          fontFamily: 'JetBrains Mono',
          fontFamilyFallback: const <String>['Menlo', 'Consolas', 'monospace'],
          backgroundColor: scheme.surface,
          textColor: scheme.onSurface,
          cursorColor: scheme.primary,
          cursorLineColor: scheme.primary.withValues(alpha: 0.08),
          selectionColor: scheme.primary.withValues(alpha: 0.24),
          codeTheme: CodeHighlightTheme(
            languages: <String, CodeHighlightThemeMode>{
              'python': CodeHighlightThemeMode(mode: langPython),
            },
            theme: dark ? atomOneDarkTheme : atomOneLightTheme,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        indicatorBuilder:
            (
              BuildContext context,
              CodeLineEditingController editingController,
              CodeChunkController chunkController,
              CodeIndicatorValueNotifier notifier,
            ) => Row(
              children: [
                DefaultCodeLineNumber(
                  controller: editingController,
                  notifier: notifier,
                ),
                DefaultCodeChunkIndicator(
                  width: 20,
                  controller: chunkController,
                  notifier: notifier,
                ),
              ],
            ),
        findBuilder:
            (
              BuildContext context,
              CodeFindController controller,
              bool readOnly,
            ) => _FindPanel(controller: controller),
      ),
    );
  }
}

class _PythonChunkAnalyzer implements CodeChunkAnalyzer {
  const _PythonChunkAnalyzer();

  @override
  List<CodeChunk> run(CodeLines codeLines) {
    final chunks = <CodeChunk>[];
    for (var index = 0; index < codeLines.length - 1; index++) {
      final text = codeLines[index].text;
      final trimmed = text.trimRight();
      if (!trimmed.endsWith(':') || trimmed.trimLeft().startsWith('#')) {
        continue;
      }
      final indent = text.length - text.trimLeft().length;
      var end = index + 1;
      for (var cursor = index + 1; cursor < codeLines.length; cursor++) {
        final candidate = codeLines[cursor].text;
        if (candidate.trim().isEmpty) {
          end = cursor;
          continue;
        }
        final candidateIndent = candidate.length - candidate.trimLeft().length;
        if (candidateIndent <= indent) {
          end = cursor;
          break;
        }
        end = cursor;
      }
      if (end - index > 1) chunks.add(CodeChunk(index, end));
    }
    return chunks;
  }
}

class _AutocompletePopup extends StatefulWidget implements PreferredSizeWidget {
  const _AutocompletePopup({required this.notifier, required this.onSelected});

  final ValueNotifier<CodeAutocompleteEditingValue> notifier;
  final ValueChanged<CodeAutocompleteResult> onSelected;

  @override
  Size get preferredSize =>
      Size(280, math.min(6, notifier.value.prompts.length) * 38.0);

  @override
  State<_AutocompletePopup> createState() => _AutocompletePopupState();
}

class _AutocompletePopupState extends State<_AutocompletePopup> {
  @override
  void initState() {
    super.initState();
    widget.notifier.addListener(_changed);
  }

  @override
  void dispose() {
    widget.notifier.removeListener(_changed);
    super.dispose();
  }

  void _changed() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final prompts = widget.notifier.value.prompts.take(6).toList();
    return Material(
      elevation: 4,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(8),
      child: ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: prompts.length,
        itemExtent: 38,
        itemBuilder: (BuildContext context, int index) {
          final prompt = prompts[index];
          return InkWell(
            onTap: () => widget.onSelected(prompt.autocomplete),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  const Icon(Icons.code, size: 15),
                  const SizedBox(width: 8),
                  Expanded(child: Text(prompt.word)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FindPanel extends StatelessWidget implements PreferredSizeWidget {
  const _FindPanel({required this.controller});

  final CodeFindController controller;

  @override
  Size get preferredSize => const Size.fromHeight(44);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? child) {
        if (controller.value == null) return const SizedBox.shrink();
        return Align(
          alignment: Alignment.topRight,
          child: Material(
            elevation: 3,
            child: SizedBox(
              width: 360,
              height: 44,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller.findInputController,
                      focusNode: controller.findInputFocusNode,
                      decoration: const InputDecoration(
                        hintText: 'Find in source',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Previous match',
                    onPressed: controller.previousMatch,
                    icon: const Icon(Icons.keyboard_arrow_up),
                  ),
                  IconButton(
                    tooltip: 'Next match',
                    onPressed: controller.nextMatch,
                    icon: const Icon(Icons.keyboard_arrow_down),
                  ),
                  IconButton(
                    tooltip: 'Close search',
                    onPressed: controller.close,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SourceKindBadge extends StatelessWidget {
  const _SourceKindBadge({required this.isCustom});

  final bool isCustom;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isCustom
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          isCustom ? 'Custom' : 'Built-in',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ),
    );
  }
}

class _ValidationStatus extends StatelessWidget {
  const _ValidationStatus({
    required this.validating,
    required this.validation,
    required this.error,
  });

  final bool validating;
  final CustomNodeValidation? validation;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    if (validating) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 8),
          Text('Checking Python…'),
        ],
      );
    }
    if (error != null) {
      return const Text('Validation unavailable');
    }
    final valid = validation?.valid == true;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          valid ? Icons.check_circle_outline : Icons.error_outline,
          size: 16,
          color: valid
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.error,
        ),
        const SizedBox(width: 6),
        Text(valid ? 'Python valid' : 'Fix diagnostics to save'),
      ],
    );
  }
}

class _DiagnosticsPanel extends StatelessWidget {
  const _DiagnosticsPanel({
    required this.diagnostics,
    required this.onSelected,
  });

  final List<CustomNodeDiagnostic> diagnostics;
  final ValueChanged<CustomNodeDiagnostic> onSelected;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 150),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: diagnostics.length,
          itemBuilder: (BuildContext context, int index) {
            final diagnostic = diagnostics[index];
            return ListTile(
              dense: true,
              leading: Icon(
                diagnostic.isError
                    ? Icons.error_outline
                    : Icons.warning_amber_outlined,
                color: diagnostic.isError
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.tertiary,
                size: 18,
              ),
              title: Text(diagnostic.message),
              subtitle: Text(
                'Line ${diagnostic.line}, column ${diagnostic.column}',
              ),
              onTap: () => onSelected(diagnostic),
            );
          },
        ),
      ),
    );
  }
}

class _EditorLoadError extends StatelessWidget {
  const _EditorLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 36,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text(
                'Python source could not be loaded',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Check the backend connection, then retry without leaving the node inspector.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      ),
    );
  }
}
