import 'package:flutter/material.dart';

/// Coloured pill badge used inside [StudentAssignmentCard]. Note: this is
/// internal to the neat/dark exploration tree and is distinct from the public
/// NMTK `NmtkStatusBadge` widget.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.label, required this.color, required this.bg});
  final String label;
  final Color color, bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: ShapeDecoration(color: bg, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2))),
      child: Text(label, style: TextStyle(color: color, fontSize: 12, fontFamily: 'Inter', fontWeight: FontWeight.w600, height: 1.17)),
    );
  }
}
