import 'package:flutter/material.dart';

/// Header row for the workflow platform-comparison table.

class TableHeaderRow extends StatelessWidget {
  const TableHeaderRow({super.key});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );
    return Row(
      children: [
        Expanded(flex: 3, child: Text('Platform', style: style)),
        Expanded(
          flex: 2,
          child: Text('Best Acc', style: style, textAlign: TextAlign.end),
        ),
        Expanded(
          flex: 2,
          child: Text('Best Loss', style: style, textAlign: TextAlign.end),
        ),
        Expanded(
          flex: 2,
          child: Text('Final Loss', style: style, textAlign: TextAlign.end),
        ),
      ],
    );
  }
}
