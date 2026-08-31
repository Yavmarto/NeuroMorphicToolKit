import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

/// Transient workspace-opening feedback owned by the workspace feature.
class WorkspaceOpenOverlay extends StatefulWidget {
  const WorkspaceOpenOverlay({super.key});

  @override
  State<WorkspaceOpenOverlay> createState() => _WorkspaceOpenOverlayState();
}

class _WorkspaceOpenOverlayState extends State<WorkspaceOpenOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = NmtkShellTokens.of(context);
    final runningColor = tokens.runningColor;
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.7),
      child: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value;
            return Container(
              width: 320,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: NmtkDesignTokens.dialogShape,
                border: Border.all(color: const Color(0xFF2B3138)),
                gradient: const LinearGradient(
                  colors: [Color(0xFF101215), Color(0xFF1A1E24)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x44000000),
                    blurRadius: 24,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Opening workspace',
                    style: TextStyle(
                      color: tokens.studioPalette.accentForeground,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Obsidian Flow is restoring files, cached previews, and panel state.',
                    style: TextStyle(
                      color: tokens.metadataForeground,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 18),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(tokens.radiusChip),
                    child: SizedBox(
                      height: 10,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Container(color: const Color(0xFF21262D)),
                          FractionallySizedBox(
                            alignment: Alignment(-1 + (t * 2), 0),
                            widthFactor: 0.45,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    runningColor.withValues(alpha: 0),
                                    runningColor,
                                    runningColor.withValues(alpha: 0),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: List.generate(3, (index) {
                      final phase = ((t + (index * 0.18)) % 1.0);
                      final opacity =
                          0.25 + (0.75 * (1 - (phase - 0.5).abs() * 2));
                      return Expanded(
                        child: Container(
                          margin: EdgeInsets.only(right: index == 2 ? 0 : 8),
                          height: 36,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                              tokens.radiusSm,
                            ),
                            color: Color.lerp(
                              const Color(0xFF1B2027),
                              const Color(0xFF233843),
                              opacity,
                            )!,
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
