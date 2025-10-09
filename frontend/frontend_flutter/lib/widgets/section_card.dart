// lib/widgets/section_card.dart
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

  static Widget buildFromDistribution({
    required Map<String, int> data,
    required Color gradientStart,
    required Color gradientEnd,
    bool showPercent = true,
    Map<String, String>? labels,
  }) {
    final total = data.values.fold<int>(0, (a, b) => a + b);
    final entries = data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: entries.map((e) {
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
      elevation: 6,
      shadowColor: Colors.black.withOpacity(0.06),
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min, // adapt height to content
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800)),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 10),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              child: DefaultTextStyle.merge(
                style: theme.textTheme.bodyMedium ?? const TextStyle(),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
    final theme = Theme.of(context);

    return Row(
      children: [
        SizedBox(
            width: 140,
            child: Text(label, style: const TextStyle(fontSize: 13))),
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
                    color: theme.colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
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
                  style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withOpacity(0.65))),
          ],
        ),
      ],
    );
  }
}
