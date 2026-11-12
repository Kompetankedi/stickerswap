import 'package:flutter/material.dart';
import '../services/whatsapp_service.dart';
import '../theme/app_theme.dart';

/// Displays an informative dialog when WhatsApp sticker export is triggered
/// on an unsupported platform such as iOS instead of crashing with
/// `MissingPluginException`.
Future<void> showIosUnsupportedDialog(
  BuildContext context, {
  String? message,
}) {
  final isDark = AppTheme.isDark(context);
  final textCol = AppTheme.getText(context);
  final secCol = AppTheme.getTextSec(context);

  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLightMode,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withAlpha(25),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.phone_android_rounded,
              color: AppTheme.primaryBlue,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Yalnızca Android Desteklenir',
              style: TextStyle(
                color: textCol,
                fontSize: 16.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      content: Text(
        message ?? WhatsAppService.iosUnsupportedMessage,
        style: TextStyle(color: secCol, fontSize: 13.5, height: 1.4),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Anladım'),
        ),
      ],
    ),
  );
}

/// Checks whether [whatsappService] is running on an unsupported platform (iOS)
/// and shows [showIosUnsupportedDialog] if so.
Future<bool> guardUnsupportedIosExport(
  BuildContext context,
  WhatsAppService whatsappService,
) async {
  if (!whatsappService.isExportUnsupportedPlatform) {
    return false;
  }
  await showIosUnsupportedDialog(context);
  return true;
}
