import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/utils/canvas_palette_search.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_palette_search_field.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_shared_widgets.dart';

/// Which side of an existing node the user pressed `+` on.
///
/// [fromOutput] — the new node will be *downstream*, so the palette offers node
/// types that have at least one **input**, and draws those inputs on the left of
/// each tile (the side the incoming wire will land on).
///
/// [fromInput] — the mirror: candidates need an **output**, drawn on the right.
enum CanvasConnectDirection { fromOutput, fromInput }

/// One selectable port on a palette candidate.
class CanvasConnectPalettePort {
  const CanvasConnectPalettePort({required this.id, required this.label});

  final String id;

  /// Shown next to the dot. Usually the same as [id] — the canvases label ports
  /// by id today — but kept separate so a friendlier label can be supplied
  /// without changing edge identity.
  final String label;
}

/// One candidate node type in the connect palette.
///
/// Deliberately model-agnostic: the pipeline canvas builds these from
/// `PipelineDagNodeType`, the architecture canvas from `NirNodeType`. Note the
/// two canvases have *different, unrelated* `PortType` declarations, so a
/// palette that spoke either model could not serve both.
class CanvasConnectPaletteEntry {
  const CanvasConnectPaletteEntry({
    required this.id,
    required this.label,
    required this.icon,
    required this.accent,
    required this.ports,
  });

  /// Node-type identifier — a `PipelineDagNodeType.name` or a `NirNodeType.id`.
  /// Returned verbatim in [CanvasConnectPaletteResult.entryId].
  final String id;

  final String label;
  final IconData icon;
  final Color accent;

  /// Only the ports on the side that faces the connection — inputs when the
  /// user pressed `+` on an output, outputs when they pressed `+` on an input.
  /// Never empty: callers filter out candidates that cannot connect.
  final List<CanvasConnectPalettePort> ports;
}

/// What the user picked: a node type, and which of its ports to wire to.
class CanvasConnectPaletteResult {
  const CanvasConnectPaletteResult({
    required this.entryId,
    required this.portId,
  });

  final String entryId;
  final String portId;
}

/// Shows the port-anchored "add connected node" palette and resolves to the
/// chosen node type + port, or `null` if the user dismissed it.
///
/// Presentation matches the existing bottom-bar palettes — a modal bottom sheet
/// on compact widths, a centred dialog otherwise.
Future<CanvasConnectPaletteResult?> showCanvasConnectPalette({
  required BuildContext context,
  required CanvasConnectDirection direction,
  required List<CanvasConnectPaletteEntry> entries,
}) {
  assert(
    entries.every((CanvasConnectPaletteEntry e) => e.ports.isNotEmpty),
    'Callers must filter out candidates with no port on the facing side; '
    'an entry with no ports has nothing to connect to.',
  );

  final bool isMobile =
      MediaQuery.sizeOf(context).width < NmtkShellTokens.compactBreakpoint;

  Widget content(BuildContext popupContext) => _CanvasConnectPaletteBody(
    direction: direction,
    entries: entries,
    isMobile: isMobile,
  );

  if (isMobile) {
    return showModalBottomSheet<CanvasConnectPaletteResult>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.8,
            ),
            child: content(sheetContext),
          ),
        );
      },
    );
  }

  return showDialog<CanvasConnectPaletteResult>(
    context: context,
    builder: (BuildContext dialogContext) {
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 620),
          child: content(dialogContext),
        ),
      );
    },
  );
}

class _CanvasConnectPaletteBody extends StatefulWidget {
  const _CanvasConnectPaletteBody({
    required this.direction,
    required this.entries,
    required this.isMobile,
  });

  final CanvasConnectDirection direction;
  final List<CanvasConnectPaletteEntry> entries;
  final bool isMobile;

  @override
  State<_CanvasConnectPaletteBody> createState() =>
      _CanvasConnectPaletteBodyState();
}

class _CanvasConnectPaletteBodyState extends State<_CanvasConnectPaletteBody> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<CanvasConnectPaletteEntry> get _visibleEntries =>
      filterCanvasPaletteItems<CanvasConnectPaletteEntry>(
        widget.entries,
        _query,
        label: (CanvasConnectPaletteEntry e) => e.label,
        keywords: (CanvasConnectPaletteEntry e) => <String>[
          e.id,
          for (final CanvasConnectPalettePort p in e.ports) p.label,
        ],
      );

  void _pick(CanvasConnectPaletteEntry entry, String portId) {
    Navigator.of(
      context,
    ).pop(CanvasConnectPaletteResult(entryId: entry.id, portId: portId));
  }

  void _submitTopResult() {
    final List<CanvasConnectPaletteEntry> visible = _visibleEntries;
    if (visible.isEmpty) return;
    final CanvasConnectPaletteEntry top = visible.first;
    _pick(top, top.ports.first.id);
  }

  @override
  Widget build(BuildContext context) {
    final bool isInputSide =
        widget.direction == CanvasConnectDirection.fromOutput;
    final List<CanvasConnectPaletteEntry> visible = _visibleEntries;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isInputSide ? 'Connect to new node' : 'Add node feeding this input',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            isInputSide
                ? 'Pick the input port to wire into.'
                : 'Pick the output port to wire from.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          CanvasPaletteSearchField(
            controller: _searchController,
            autofocus: !widget.isMobile,
            onChanged: (String value) => setState(() => _query = value),
            onSubmitted: _submitTopResult,
          ),
          const SizedBox(height: 12),
          if (visible.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('No matching nodes'),
            )
          else
            Flexible(
              child: SingleChildScrollView(
                child: GridView.count(
                  crossAxisCount: widget.isMobile ? 2 : 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.35,
                  children: visible
                      .map(
                        (CanvasConnectPaletteEntry entry) =>
                            _CanvasConnectPaletteTile(
                              entry: entry,
                              portsOnLeft: isInputSide,
                              onPickPort: (String portId) =>
                                  _pick(entry, portId),
                            ),
                      )
                      .toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A candidate drawn as a miniature node card, with its facing ports on the
/// edge the wire will attach to. Each port row is its own tap target, so
/// choosing "which port" costs no extra step; tapping the card body takes the
/// first port.
class _CanvasConnectPaletteTile extends StatelessWidget {
  const _CanvasConnectPaletteTile({
    required this.entry,
    required this.portsOnLeft,
    required this.onPickPort,
  });

  final CanvasConnectPaletteEntry entry;

  /// True when the facing ports are inputs (drawn on the left).
  final bool portsOnLeft;

  final ValueChanged<String> onPickPort;

  @override
  Widget build(BuildContext context) {
    final NmtkShellTokens tokens = NmtkShellTokens.of(context);
    final ThemeData theme = Theme.of(context);

    final Widget portColumn = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: portsOnLeft
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.end,
      children: entry.ports
          .map(
            (CanvasConnectPalettePort port) => _PaletteTilePortRow(
              key: ValueKey<String>('palette_port_${entry.id}_${port.id}'),
              label: port.label,
              isInput: portsOnLeft,
              onTap: () => onPickPort(port.id),
            ),
          )
          .toList(),
    );

    final Widget body = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(entry.icon, size: 24, color: entry.accent),
        const SizedBox(height: 6),
        Text(
          entry.label,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );

    return InkWell(
      onTap: () => onPickPort(entry.ports.first.id),
      borderRadius: BorderRadius.circular(tokens.radiusSm),
      child: Container(
        decoration: BoxDecoration(
          color: tokens.utilityPanelBackground,
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          border: Border.all(color: tokens.chromeBorder),
        ),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: portsOnLeft
              ? [portColumn, Expanded(child: body), const SizedBox(width: 8)]
              : [const SizedBox(width: 8), Expanded(child: body), portColumn],
        ),
      ),
    );
  }
}

/// A dot + name pair matching the canvas port styling, tappable as its own
/// target. Non-interactive visually — the dot is a plain circle rather than a
/// [CanvasPortWidget], which owns connection gestures this context has no use
/// for.
class _PaletteTilePortRow extends StatelessWidget {
  const _PaletteTilePortRow({
    super.key,
    required this.label,
    required this.isInput,
    required this.onTap,
  });

  final String label;
  final bool isInput;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final Color fill = isInput
        ? colorScheme.secondaryContainer
        : colorScheme.primaryContainer;
    final Color border = isInput ? colorScheme.secondary : colorScheme.primary;

    final Widget dot = Container(
      width: kCanvasPortRadius * 2,
      height: kCanvasPortRadius * 2,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(color: border, width: 1.5),
      ),
    );

    final Widget text = Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 9),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: isInput
              ? [dot, const SizedBox(width: 4), text]
              : [text, const SizedBox(width: 4), dot],
        ),
      ),
    );
  }
}
