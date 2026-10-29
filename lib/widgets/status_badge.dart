import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A small pill-shaped badge used for displaying status labels.
class StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const StatusBadge({
    super.key,
    required this.label,
    this.color = AppTheme.success,
    this.icon,
  });

  factory StatusBadge.installed() => const StatusBadge(
        label: 'Yüklü',
        color: AppTheme.success,
        icon: Icons.check_circle_rounded,
      );

  factory StatusBadge.pending() => const StatusBadge(
        label: 'Bekliyor',
        color: AppTheme.warning,
        icon: Icons.schedule_rounded,
      );

  factory StatusBadge.animated() => const StatusBadge(
        label: 'Hareketli',
        color: AppTheme.info,
        icon: Icons.animation_rounded,
      );

  factory StatusBadge.staticType() => const StatusBadge(
        label: 'Statik',
        color: AppTheme.textMuted,
        icon: Icons.image_rounded,
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: AppTheme.chipRadius,
        border: Border.all(color: color.withAlpha(60), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
