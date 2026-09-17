import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

class DownloadProgressBar extends StatelessWidget {
  const DownloadProgressBar({super.key, this.progress, this.sizeBytes});

  final double? progress;
  final int? sizeBytes;

  @override
  Widget build(BuildContext context) {
    final colors = Zeta.of(context).colors;
    if (progress != null) {
      final label = (sizeBytes != null && sizeBytes! > 0)
          ? '${_formatBytesStatic((progress! * sizeBytes!).toInt())} / ${_formatBytesStatic(sizeBytes!)}'
          : '${(progress! * 100).toStringAsFixed(0)}%';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(
            value: progress!.clamp(0.0, 1.0),
            backgroundColor: colors.surfaceHover,
            valueColor: AlwaysStoppedAnimation(colors.mainPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colors.mainPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(
          backgroundColor: colors.surfaceHover,
          valueColor: AlwaysStoppedAnimation(colors.mainPrimary),
        ),
        const SizedBox(height: 4),
        Text(
          'Downloading…',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colors.mainPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

String _formatBytesStatic(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}
