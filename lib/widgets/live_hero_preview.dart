import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/telegram_sticker.dart';
import '../services/sticker_export_orchestrator.dart';
import '../theme/app_theme.dart';
import 'animated_sticker_player.dart';
import 'gradient_button.dart';

/// Displays a live looping preview stage for the currently focused sticker
/// in animated (`.tgs`) or video (`.webm`) packs.
class LiveHeroPreview extends StatelessWidget {
  final StickerExportOrchestrator orchestrator;
  final VoidCallback? onInspectSticker;

  const LiveHeroPreview({
    super.key,
    required this.orchestrator,
    this.onInspectSticker,
  });

  @override
  Widget build(BuildContext context) {
    final set = orchestrator.stickerSet;
    if (!set.isAnimated && !set.isVideo) {
      return const SizedBox.shrink();
    }

    return ListenableBuilder(
      listenable: Listenable.merge([
        orchestrator.activePreviewSticker,
        orchestrator.mediaCacheVersion,
      ]),
      builder: (context, _) {
        final active =
            orchestrator.activePreviewSticker.value ?? set.stickers.firstOrNull;
        if (active == null) return const SizedBox.shrink();

        final isDark = AppTheme.isDark(context);
        final thumbId = active.thumbFileId ?? active.fileId;
        final thumbBytes = orchestrator.thumbnails[thumbId];
        final activeIndex = orchestrator.filteredStickers.indexOf(active);
        final badgeColor =
            set.isVideo ? AppTheme.accentSecondary : AppTheme.accentPrimary;

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.cardDark : AppTheme.cardLight,
            borderRadius: AppTheme.cardRadius,
            border: AppTheme.getBorder(context),
            boxShadow: isDark ? null : AppTheme.lightCardShadow,
          ),
          child: Row(
            children: [
              Container(
                width: 104,
                height: 104,
                decoration: BoxDecoration(
                  color: isDark
                      ? AppTheme.surfaceDarkElevated
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF334155)
                        : const Color(0xFFE2E8F0),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Center(
                    child: AnimatedStickerPlayer(
                      key: ValueKey('${active.fileId}_hero'),
                      sticker: active,
                      packName: set.name,
                      thumbnailBytes: thumbBytes,
                      size: 104,
                      autoPlay: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: badgeColor.withAlpha(30),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: badgeColor.withAlpha(80)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            set.isVideo
                                ? Icons.videocam_rounded
                                : Icons.auto_awesome_rounded,
                            size: 12,
                            color: badgeColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            set.isVideo
                                ? 'Canlı Video Döngüsü'
                                : 'Canlı Lottie Animasyon',
                            style: TextStyle(
                              color: badgeColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(active.emoji, style: const TextStyle(fontSize: 18)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            activeIndex >= 0
                                ? 'Canlı Önizleme #${activeIndex + 1}'
                                : 'Canlı Önizleme',
                            style: TextStyle(
                              color: AppTheme.getText(context),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Aşağıdaki çıkartmalara dokunarak hareketlerini canlı izleyin.',
                      style: TextStyle(
                        color: AppTheme.textMuted.withAlpha(210),
                        fontSize: 10.5,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: onInspectSticker ??
                          () => showStickerDetailSheet(
                                context,
                                sticker: active,
                                orchestrator: orchestrator,
                              ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.open_in_full_rounded,
                            size: 12,
                            color: AppTheme.accentPrimary,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Büyüt ve İncele',
                            style: TextStyle(
                              color: AppTheme.accentPrimary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Opens a modal bottom sheet inspecting a single [TelegramSticker] at 200×200.
Future<void> showStickerDetailSheet(
  BuildContext context, {
  required TelegramSticker sticker,
  required StickerExportOrchestrator orchestrator,
}) async {
  HapticFeedback.lightImpact();
  final thumbId = sticker.thumbFileId ?? sticker.fileId;
  final thumbBytes = orchestrator.thumbnails[thumbId];

  await showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (modalContext) {
      return StatefulBuilder(
        builder: (modalContext, setModalState) {
          final isDark = AppTheme.isDark(modalContext);
          return Container(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            decoration: BoxDecoration(
              color:
                  isDark ? AppTheme.surfaceDark : AppTheme.surfaceLightMode,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              border: Border(
                top: BorderSide(
                  color: isDark
                      ? const Color(0xFF334155)
                      : const Color(0xFFE2E8F0),
                ),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF475569)
                        : const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppTheme.backgroundDark
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF334155)
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Center(
                    child: AnimatedStickerPlayer(
                      sticker: sticker,
                      packName: orchestrator.stickerSet.name,
                      thumbnailBytes: thumbBytes,
                      size: 200,
                      autoPlay: true,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _DetailChip(
                      isDark: isDark,
                      child: Row(
                        children: [
                          Text(
                            sticker.emoji,
                            style: const TextStyle(fontSize: 18),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Emoji',
                            style: TextStyle(
                              color: isDark
                                  ? AppTheme.textMutedDark
                                  : AppTheme.textMutedLight,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    _DetailChip(
                      isDark: isDark,
                      child: Text(
                        sticker.isVideo
                            ? '🎬 Video'
                            : sticker.isAnimated
                                ? '✨ Hareketli'
                                : '🖼️ Statik WebP',
                        style: const TextStyle(
                          color: AppTheme.accentPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'WhatsApp standartları: 512×512 piksel, şeffaf arka plan, < 100 KB',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppTheme.textMuted.withAlpha(150),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: GradientButton(
                    text: sticker.isSelected
                        ? 'Seçimi Kaldır'
                        : 'Bu Çıkartmayı Seç',
                    icon: sticker.isSelected
                        ? Icons.remove_circle_outline_rounded
                        : Icons.check_circle_outline_rounded,
                    gradient: sticker.isSelected
                        ? const LinearGradient(
                            colors: [Color(0xFFE53935), Color(0xFFC62828)],
                          )
                        : AppTheme.primaryGradient,
                    height: 48,
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      orchestrator.toggleStickerSelection(
                        sticker,
                        setAsActive: false,
                      );
                      setModalState(() {});
                      Navigator.pop(modalContext);
                    },
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

class _DetailChip extends StatelessWidget {
  final bool isDark;
  final Widget child;

  const _DetailChip({required this.isDark, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDarkElevated : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: child,
    );
  }
}
