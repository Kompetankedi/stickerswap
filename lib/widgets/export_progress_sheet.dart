import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/sticker_export_orchestrator.dart';
import '../services/storage_service.dart';
import '../services/whatsapp_service.dart';
import '../theme/app_theme.dart';
import 'gradient_button.dart';
import 'installed_pack_cache_dialog.dart';
import 'pre_flight_dialog.dart';

/// Displays real-time sticker preparation progress, percentage, and cancel control
/// without triggering full-screen rebuilds.
class ExportProgressSheet extends StatelessWidget {
  final ValueListenable<ExportProgressState> progressListenable;
  final VoidCallback onCancel;

  const ExportProgressSheet({
    super.key,
    required this.progressListenable,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    return ValueListenableBuilder<ExportProgressState>(
      valueListenable: progressListenable,
      builder: (context, state, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    state.statusText,
                    style: TextStyle(
                      color: isDark
                          ? AppTheme.textPrimary
                          : const Color(0xFF1E293B),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${(state.progress * 100).toInt()}%',
                  style: const TextStyle(
                    color: AppTheme.accentPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.0, end: state.progress),
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                builder: (context, val, _) {
                  return LinearProgressIndicator(
                    value: val,
                    minHeight: 7,
                    backgroundColor: isDark
                        ? AppTheme.surfaceDarkElevated
                        : const Color(0xFFE2E8F0),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppTheme.accentPrimary,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onCancel,
                icon: const Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: AppTheme.error,
                ),
                label: const Text(
                  'İşlemi İptal Et',
                  style: TextStyle(
                    color: AppTheme.error,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppTheme.error.withAlpha(90)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Presents the multi-part export confirmation sheet for packs > 30 stickers.
Future<void> showMultiPartExportSheet({
  required BuildContext context,
  required List<PreparedPackPart> preparedParts,
  required WhatsAppService whatsappService,
  required StorageService storageService,
  required bool isCustomName,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => MultiPartExportSheet(
      preparedParts: preparedParts,
      whatsappService: whatsappService,
      storageService: storageService,
      isCustomName: isCustomName,
    ),
  );
}

class MultiPartExportSheet extends StatefulWidget {
  final List<PreparedPackPart> preparedParts;
  final WhatsAppService whatsappService;
  final StorageService storageService;
  final bool isCustomName;

  const MultiPartExportSheet({
    super.key,
    required this.preparedParts,
    required this.whatsappService,
    required this.storageService,
    this.isCustomName = false,
  });

  @override
  State<MultiPartExportSheet> createState() => _MultiPartExportSheetState();
}

class _MultiPartExportSheetState extends State<MultiPartExportSheet> {
  int? _activeSendingIndex;

  int get _nextPendingIndex =>
      widget.preparedParts.indexWhere((p) => !p.isAddedToWhatsApp);

  bool get _isAllAdded =>
      widget.preparedParts.every((p) => p.isAddedToWhatsApp);

  int get _addedCount =>
      widget.preparedParts.where((p) => p.isAddedToWhatsApp).length;

  Future<void> _exportPart(PreparedPackPart part) async {
    if (_activeSendingIndex != null) return;

    setState(() {
      _activeSendingIndex = part.index;
      part.error = null;
      part.isCancelled = false;
    });

    try {
      final validatedStickers = await runPreFlightValidationGate(
        context: context,
        trayPath: part.trayPath,
        stickerData: part.stickerData,
        isAnimatedPack: part.isAnimated,
      );
      if (validatedStickers == null || !mounted) {
        part.isCancelled = true;
        return;
      }

      final targetPackId = await resolveAnimatedPackExportIdentifier(
        context: context,
        baseIdentifier: part.packId,
        whatsappService: widget.whatsappService,
        isAnimated: part.isAnimated,
        checkIfInstalled: part.isAnimated || widget.isCustomName,
        isNameUpdated: widget.isCustomName,
      );
      if (targetPackId == null) {
        part.isCancelled = true;
        return;
      }

      final result = await widget.whatsappService.addStickerPack(
        identifier: targetPackId,
        name: part.packName,
        publisher: part.publisher,
        trayPath: part.trayPath,
        stickerData: validatedStickers,
        animatedStickerPack: part.isAnimated,
      );

      if (!mounted) return;

      if (result.isAdded) {
        part.isAddedToWhatsApp = true;
        part.isCancelled = false;
        part.error = null;
        await widget.storageService.updatePackStatus(part.packId, true);
        HapticFeedback.mediumImpact();
      } else if (result.isCancelled) {
        part.isCancelled = true;
        HapticFeedback.lightImpact();
      } else {
        part.error = result.errorMessage ?? 'Aktarım başarısız oldu.';
        HapticFeedback.heavyImpact();
      }
    } catch (e) {
      if (mounted) {
        part.error = e.toString().replaceAll('Exception: ', '').trim();
      }
    } finally {
      if (mounted) {
        setState(() {
          _activeSendingIndex = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final total = widget.preparedParts.length;
    final nextIdx = _nextPendingIndex;
    final allDone = _isAllAdded;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLightMode,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF475569)
                    : const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.whatsappGreen.withAlpha(25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.splitscreen_rounded,
                  color: AppTheme.whatsappGreen,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Çok Parçalı WhatsApp Aktarımı',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.getText(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      allDone
                          ? 'Tüm parçalar WhatsApp\'a eklendi!'
                          : '$_addedCount / $total parça eklendi (WhatsApp paketi başına maks 30 çıkartma)',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? AppTheme.textMutedDark
                            : AppTheme.textMutedLight,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isDark
                  ? AppTheme.surfaceDarkElevated
                  : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF334155)
                    : const Color(0xFFE2E8F0),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: isDark
                      ? AppTheme.textMutedDark
                      : AppTheme.textMutedLight,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'WhatsApp her paketi ayrı bir onay ekranıyla kabul eder. Parçaları sırayla onaylayarak kolayca aktarabilirsiniz.',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? AppTheme.textMutedDark
                          : AppTheme.textMutedLight,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: widget.preparedParts.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, idx) {
                final part = widget.preparedParts[idx];
                final isSendingThis = _activeSendingIndex == part.index;
                final isNext = nextIdx == part.index;

                final borderColor = part.isAddedToWhatsApp
                    ? AppTheme.success.withAlpha(120)
                    : (isNext
                        ? AppTheme.whatsappGreen
                        : (isDark
                            ? const Color(0xFF334155)
                            : const Color(0xFFE2E8F0)));

                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.cardDark : AppTheme.cardLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: borderColor,
                      width: isNext ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: File(part.trayPath).existsSync()
                            ? Image.file(
                                File(part.trayPath),
                                width: 42,
                                height: 42,
                                fit: BoxFit.cover,
                              )
                            : Container(
                                width: 42,
                                height: 42,
                                color: isDark
                                    ? AppTheme.surfaceDarkElevated
                                    : const Color(0xFFE2E8F0),
                                child: const Icon(
                                  Icons.image_outlined,
                                  size: 20,
                                ),
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              part.packName,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.getText(context),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${part.stickerData.length} çıkartma ${part.isAnimated ? "• Hareketli" : ""}',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? AppTheme.textMutedDark
                                    : AppTheme.textMutedLight,
                              ),
                            ),
                            if (part.error != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                part.error!,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.error,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ] else if (part.isCancelled) ...[
                              const SizedBox(height: 2),
                              const Text(
                                'WhatsApp\'ta iptal edildi',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.warning,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (isSendingThis)
                        const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppTheme.whatsappGreen,
                            ),
                          ),
                        )
                      else if (part.isAddedToWhatsApp)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.success.withAlpha(25),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: AppTheme.success.withAlpha(80),
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.check_circle_rounded,
                                size: 13,
                                color: AppTheme.success,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Eklendi',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.success,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        OutlinedButton(
                          onPressed: _activeSendingIndex != null
                              ? null
                              : () => _exportPart(part),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            minimumSize: Size.zero,
                            side: BorderSide(
                              color: isNext
                                  ? AppTheme.whatsappGreen
                                  : (isDark
                                      ? const Color(0xFF475569)
                                      : const Color(0xFFCBD5E1)),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Text(
                            part.isCancelled || part.error != null
                                ? 'Tekrar Dene'
                                : 'Ekle',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isNext
                                  ? AppTheme.whatsappGreen
                                  : AppTheme.getText(context),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          if (allDone)
            GradientButton(
              text: 'Tamamla',
              icon: Icons.check_rounded,
              gradient: AppTheme.primaryGradient,
              onPressed: () => Navigator.pop(context),
            )
          else ...[
            GradientButton(
              text: nextIdx != -1
                  ? 'Parça ${nextIdx + 1}/$total\'i WhatsApp\'a Ekle'
                  : 'Sıradaki Parçayı Ekle',
              icon: Icons.send_rounded,
              gradient: AppTheme.whatsappGradient,
              isLoading: _activeSendingIndex != null,
              onPressed: _activeSendingIndex != null || nextIdx == -1
                  ? null
                  : () => _exportPart(widget.preparedParts[nextIdx]),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: _activeSendingIndex != null
                  ? null
                  : () => Navigator.pop(context),
              child: Text(
                'Daha Sonra Tamamla',
                style: TextStyle(
                  color: isDark
                      ? AppTheme.textMutedDark
                      : AppTheme.textMutedLight,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
