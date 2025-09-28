import 'package:flutter/material.dart';

class SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
  });

  /// Builds a visual distribution list (label -> int) using a single gradient
  /// color for all bars (dark blue -> black). Colors of individual bars are ignored.
  static Widget buildFromDistribution({
    required Map<String, int> data,
    required Color gradientStart, // e.g. Color(0xFF0A3F8B)
    required Color gradientEnd, // e.g. Colors.black
    bool showPercent = true,
    Map<String, String>? labels,
  }) {
    final total = data.values.fold<int>(0, (a, b) => a + b);
    final entries = data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: entries.mapIndexed<Widget>((i, e) {
        final label = labels != null && labels.containsKey(e.key)
            ? labels[e.key]!
            : e.key;
        final value = e.value;
        final percent = total > 0 ? (value / total) : 0.0;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: _GradientDistributionRow(
            label: label,
            value: value,
            percent: percent,
            gradientStart: gradientStart,
            gradientEnd: gradientEnd,
            showPercent: showPercent,
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 1,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

/// Row showing label, a bar filled with a horizontal linear gradient,
/// and value/percent text on the right.
class _GradientDistributionRow extends StatelessWidget {
  final String label;
  final int value;
  final double percent;
  final Color gradientStart;
  final Color gradientEnd;
  final bool showPercent;

  const _GradientDistributionRow({
    required this.label,
    required this.value,
    required this.percent,
    required this.gradientStart,
    required this.gradientEnd,
    this.showPercent = true,
  });

  @override
  Widget build(BuildContext context) {
    final pctText = '${(percent * 100).round()}%';
    return Row(
      children: [
        SizedBox(
          width: 140,
          child: Text(label, style: const TextStyle(fontSize: 13)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: LayoutBuilder(builder: (ctx, constraints) {
            final fullWidth = constraints.maxWidth;
            final barWidth = (percent * fullWidth).clamp(4.0, fullWidth);
            return Stack(
              children: [
                Container(
                  height: 16,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                // Foreground uses a gradient that fills the whole container width,
                // but we clip it to the variable barWidth to represent the percent.
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    widthFactor: (barWidth / fullWidth).isFinite
                        ? (barWidth / fullWidth)
                        : 0.0,
                    child: Container(
                      height: 16,
                      width: fullWidth,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [gradientStart, gradientEnd],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          }),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(value.toString(),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            if (showPercent)
              Text(pctText,
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ],
        ),
      ],
    );
  }
}

/// Utility extension: mapIndexed for List operations
extension _ListIndexed<E> on List<E> {
  List<T> mapIndexed<T>(T Function(int index, E item) f) {
    final out = <T>[];
    for (var i = 0; i < length; i++) {
      out.add(f(i, this[i]));
    }
    return out;
  }
}
