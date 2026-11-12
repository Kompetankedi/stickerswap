import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lottie/lottie.dart';
import '../models/telegram_sticker.dart';
import '../services/sticker_export_orchestrator.dart';
import '../theme/app_theme.dart';
import 'live_hero_preview.dart';

/// Displays the 4-column sticker grid with multi-selection, 1–30 part badges,
/// live Lottie rendering, and inspection triggers.
class StickerSelectionGrid extends StatelessWidget {
  final StickerExportOrchestrator orchestrator;

  const StickerSelectionGrid({
    super.key,
    required this.orchestrator,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        orchestrator,
        orchestrator.activePreviewSticker,
        orchestrator.mediaCacheVersion,
      ]),
      builder: (context, _) {
        final filtered = orchestrator.filteredStickers;
        if (filtered.isEmpty) {
          return Center(
            child: Text(
              'Bu filtreye uygun çıkartma bulunamadı.',
              style: TextStyle(color: AppTheme.textMuted.withAlpha(150)),
            ),
          );
        }

        // Precompute 1–30 part assignment index for selected stickers when splitting.
        final Map<String, int> selectedPartMap = {};
        if (orchestrator.selectedCount > 30) {
          int selectedIdx = 0;
          for (final s in orchestrator.stickerSet.stickers) {
            if (s.isSelected) {
              selectedPartMap[s.fileId] = (selectedIdx ~/ 30) + 1;
              selectedIdx++;
            }
          }
        }

        final isDark = AppTheme.isDark(context);
        final activeHeroId = orchestrator.activePreviewSticker.value?.fileId;

        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            final sticker = filtered[index];
            final thumbId = sticker.thumbFileId ?? sticker.fileId;
            final thumbBytes = orchestrator.thumbnails[thumbId];
            final lottieBytes = orchestrator.lottieCache[sticker.fileId];
            final isCurrentHero = activeHeroId == sticker.fileId;
            final partBadgeNum = selectedPartMap[sticker.fileId];

            return _StickerGridTile(
              sticker: sticker,
              isDark: isDark,
              isCurrentHero: isCurrentHero,
              thumbBytes: thumbBytes,
              lottieBytes: lottieBytes,
              partBadgeNum: partBadgeNum,
              onTap: () {
                HapticFeedback.selectionClick();
                orchestrator.toggleStickerSelection(sticker);
              },
              onInspect: () {
                orchestrator.setActivePreviewSticker(sticker);
                showStickerDetailSheet(
                  context,
                  sticker: sticker,
                  orchestrator: orchestrator,
                );
              },
            )
                .animate()
                .fadeIn(
                  delay: Duration(milliseconds: 40 * (index % 12)),
                  duration: 250.ms,
                )
                .scale(
                  begin: const Offset(0.92, 0.92),
                  delay: Duration(milliseconds: 40 * (index % 12)),
                  duration: 250.ms,
                );
          },
        );
      },
    );
  }
}

class _StickerGridTile extends StatelessWidget {
  final TelegramSticker sticker;
  final bool isDark;
  final bool isCurrentHero;
  final Uint8List? thumbBytes;
  final Uint8List? lottieBytes;
  final int? partBadgeNum;
  final VoidCallback onTap;
  final VoidCallback onInspect;

  const _StickerGridTile({
    required this.sticker,
    required this.isDark,
    required this.isCurrentHero,
    required this.thumbBytes,
    required this.lottieBytes,
    required this.partBadgeNum,
    required this.onTap,
    required this.onInspect,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = (isCurrentHero || sticker.isSelected)
        ? AppTheme.primaryBlue
        : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0));

    return GestureDetector(
      onTap: onTap,
      onLongPress: onInspect,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: sticker.isSelected
              ? (isDark
                  ? AppTheme.surfaceDarkElevated
                  : const Color(0xFFEFF6FF))
              : (isDark ? AppTheme.cardDark : AppTheme.cardLight),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: borderColor,
            width: (isCurrentHero || sticker.isSelected) ? 2.0 : 1.0,
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: _buildArtwork(),
              ),
            ),
            if (partBadgeNum != null)
              Positioned(
                top: 4,
                left: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withAlpha(220),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    'P$partBadgeNum',
                    style: const TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w800,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ),
            Positioned(
              top: 4,
              right: 4,
              child: AnimatedScale(
                scale: sticker.isSelected ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                    color: AppTheme.primaryBlue,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check,
                    size: 13,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 4,
              left: 4,
              child: Text(
                sticker.emoji,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            Positioned(
              bottom: 2,
              right: 2,
              child: InkWell(
                onTap: onInspect,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isCurrentHero
                        ? AppTheme.accentSecondary.withAlpha(200)
                        : ((sticker.isVideo || sticker.isAnimated)
                            ? AppTheme.accentPrimary.withAlpha(80)
                            : Colors.black.withAlpha(80)),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        sticker.isVideo || sticker.isAnimated
                            ? Icons.play_arrow_rounded
                            : Icons.zoom_in_rounded,
                        size: 11,
                        color: Colors.white,
                      ),
                      if (sticker.isVideo || sticker.isAnimated) ...[
                        const SizedBox(width: 1),
                        Text(
                          isCurrentHero ? 'OYNATILIYOR' : 'CANLI',
                          style: const TextStyle(
                            fontSize: 7.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArtwork() {
    if (sticker.isAnimated && lottieBytes != null) {
      return Lottie.memory(
        lottieBytes!,
        fit: BoxFit.contain,
        repeat: true,
        errorBuilder: (_, _, _) => _buildThumbnailOrPlaceholder(),
      );
    }
    return _buildThumbnailOrPlaceholder();
  }

  Widget _buildThumbnailOrPlaceholder() {
    if (thumbBytes != null) {
      return Image.memory(
        thumbBytes!,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => _placeholderIcon(),
      );
    }
    return _placeholderIcon();
  }

  Widget _placeholderIcon() {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDarkElevated : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(sticker.emoji, style: const TextStyle(fontSize: 26)),
      ),
    );
  }
}
