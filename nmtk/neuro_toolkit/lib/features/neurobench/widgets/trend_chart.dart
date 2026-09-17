import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

class TrendChart extends StatelessWidget {
  final List<dynamic> history;
  final String metricName;

  const TrendChart({
    super.key,
    required this.history,
    required this.metricName,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = NmtkShellTokens.of(context);

    return Container(
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(tokens.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Trend: $metricName',
            style: Zeta.of(
              context,
            ).textStyles.bodyMedium.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Chart visualisation not available in this build.',
            style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                  color: tokens.metadataForeground,
                  fontSize: 12,
                ),
          ),
          const SizedBox(height: 8),
          if (history.isEmpty)
            Text(
              'No data points recorded.',
              style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                    color: tokens.metadataForeground,
                    fontSize: 12,
                  ),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: history.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '#${index + 1}',
                        style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                              color: tokens.metadataForeground,
                              fontSize: 12,
                            ),
                      ),
                      Text(
                        '${history[index]}',
                        style: Zeta.of(
                          context,
                        ).textStyles.bodyMedium.copyWith(fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
