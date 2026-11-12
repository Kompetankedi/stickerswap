import 'package:flutter/material.dart';
import '../services/sticker_pre_flight_validator.dart';
import '../services/sticker_processor.dart';
import '../theme/app_theme.dart';

enum _PreFlightUserChoice {
  excludeAndContinue,
  recompressAndRetry,
  cancel,
}

/// Runs [StickerPreFlightValidator] on [stickerData] before calling WhatsApp's
/// export intent. If issues are detected, presents actionable recovery choices
/// (exclude faulty stickers or re-compress at lower quality) and returns the
/// validated list to export, or `null` if cancelled / unrecoverable.
Future<List<Map<String, dynamic>>?> runPreFlightValidationGate({
  required BuildContext context,
  required String trayPath,
  required List<Map<String, dynamic>> stickerData,
  required bool isAnimatedPack,
  StickerPreFlightValidator validator = const StickerPreFlightValidator(),
  StickerProcessor? stickerProcessor,
}) async {
  final processor = stickerProcessor ?? StickerProcessor();
  var currentStickers = List<Map<String, dynamic>>.from(stickerData);

  while (true) {
    final report = await validator.validatePack(
      trayPath: trayPath,
      stickerData: currentStickers,
      isAnimatedPack: isAnimatedPack,
    );
    if (report.isValid) {
      return currentStickers;
    }
    if (!context.mounted) return null;

    final choice = await showDialog<_PreFlightUserChoice>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _PreFlightIssueDialog(report: report),
    );

    if (choice == _PreFlightUserChoice.excludeAndContinue &&
        report.canContinueByExcluding) {
      return report.validStickerData;
    }

    if (choice == _PreFlightUserChoice.recompressAndRetry &&
        report.hasRecompressibleIssues) {
      for (final issue in report.stickerIssues) {
        if (!issue.canFixByRecompress || issue.path.isEmpty) continue;
        try {
          await processor.recompressWebpSticker(
            issue.path,
            asAnimated: isAnimatedPack,
          );
        } catch (_) {
          // Next validation pass will still surface any remaining issue.
        }
      }
      if (!context.mounted) return null;
      continue;
    }

    return null;
  }
}

class _PreFlightIssueDialog extends StatelessWidget {
  final PreFlightValidationReport report;

  const _PreFlightIssueDialog({required this.report});

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final textCol = AppTheme.getText(context);
    final secCol = AppTheme.getTextSec(context);
    final previewIssues = report.stickerIssues.take(4).toList();
    final remainingCount = report.stickerIssues.length - previewIssues.length;

    return AlertDialog(
      backgroundColor: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLightMode,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.warning.withAlpha(30),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.verified_user_outlined,
              color: AppTheme.warning,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Aktarım Öncesi Kontrol',
              style: TextStyle(
                color: textCol,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              report.buildSummaryHeadline(),
              style: TextStyle(
                color: secCol,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            ...report.packErrors.map(
              (err) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      size: 16,
                      color: AppTheme.error,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        err,
                        style: const TextStyle(
                          color: AppTheme.error,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ...previewIssues.map(
              (issue) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF0F172A)
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF334155)
                        : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Çıkartma #${issue.stickerIndex + 1} (${issue.fileName})',
                      style: TextStyle(
                        color: textCol,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ...issue.reasons.map(
                      (reason) => Text(
                        '• $reason',
                        style: TextStyle(color: secCol, fontSize: 11.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (remainingCount > 0)
              Text(
                '+$remainingCount sorunlu çıkartma daha var.',
                style: TextStyle(color: secCol, fontSize: 12),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, _PreFlightUserChoice.cancel),
          child: const Text('İptal'),
        ),
        if (report.hasRecompressibleIssues)
          OutlinedButton(
            onPressed: () => Navigator.pop(
              context,
              _PreFlightUserChoice.recompressAndRetry,
            ),
            child: const Text('Yeniden Sıkıştır'),
          ),
        if (report.canContinueByExcluding)
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              _PreFlightUserChoice.excludeAndContinue,
            ),
            child: Text('Hariç Tutarak Ekle (${report.validCount})'),
          ),
      ],
    );
  }
}

