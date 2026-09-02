import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart' hide AppTheme;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/cnl_focus_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/cnl_line_node_map_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/theme/app_theme.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/pipeline_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/spec_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/l10n/app_localizations.dart';
import 'package:neuro_toolkit/features/neurocnl/services/import_text_file_picker.dart';
import 'package:neuro_toolkit/features/neurocnl/utils/cnl_completion_engine.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/cnl_sentence_builder_dialog.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/cnl_line_highlight_painter.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/template_gallery.dart';

const double _kLineHeight = 20.0;
const EdgeInsets _kEditorContentPadding = EdgeInsets.symmetric(
  horizontal: 12,
  vertical: 12,
);
// ZETA-MIGRATION-EXEMPT: CNL is a monospace code editor — Zeta (IBM Plex
// Sans) ships no monospace text style, so the editor, its syntax-highlight
// TextSpans, line-number gutter, hint, and autocomplete overlay all inherit
// this JetBrains Mono base by design.
const TextStyle _kEditorStyle = TextStyle(
  fontFamily: AppTheme.monospaceFontFamily,
  package: AppTheme.fontPackage,
  fontSize: 13,
  height: _kLineHeight / 13,
  color: AppTheme.textPrimary,
);
final StrutStyle _kEditorStrutStyle = StrutStyle.fromTextStyle(
  _kEditorStyle,
  forceStrutHeight: true,
);
final RegExp _kNumericLiteralPattern = RegExp(r'-?(?:\d+\.?\d*|\.\d+)');

int _lineCountForEditorText(String text) {
  return text.isEmpty ? 1 : '\n'.allMatches(text).length + 1;
}

class _SelectedNumericLiteral {
  const _SelectedNumericLiteral({
    required this.start,
    required this.end,
    required this.text,
    required this.linePreview,
  });

  final int start;
  final int end;
  final String text;
  final String linePreview;
}

/// [TextEditingController] that applies CNL syntax highlighting via
/// [buildTextSpan], eliminating the need for a separate background layer.
class _CnlController extends TextEditingController {
  Map<int, String> _errorMap;

  _CnlController({required String text, Map<int, String>? errorMap})
    : _errorMap = errorMap ?? {},
      super(text: text);

  Map<int, String> get errorMap => _errorMap;
  set errorMap(Map<int, String> value) {
    _errorMap = value;
    notifyListeners();
  }

  static final _tokenPattern = RegExp(
    r'(\bMUST NOT\b|\bMUST\b|\bONLY IF\b|\bIF\b|\bWITH\b|\bDURING\b|\bAFTER\b|\bWITHIN\b|\bBETWEEN\b|\bAND\b|\bBY\b)'
    r'|(\b\d+\.?\d*\b)'
    r'|(\bexceeds\b|\bfire\b|\bemit\b|\bstrengthen\b|\bweaken\b|\bmodulate\b|\bdecay\b|\badapt\b|\bcontain\b|\bproject\b|\binhibit\b|\bmaintain\b|\brepresent\b|\bencode\b|\brespond to\b)'
    r'|(\bseconds\b|\bms\b|\bHz\b|\bdegrees\b)'
    r'|(\binhibitory\b|\bexcitatory\b|\bplastic\b|\bactive\b|\binactive\b|\bmembrane potential\b|\brefractory period\b|\bsynaptic weight\b|\baxonal delay\b)'
    r'|([^A-Za-z0-9]+)'
    r'|(\w+)',
  );

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final lines = text.split('\n');
    final children = <InlineSpan>[];
    for (var i = 0; i < lines.length; i++) {
      if (i > 0) children.add(const TextSpan(text: '\n'));
      children.addAll(
        _highlightLine(lines[i], hasError: _errorMap.containsKey(i)),
      );
    }
    return TextSpan(style: _kEditorStyle, children: children);
  }

  List<TextSpan> _highlightLine(String line, {bool hasError = false}) {
    final decoration = hasError
        ? TextDecoration.underline
        : TextDecoration.none;
    final decorationStyle = hasError ? TextDecorationStyle.wavy : null;
    final decorationColor = hasError ? AppTheme.error : null;

    if (line.trimLeft().startsWith('#')) {
      return [
        TextSpan(
          text: line,
          // ZETA-MIGRATION-EXEMPT: inherits _kEditorStyle monospace base (see above)
          style: TextStyle(
            color: AppTheme.synComment,
            decoration: decoration,
            decorationStyle: decorationStyle,
            decorationColor: decorationColor,
          ),
        ),
      ];
    }

    final spans = <TextSpan>[];
    for (final match in _tokenPattern.allMatches(line)) {
      final token = match.group(0)!;
      Color color;
      if (match.group(1) != null) {
        color = AppTheme.synKeyword; // Indigo
      } else if (match.group(2) != null) {
        color = AppTheme.synNumber; // Cyan
      } else if (match.group(3) != null) {
        color = AppTheme.synVerb; // Emerald
      } else if (match.group(4) != null) {
        color = AppTheme.synUnit; // Slate
      } else if (match.group(5) != null) {
        color = AppTheme.primary; // Sky Blue (Values/Types)
      } else if (match.group(7) != null) {
        color = AppTheme.textPrimary; // White (Subjects)
      } else {
        color = AppTheme.textPrimary;
      }

      spans.add(
        TextSpan(
          text: token,
          // ZETA-MIGRATION-EXEMPT: inherits _kEditorStyle monospace base (see above)
          style: TextStyle(
            color: color,
            decoration: decoration,
            decorationStyle: decorationStyle,
            decorationColor: decorationColor,
          ),
        ),
      );
    }

    if (spans.isEmpty) {
      spans.add(
        TextSpan(
          text: line,
          // ZETA-MIGRATION-EXEMPT: inherits _kEditorStyle monospace base (see above)
          style: TextStyle(
            decoration: decoration,
            decorationStyle: decorationStyle,
            decorationColor: decorationColor,
          ),
        ),
      );
    }
    return spans;
  }
}

/// CNL code editor with syntax highlighting, inline error markers, autocomplete,
/// slot-filling Tab navigation, and a sentence builder dialog.
///
/// Autocomplete covers all 13 CNL concepts via prefix-matching against a full
/// template library. Templates use {slot} markers — Tab navigates between slots
/// after a completion is inserted.
///
/// The + button in the toolbar opens [CnlSentenceBuilderDialog], a guided form
/// that assembles a valid sentence and appends it to the editor.
class CnlEditor extends ConsumerStatefulWidget {
  const CnlEditor({super.key, ImportTextFilePicker? filePicker})
    : filePicker = filePicker ?? const _DefaultImportTextFilePicker();

  final ImportTextFilePicker filePicker;

  @override
  ConsumerState<CnlEditor> createState() => _CnlEditorState();
}

class _DefaultImportTextFilePicker extends ImportTextFilePicker {
  const _DefaultImportTextFilePicker();

  @override
  Future<ImportedTextFile?> pickFile({
    List<String> acceptedExtensions = const <String>['cnl'],
  }) {
    return createImportTextFilePicker().pickFile(
      acceptedExtensions: acceptedExtensions,
    );
  }
}

// CNL sentence templates are defined in CnlCompletionEngine (cnl_completion_engine.dart).
// The engine exposes them as `kAllCnlTemplates` and handles all completion layers.

class _CnlEditorState extends ConsumerState<CnlEditor> {
  late final _CnlController _controller;
  late final FocusNode _focusNode;
  late final UndoHistoryController _undoHistoryController;
  final LayerLink _layerLink = LayerLink();
  final GlobalKey _editorViewportKey = GlobalKey();
  OverlayEntry? _autocompleteOverlay;
  int _selectedCompletionIndex = 0;
  List<CompletionItem> _currentCompletions = const <CompletionItem>[];
  static const _engine = CnlCompletionEngine();
  bool _isImporting = false;

  late final ScrollController _textFieldScrollController;
  late final ScrollController _gutterScrollController;

  @override
  void initState() {
    super.initState();
    _controller = _CnlController(text: ref.read(specTextProvider));
    _focusNode = FocusNode();
    _undoHistoryController = UndoHistoryController();
    _textFieldScrollController = ScrollController();
    _gutterScrollController = ScrollController();
    _controller.addListener(_syncSelectionState);

    _textFieldScrollController.addListener(() {
      if (_gutterScrollController.hasClients) {
        _gutterScrollController.jumpTo(_textFieldScrollController.offset);
      }
      ref
          .read(workspaceProvider.notifier)
          .updateActiveFileScroll(_textFieldScrollController.offset);
    });
  }

  @override
  void dispose() {
    _dismissAutocomplete();
    _controller.removeListener(_syncSelectionState);
    _controller.dispose();
    _focusNode.dispose();
    _undoHistoryController.dispose();
    _textFieldScrollController.dispose();
    _gutterScrollController.dispose();
    super.dispose();
  }

  Map<int, String> _buildErrorMap() {
    final parseResult = ref.read(pipelineProvider).parseResult;
    if (parseResult == null) return {};
    final errors = <int, String>{};
    for (final sentence in parseResult.sentences) {
      if (!sentence.valid && sentence.error != null) {
        errors[sentence.line - 1] = sentence.error!;
      }
    }
    return errors;
  }

  void _onChanged(String text) {
    _checkAutocomplete(text);
    // Sets the optimistic echo instantly and debounces the canonical-doc
    // commit (which itself triggers parse/validate and canvas mirroring) —
    // one call now covers what used to be two separate debounced paths.
    ref.read(specTextProvider.notifier).update(text);
  }

  void _syncSelectionState() {
    final selection = _controller.selection;
    final cursorOffset = selection.extentOffset < 0
        ? 0
        : selection.extentOffset;
    final selectionBase = selection.baseOffset < 0 ? 0 : selection.baseOffset;
    final selectionExtent = selection.extentOffset < 0
        ? 0
        : selection.extentOffset;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(workspaceProvider.notifier)
          .updateActiveFileSelection(
            cursorOffset: cursorOffset,
            selectionBase: selectionBase,
            selectionExtent: selectionExtent,
          );
      _publishCursorFocus();
      setState(() {});
    });
  }

  int _cursorLine() {
    final int offset = _controller.selection.extentOffset
        .clamp(0, _controller.text.length)
        .toInt();
    return '\n'.allMatches(_controller.text.substring(0, offset)).length + 1;
  }

  void _publishCursorFocus() {
    final int line = _cursorLine();
    final lineToNode = ref.read(cnlLineNodeMapProvider).lineToNode;
    ref
        .read(cnlFocusProvider.notifier)
        .setFocusedLine(lineToNode.containsKey(line) ? line : null);
  }

  void _focusEditorLine(int line) {
    final Map<String, int> nodeToLine = ref
        .read(cnlLineNodeMapProvider)
        .nodeToLine;
    if (!nodeToLine.values.contains(line)) return;

    final String text = _controller.text;
    var lineStart = 0;
    for (var index = 1; index < line; index += 1) {
      final nextBreak = text.indexOf('\n', lineStart);
      if (nextBreak == -1) return;
      lineStart = nextBreak + 1;
    }
    _controller.selection = TextSelection.collapsed(offset: lineStart);
    _focusNode.requestFocus();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_textFieldScrollController.hasClients) return;
      final double? lineOffset = _lineOffsetFor(line);
      if (lineOffset == null) return;
      final position = _textFieldScrollController.position;
      final target = (lineOffset - position.viewportDimension / 3)
          .clamp(0.0, position.maxScrollExtent)
          .toDouble();
      _textFieldScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    });
  }

  double? _lineOffsetFor(int? line) {
    if (line == null || line < 1) return null;
    final RenderBox? viewport =
        _editorViewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (viewport == null || !viewport.hasSize) return null;

    final String text = _controller.text;
    var lineStart = 0;
    for (var index = 1; index < line; index += 1) {
      final nextBreak = text.indexOf('\n', lineStart);
      if (nextBreak == -1) return null;
      lineStart = nextBreak + 1;
    }
    final painter =
        TextPainter(
          text: TextSpan(style: _kEditorStyle, text: text),
          textDirection: TextDirection.ltr,
          strutStyle: _kEditorStrutStyle,
        )..layout(
          maxWidth: (viewport.size.width - _kEditorContentPadding.horizontal)
              .clamp(0.0, double.infinity),
        );
    final offset = painter
        .getOffsetForCaret(TextPosition(offset: lineStart), Rect.zero)
        .dy;
    painter.dispose();
    return offset;
  }

  _SelectedNumericLiteral? _selectedNumericLiteral() {
    final text = _controller.text;
    final selection = _controller.selection;
    if (text.isEmpty ||
        !selection.isValid ||
        selection.baseOffset < 0 ||
        selection.extentOffset < 0) {
      return null;
    }

    final selectionStart = selection.start.clamp(0, text.length).toInt();
    final selectionEnd = selection.end.clamp(0, text.length).toInt();
    final isCollapsed = selectionStart == selectionEnd;

    for (final match in _kNumericLiteralPattern.allMatches(text)) {
      final containsCaret =
          isCollapsed &&
          selectionStart >= match.start &&
          selectionStart <= match.end;
      final containsSelection =
          !isCollapsed &&
          selectionStart >= match.start &&
          selectionEnd <= match.end;
      if (!containsCaret && !containsSelection) {
        continue;
      }

      final lineStart = text.lastIndexOf('\n', match.start - 1) + 1;
      final lineEnd = text.indexOf('\n', match.end);
      final normalizedLineEnd = lineEnd == -1 ? text.length : lineEnd;
      return _SelectedNumericLiteral(
        start: match.start,
        end: match.end,
        text: match.group(0)!,
        linePreview: text.substring(lineStart, normalizedLineEnd).trim(),
      );
    }
    return null;
  }

  Future<void> _openNumericEditor() async {
    final selectedNumeric = _selectedNumericLiteral();
    if (selectedNumeric == null) {
      return;
    }

    final replacement = await showDialog<String>(
      context: context,
      builder: (context) => _NumericLiteralDialog(
        initialValue: selectedNumeric.text,
        linePreview: selectedNumeric.linePreview,
      ),
    );
    if (!mounted ||
        replacement == null ||
        replacement == selectedNumeric.text) {
      return;
    }

    final currentText = _controller.text;
    final updatedText = currentText.replaceRange(
      selectedNumeric.start,
      selectedNumeric.end,
      replacement,
    );
    _controller.value = TextEditingValue(
      text: updatedText,
      selection: TextSelection.collapsed(
        offset: selectedNumeric.start + replacement.length,
      ),
    );
    _onChanged(updatedText);
  }

  // ── Autocomplete ─────────────────────────────────────────────────────────

  void _checkAutocomplete(String text) {
    final int cursorPos = _controller.selection.baseOffset;
    if (cursorPos < 0) {
      _dismissAutocomplete();
      return;
    }

    // Read live node labels from canvas for layer-3 node-name completions.
    // n.label is String? — whereType<String>() drops nulls safely.
    final Iterable<String> nodeLabels = ref
        .read(canvasProvider)
        .graph
        .nodes
        .map((n) => n.label)
        .whereType<String>()
        .where((l) => l.isNotEmpty);

    final List<CompletionItem> matches = _engine.suggest(
      text,
      cursorPos,
      nodeLabels,
    );

    if (matches.isEmpty) {
      _dismissAutocomplete();
      return;
    }
    _showAutocomplete(matches);
  }

  void _showAutocomplete(List<CompletionItem> completions) {
    _currentCompletions = completions;
    _selectedCompletionIndex = 0;
    _dismissAutocomplete();

    _autocompleteOverlay = OverlayEntry(
      builder: (context) => _AutocompleteOverlay(
        completions: _currentCompletions,
        selectedIndex: _selectedCompletionIndex,
        layerLink: _layerLink,
        onSelect: _insertCompletion,
        onDismiss: _dismissAutocomplete,
      ),
    );
    Overlay.of(context).insert(_autocompleteOverlay!);
  }

  void _dismissAutocomplete() {
    _autocompleteOverlay?.remove();
    _autocompleteOverlay = null;
    _currentCompletions = const <CompletionItem>[];
  }

  /// Insert [item] at the current cursor position.
  ///
  /// - **Template items**: replace the entire current line from its start up to
  ///   the cursor, then navigate to the first `{slot}` marker.
  /// - **Token / node items**: replace only the partial last token on the line,
  ///   then position the cursor after the inserted word (and append a space so
  ///   the next word can be typed immediately).
  void _insertCompletion(CompletionItem item) {
    final int cursorPos = _controller.selection.baseOffset;
    if (cursorPos < 0) return;

    final String text = _controller.text;

    if (item.source == CompletionSource.template) {
      // Template: replace from line start to cursor.
      final int lineStart =
          text.lastIndexOf('\n', cursorPos > 0 ? cursorPos - 1 : 0) + 1;
      final String newText =
          text.substring(0, lineStart) + item.text + text.substring(cursorPos);
      _controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(
          offset: lineStart + item.text.length,
        ),
      );
      _dismissAutocomplete();
      _onChanged(newText);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _navigateToFirstSlotFrom(lineStart);
      });
    } else {
      // Token / node-name: replace only the partial last word.
      final String beforeCursor = text.substring(0, cursorPos);
      final int wordStart = beforeCursor.lastIndexOf(RegExp(r'\s')) + 1;
      final String insertion = '${item.text} ';
      final String newText =
          text.substring(0, wordStart) + insertion + text.substring(cursorPos);
      _controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(
          offset: wordStart + insertion.length,
        ),
      );
      _dismissAutocomplete();
      _onChanged(newText);
    }
  }

  /// Select the first {slot} marker at or after [from] in the current text.
  void _navigateToFirstSlotFrom(int from) {
    final text = _controller.text;
    for (final m in RegExp(r'\{[^}]+\}').allMatches(text)) {
      if (m.start >= from) {
        _controller.selection = TextSelection(
          baseOffset: m.start,
          extentOffset: m.end,
        );
        return;
      }
    }
  }

  /// Select the next {slot} marker after the current cursor/selection.
  /// Returns true if a slot was found and selected.
  bool _tryNavigateToNextSlot() {
    final text = _controller.text;
    final from = _controller.selection.extentOffset;
    if (from < 0) return false;
    for (final m in RegExp(r'\{[^}]+\}').allMatches(text)) {
      if (m.start >= from) {
        _controller.selection = TextSelection(
          baseOffset: m.start,
          extentOffset: m.end,
        );
        return true;
      }
    }
    return false;
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // Autocomplete overlay navigation.
    if (_autocompleteOverlay != null) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        _dismissAutocomplete();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        setState(() {
          _selectedCompletionIndex =
              (_selectedCompletionIndex + 1) % _currentCompletions.length;
        });
        _autocompleteOverlay!.markNeedsBuild();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        setState(() {
          _selectedCompletionIndex =
              (_selectedCompletionIndex - 1 + _currentCompletions.length) %
              _currentCompletions.length;
        });
        _autocompleteOverlay!.markNeedsBuild();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.tab ||
          event.logicalKey == LogicalKeyboardKey.enter) {
        _insertCompletion(_currentCompletions[_selectedCompletionIndex]);
        return KeyEventResult.handled;
      }
    }

    // Tab slot navigation when no autocomplete overlay is open.
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      if (_tryNavigateToNextSlot()) return KeyEventResult.handled;
    }

    final modifierPressed =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (modifierPressed && event.logicalKey == LogicalKeyboardKey.keyE) {
      if (_selectedNumericLiteral() != null) {
        _openNumericEditor();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  // ── Sentence builder ─────────────────────────────────────────────────────

  Future<void> _openSentenceBuilder() async {
    final sentence = await showDialog<String>(
      context: context,
      builder: (_) => const CnlSentenceBuilderDialog(),
    );
    if (sentence != null && mounted) {
      _insertBuiltSentence(sentence);
    }
  }

  void _insertBuiltSentence(String sentence) {
    final text = _controller.text;
    final newText = text.isEmpty || text.endsWith('\n')
        ? text + sentence
        : '$text\n$sentence';
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
    _onChanged(newText);
  }

  // ── Load CNL file ────────────────────────────────────────────────────────

  Future<void> _importFile() async {
    if (!await _confirmReplaceUnsavedChanges()) return;

    setState(() => _isImporting = true);
    try {
      final importedFile = await widget.filePicker.pickFile();
      if (importedFile == null || !mounted) return;
      await ref
          .read<SpecTextController>(specTextProvider.notifier)
          .set(importedFile.text);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('CNL file load failed: $error'),
            showCloseIcon: true,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Future<bool> _confirmReplaceUnsavedChanges() async {
    final activeFile = ref.read(workspaceProvider).activeFile;
    if (activeFile == null || !activeFile.dirty) return true;

    final shouldReplace = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Load CNL file'),
        content: Text(
          'Loading a file will replace unsaved changes in ${activeFile.name}.',
        ),
        actions: [
          ZetaButton.text(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            label: 'Keep editing',
          ),
          ZetaButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            label: 'Load file',
          ),
        ],
      ),
    );
    return shouldReplace ?? false;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    ref.listen<String>(specTextProvider, (prev, next) {
      if (_controller.text != next) {
        _controller.text = next;
        final activeFile = ref.read(workspaceProvider).activeFile;
        final extent = activeFile == null
            ? next.length
            : activeFile.selectionExtent.clamp(0, next.length).toInt();
        final base = activeFile == null
            ? extent
            : activeFile.selectionBase.clamp(0, next.length).toInt();
        _controller.selection = TextSelection(
          baseOffset: base,
          extentOffset: extent,
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_textFieldScrollController.hasClients || activeFile == null) {
            return;
          }
          final offset = activeFile.scrollOffset
              .clamp(0, _textFieldScrollController.position.maxScrollExtent)
              .toDouble();
          _textFieldScrollController.jumpTo(offset);
        });
      }
    });

    ref.listen(workspaceProvider.select((state) => state.activeFileId), (_, _) {
      final activeFile = ref.read(workspaceProvider).activeFile;
      if (activeFile == null) {
        return;
      }
      _controller.selection = TextSelection(
        baseOffset: activeFile.selectionBase
            .clamp(0, _controller.text.length)
            .toInt(),
        extentOffset: activeFile.selectionExtent
            .clamp(0, _controller.text.length)
            .toInt(),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_textFieldScrollController.hasClients) {
          _textFieldScrollController.jumpTo(
            activeFile.scrollOffset
                .clamp(0, _textFieldScrollController.position.maxScrollExtent)
                .toDouble(),
          );
        }
      });
    });

    ref.listen(pipelineProvider, (_, _) {
      _controller.errorMap = _buildErrorMap();
    });

    ref.listen(cnlLineNodeMapProvider, (_, _) {
      _publishCursorFocus();
    });

    ref.listen(cnlFocusProvider.select((focus) => focus.focusedNodeId), (
      previous,
      nodeId,
    ) {
      if (nodeId == null || nodeId == previous) return;
      final int? line = ref.read(cnlLineNodeMapProvider).nodeToLine[nodeId];
      if (line != null) _focusEditorLine(line);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildToolbar(context),
        Expanded(child: _buildEditor(context)),
      ],
    );
  }

  Widget _buildToolbar(BuildContext context) {
    final selectedNumeric = _selectedNumericLiteral();
    final undoButtons = ValueListenableBuilder<UndoHistoryValue>(
      valueListenable: _undoHistoryController,
      builder: (context, historyValue, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: 'Undo (Ctrl/Cmd+Z)',
              child: ZetaIconButton.text(
                icon: ZetaIcons.undo,
                size: ZetaWidgetSize.small,
                semanticLabel: 'Undo (Ctrl/Cmd+Z)',
                onPressed: historyValue.canUndo
                    ? _undoHistoryController.undo
                    : null,
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: 'Redo (Ctrl/Cmd+Shift+Z)',
              child: ZetaIconButton.text(
                icon: ZetaIcons.redo,
                size: ZetaWidgetSize.small,
                semanticLabel: 'Redo (Ctrl/Cmd+Shift+Z)',
                onPressed: historyValue.canRedo
                    ? _undoHistoryController.redo
                    : null,
              ),
            ),
          ],
        );
      },
    );
    final actionsRow = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (selectedNumeric != null) ...[
            Tooltip(
              message: 'Edit selected number (Ctrl/Cmd+E)',
              child: ZetaButton.text(
                onPressed: _openNumericEditor,
                leadingIcon: ZetaIcons.tune,
                label: 'Edit ${selectedNumeric.text}',
              ),
            ),
            const SizedBox(width: 8),
          ],
          undoButtons,
          const SizedBox(width: 8),
          Tooltip(
            message: 'Show templates',
            child: ZetaIconButton.text(
              icon: Icons
                  .auto_awesome, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
              size: ZetaWidgetSize.small,
              semanticLabel: 'Show templates',
              onPressed: () => TemplateGallery.show(context),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Load CNL file',
            child: ZetaIconButton.text(
              icon: ZetaIcons.upload_file,
              size: ZetaWidgetSize.small,
              semanticLabel: 'Load CNL file',
              onPressed: _isImporting ? null : _importFile,
            ),
          ),
          const SizedBox(width: 8),
          _LineCountBadge(controller: _controller),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Add CNL sentence',
            child: ZetaIconButton.text(
              icon: ZetaIcons.add_circle_outline,
              size: ZetaWidgetSize.small,
              semanticLabel: 'Add CNL sentence',
              onPressed: _openSentenceBuilder,
            ),
          ),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(children: [Flexible(child: actionsRow)]),
    );
  }

  Widget _buildEditor(BuildContext context) {
    final focus = ref.watch(cnlFocusProvider);
    final lineMap = ref.watch(cnlLineNodeMapProvider);
    final int? focusedLine =
        focus.focusedLine ?? lineMap.nodeToLine[focus.focusedNodeId];
    final tokens = NmtkShellTokens.of(context);
    return Container(
      color: AppTheme.background,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // text area width = full width - gutter (40px) - content padding horizontal (12*2)
          final textAreaWidth =
              (constraints.maxWidth - 40 - _kEditorContentPadding.horizontal)
                  .clamp(0.0, double.infinity);
          return Focus(
            onKeyEvent: _handleKeyEvent,
            child: CompositedTransformTarget(
              link: _layerLink,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildGutter(textAreaWidth),
                  Expanded(
                    child: Stack(
                      key: _editorViewportKey,
                      fit: StackFit.expand,
                      children: [
                        IgnorePointer(
                          child: AnimatedBuilder(
                            animation: _textFieldScrollController,
                            builder: (context, _) => CustomPaint(
                              painter: CnlLineHighlightPainter(
                                lineOffset: _lineOffsetFor(focusedLine),
                                lineHeight: _kLineHeight,
                                scrollOffset:
                                    _textFieldScrollController.hasClients
                                    ? _textFieldScrollController.offset
                                    : 0,
                                paddingTop: _kEditorContentPadding.top,
                                accentColor: tokens.studioPalette.accent,
                                cornerRadius: tokens.radiusSm,
                              ),
                            ),
                          ),
                        ),
                        Semantics(
                          label: 'CNL Code Editor',
                          // NOTE: Reverted from ZetaTextInput back to Material
                          // TextField. ZetaTextInput in zeta_flutter 1.4.5 is a
                          // single-line form field — it does not expose
                          // maxLines/expands/scrollController and wraps its inner
                          // TextField in a fixed-height SizedBox, which made the
                          // multi-line CNL spec invisible even when the
                          // controller held content. See Pattern B5 in
                          // .kiro/specs/full-zeta-migration/design.md (monospace
                          // / code-editor cases keep a raw TextField).
                          child: TextField(
                            controller: _controller,
                            focusNode: _focusNode,
                            scrollController: _textFieldScrollController,
                            maxLines: null,
                            expands: true,
                            onChanged: _onChanged,
                            undoController: _undoHistoryController,
                            style: _kEditorStyle,
                            strutStyle: _kEditorStrutStyle,
                            textAlignVertical: TextAlignVertical.top,
                            cursorColor: AppTheme.primary,
                            decoration: const InputDecoration(
                              contentPadding: _kEditorContentPadding,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                              isDense: true,
                              hintText:
                                  '# Type your CNL spec here or load a template\u2026',
                              // ZETA-MIGRATION-EXEMPT: monospace editor hint, mirrors _kEditorStyle
                              hintStyle: TextStyle(
                                fontFamily: AppTheme.monospaceFontFamily,
                                package: AppTheme.fontPackage,
                                fontSize: 13,
                                height: _kLineHeight / 13,
                                color: AppTheme.synComment,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  List<_GutterLineData> _computeGutterLines(String text, double textAreaWidth) {
    final logicalLines = text.isEmpty ? <String>[''] : text.split('\n');
    final result = <_GutterLineData>[];
    for (var i = 0; i < logicalLines.length; i++) {
      double visualHeight = _kLineHeight;
      if (textAreaWidth > 0) {
        final lineText = logicalLines[i];
        final painter = TextPainter(
          text: TextSpan(
            style: _kEditorStyle,
            text: lineText.isEmpty ? ' ' : lineText,
          ),
          textDirection: TextDirection.ltr,
          strutStyle: _kEditorStrutStyle,
        );
        painter.layout(maxWidth: textAreaWidth);
        // Round to nearest integer visual row count, minimum 1.
        final rowCount = (painter.height / _kLineHeight).round().clamp(1, 500);
        visualHeight = rowCount * _kLineHeight;
        painter.dispose();
      }
      result.add(
        _GutterLineData(
          logicalIndex: i,
          visualHeight: visualHeight,
          hasError: _controller.errorMap.containsKey(i),
        ),
      );
    }
    return result;
  }

  Widget _buildGutter(double textAreaWidth) {
    return Container(
      key: const ValueKey('cnl-editor-gutter'),
      width: 40,
      color: AppTheme.surface,
      child: SingleChildScrollView(
        controller: _gutterScrollController,
        physics: const NeverScrollableScrollPhysics(),
        child: ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (context, value, _) {
            final gutterLines = _computeGutterLines(value.text, textAreaWidth);
            return Padding(
              padding: EdgeInsets.only(
                top: _kEditorContentPadding.top,
                bottom: _kEditorContentPadding.bottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: gutterLines.map((gl) {
                  final hasError = gl.hasError;
                  // Show line number at the top of the visual block; if the
                  // line wraps, the remaining visual rows have no number.
                  final lineNumWidget = SizedBox(
                    height: _kLineHeight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        key: ValueKey('cnl-line-${gl.logicalIndex + 1}'),
                        '${gl.logicalIndex + 1}',
                        // ZETA-MIGRATION-EXEMPT: monospace gutter line number, mirrors _kEditorStyle
                        style: TextStyle(
                          fontFamily: AppTheme.monospaceFontFamily,
                          package: AppTheme.fontPackage,
                          fontSize: 13,
                          height: _kLineHeight / 13,
                          color: hasError
                              ? AppTheme.error
                              : AppTheme.textSecondary.withValues(alpha: 0.5),
                          fontWeight: hasError
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  );
                  // Wrap with tooltip for errors.
                  Widget numberLabel = hasError
                      ? Tooltip(
                          message: _controller.errorMap[gl.logicalIndex]!,
                          preferBelow: true,
                          textStyle: Zeta.of(context).textStyles.bodyXSmall
                              .copyWith(
                                color: Zeta.of(context).colors.mainInverse,
                              ),
                          decoration: BoxDecoration(
                            color: AppTheme.error.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(
                              NmtkShellTokens.of(context).radiusSm,
                            ),
                          ),
                          child: lineNumWidget,
                        )
                      : lineNumWidget;
                  // If the line wraps to multiple visual rows, place the
                  // number at the top, with empty space below for wrapped rows.
                  if (gl.visualHeight > _kLineHeight) {
                    return SizedBox(
                      height: gl.visualHeight,
                      child: Align(
                        alignment: Alignment.topRight,
                        child: numberLabel,
                      ),
                    );
                  }
                  return numberLabel;
                }).toList(),
              ),
            );
          },
        ),
      ),
    );
  }
}

// \u2500\u2500 Gutter line data \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500

class _GutterLineData {
  const _GutterLineData({
    required this.logicalIndex,
    required this.visualHeight,
    required this.hasError,
  });

  /// Zero-based logical line index.
  final int logicalIndex;

  /// Visual height in pixels; may be > [_kLineHeight] when the line wraps.
  final double visualHeight;

  /// Whether this line has an associated error marker.
  final bool hasError;
}

/// Shows the current line count.
class _LineCountBadge extends StatelessWidget {
  final TextEditingController controller;

  const _LineCountBadge({required this.controller});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final text = value.text;
        final lines = _lineCountForEditorText(text);
        final nonEmpty = text
            .split('\n')
            .where((l) => l.trim().isNotEmpty && !l.trimLeft().startsWith('#'))
            .length;
        return Text(
          '$nonEmpty ${l10n.sentences} \u00b7 $lines ${l10n.lines}',
          style: Zeta.of(
            context,
          ).textStyles.bodyXSmall.copyWith(color: AppTheme.textSecondary),
        );
      },
    );
  }
}

class _NumericLiteralDialog extends StatefulWidget {
  const _NumericLiteralDialog({
    required this.initialValue,
    required this.linePreview,
  });

  final String initialValue;
  final String linePreview;

  @override
  State<_NumericLiteralDialog> createState() => _NumericLiteralDialogState();
}

class _NumericLiteralDialogState extends State<_NumericLiteralDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty || double.tryParse(trimmed) == null) {
      setState(() {
        _errorText = 'Enter a valid number.';
      });
      return;
    }
    Navigator.of(context).pop(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(
          NmtkShellTokens.of(context).radiusMd,
        ),
      ),
      title: const Text('Edit number'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.linePreview,
            style: Zeta.of(context).textStyles.bodyXSmall.copyWith(
              color: AppTheme.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          NmtkTextInput(
            controller: _controller,
            // ZETA-MIGRATION-TODO: autofocus dropped
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            label: 'Value',
            errorText: _errorText,
            hintText:
                'Updates the number in the CNL editor and reruns parse/validate.',
            // ZETA-MIGRATION-TODO: border has no ZetaTextInput equivalent
            // ZETA-MIGRATION-TODO: onSubmitted dropped
          ),
        ],
      ),
      actions: [
        ZetaButton.text(
          onPressed: () => Navigator.of(context).pop(),
          label: 'Cancel',
        ),
        ZetaButton(onPressed: _submit, label: 'Apply'),
      ],
    );
  }
}

// ── Regex for rendering slot markers and keywords in the overlay ──────────
final _kOverlayTokenPattern = RegExp(
  r'\{[^}]+\}'
  r'|\bMUST NOT\b|\bMUST\b|\bONLY IF\b|\bIF\b|\bWITH\b'
  r'|\bDURING\b|\bAFTER\b|\bWITHIN\b|\bBETWEEN\b|\bAND\b|\bBY\b',
);

List<TextSpan> _buildTemplateSpans(String template, bool isSelected) {
  final spans = <TextSpan>[];
  int last = 0;
  for (final m in _kOverlayTokenPattern.allMatches(template)) {
    if (m.start > last) {
      spans.add(
        TextSpan(
          text: template.substring(last, m.start),
          // ZETA-MIGRATION-EXEMPT: completion overlay inherits the monospace base set by its parent TextSpan
          style: TextStyle(
            color: isSelected ? AppTheme.primary : AppTheme.textPrimary,
          ),
        ),
      );
    }
    final token = m.group(0)!;
    final isSlot = token.startsWith('{');
    spans.add(
      TextSpan(
        text: token,
        // ZETA-MIGRATION-EXEMPT: completion overlay inherits the monospace base set by its parent TextSpan
        style: TextStyle(
          color: isSlot ? AppTheme.synNumber : AppTheme.synKeyword,
          fontStyle: isSlot ? FontStyle.italic : FontStyle.normal,
          fontWeight: isSlot ? FontWeight.normal : FontWeight.w600,
        ),
      ),
    );
    last = m.end;
  }
  if (last < template.length) {
    spans.add(
      TextSpan(
        text: template.substring(last),
        // ZETA-MIGRATION-EXEMPT: completion overlay inherits the monospace base set by its parent TextSpan
        style: TextStyle(
          color: isSelected ? AppTheme.primary : AppTheme.textPrimary,
        ),
      ),
    );
  }
  return spans;
}

/// Short badge label for a [CompletionSource].
String _sourceBadgeLabel(CompletionSource source) {
  switch (source) {
    case CompletionSource.template:
      return 'template';
    case CompletionSource.token:
      return 'keyword';
    case CompletionSource.node:
      return 'node';
  }
}

Color _sourceBadgeColor(CompletionSource source) {
  switch (source) {
    case CompletionSource.template:
      return AppTheme.synKeyword;
    case CompletionSource.token:
      return AppTheme.synVerb;
    case CompletionSource.node:
      return AppTheme.primary;
  }
}

/// Autocomplete overlay positioned near the editor cursor area.
class _AutocompleteOverlay extends StatelessWidget {
  final List<CompletionItem> completions;
  final int selectedIndex;
  final LayerLink layerLink;
  final ValueChanged<CompletionItem> onSelect;
  final VoidCallback onDismiss;

  const _AutocompleteOverlay({
    required this.completions,
    required this.selectedIndex,
    required this.layerLink,
    required this.onSelect,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: onDismiss,
            behavior: HitTestBehavior.translucent,
          ),
        ),
        CompositedTransformFollower(
          link: layerLink,
          showWhenUnlinked: false,
          offset: const Offset(48, 40),
          child: Material(
            elevation: 0,
            borderRadius: BorderRadius.circular(
              NmtkShellTokens.of(context).radiusSm,
            ),
            color: AppTheme.surface,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 560, maxHeight: 280),
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.border),
                borderRadius: BorderRadius.circular(
                  NmtkShellTokens.of(context).radiusSm,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header hint
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
                    child: Row(
                      children: [
                        const Icon(
                          ZetaIcons.arrow_forward,
                          size: 12,
                          color: AppTheme.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Tab / Enter to insert  \u2022  \u2191\u2193 to navigate  \u2022  Esc to dismiss',
                            style: Zeta.of(context).textStyles.bodyXSmall
                                .copyWith(
                                  fontSize: 10,
                                  color: AppTheme.textSecondary,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: AppTheme.border),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: completions.length,
                      itemBuilder: (context, index) {
                        final item = completions[index];
                        final isSelected = index == selectedIndex;
                        return InkWell(
                          onTap: () => onSelect(item),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7,
                            ),
                            color: isSelected
                                ? AppTheme.primary.withValues(alpha: 0.12)
                                : Colors.transparent,
                            child: Row(
                              children: [
                                // Completion text
                                Expanded(
                                  child: RichText(
                                    text: TextSpan(
                                      // ZETA-MIGRATION-EXEMPT: monospace completion snippet, mirrors _kEditorStyle
                                      style: const TextStyle(
                                        fontFamily:
                                            AppTheme.monospaceFontFamily,
                                        package: AppTheme.fontPackage,
                                        fontSize: 12.5,
                                      ),
                                      children:
                                          item.source ==
                                              CompletionSource.template
                                          ? _buildTemplateSpans(
                                              item.text,
                                              isSelected,
                                            )
                                          : [
                                              TextSpan(
                                                text: item.text,
                                                // ZETA-MIGRATION-EXEMPT: inherits the monospace completion base above
                                                style: TextStyle(
                                                  color: isSelected
                                                      ? AppTheme.primary
                                                      : AppTheme.textPrimary,
                                                ),
                                              ),
                                            ],
                                    ),
                                  ),
                                ),
                                // Source badge
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _sourceBadgeColor(
                                      item.source,
                                    ).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(
                                      NmtkShellTokens.of(context).radiusSm,
                                    ),
                                  ),
                                  child: Text(
                                    _sourceBadgeLabel(item.source),
                                    style: Zeta.of(context)
                                        .textStyles
                                        .labelSmall
                                        .copyWith(
                                          fontSize: 9,
                                          color: _sourceBadgeColor(item.source),
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
