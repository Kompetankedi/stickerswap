import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Düz, net, minimalist ve kurumsal kart bileşeni.
/// Liquid glass, bulanıklık ve neon efektleri tamamen kaldırılmıştır.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double? width;
  final double? height;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.width,
    this.height,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        height: height,
        padding: padding,
        decoration: BoxDecoration(
          color: isDark ? AppTheme.cardDark : AppTheme.cardLight,
          borderRadius: AppTheme.cardRadius,
          border: AppTheme.getBorder(context),
          boxShadow: isDark ? null : AppTheme.lightCardShadow,
        ),
        child: child,
      ),
    );
  }
}

/// Kurumsal kart takma adı (alias)
typedef CorporateCard = GlassCard;
