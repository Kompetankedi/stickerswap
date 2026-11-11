import 'package:flutter/material.dart';
import '../services/whatsapp_service.dart';
import '../theme/app_theme.dart';

/// Prompts the user when a pack is already installed in WhatsApp so they
/// can mint a fresh identifier to bypass WhatsApp's client-side metadata/sticker cache.
/// Returns `null` if cancelled.
Future<String?> resolveAnimatedPackExportIdentifier({
  required BuildContext context,
  required String baseIdentifier,
  required WhatsAppService whatsappService,
  required bool isAnimated,
  bool checkIfInstalled = false,
  bool isNameUpdated = false,
}) async {
  if (!isAnimated && !checkIfInstalled) return baseIdentifier;
  final installed = await whatsappService.isPackInstalled(baseIdentifier);
  if (!installed || !context.mounted) return baseIdentifier;

  final String message;
  if (isNameUpdated && !isAnimated) {
    message =
        'Bu paket WhatsApp\'ta zaten yüklü olduğu için WhatsApp eski paket adını koruyabilir.\n\n'
        'Güncel paket adının WhatsApp\'ta hemen görünmesi için "Yeni Güncel Kopya Ekle"yi seçebilir '
        'ya da önce WhatsApp içinden eski paketi silip yeniden ekleyebilirsiniz.';
  } else if (isNameUpdated && isAnimated) {
    message =
        'WhatsApp daha önce eklenen paketlerin eski adını ve (1 sn) önbelleğini koruyabilir.\n\n'
        'Güncel adın ve animasyonun görünmesi için "Yeni Güncel Kopya Ekle"yi seçebilir '
        'ya da önce WhatsApp içinden eski paketi silip yeniden ekleyebilirsiniz.';
  } else if (!isAnimated) {
    message =
        'Bu paket WhatsApp\'ta zaten yüklü.\n\n'
        'Yeni bir kopya olarak eklemek için "Yeni Güncel Kopya Ekle"yi seçebilir '
        'ya da önce WhatsApp içinden eski paketi silip yeniden ekleyebilirsiniz.';
  } else {
    message =
        'WhatsApp daha önce eklenen paketlerin eski (1 sn) önbelleğini koruyabilir.\n\n'
        'Güncel animasyonun görünmesi için "Yeni Güncel Kopya Ekle"yi seçebilir '
        'ya da önce WhatsApp içinden eski paketi silip yeniden ekleyebilirsiniz.';
  }

  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Paket WhatsApp\'ta Zaten Yüklü'),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(null),
          child: const Text('İptal'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(baseIdentifier),
          child: const Text('Mevcuta Yaz'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.whatsappGreen,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(
            WhatsAppService.buildVersionedIdentifier(baseIdentifier),
          ),
          child: const Text('Yeni Güncel Kopya Ekle'),
        ),
      ],
    ),
  );
}

/// Warns when re-adding a saved animated pack whose local files predate `_wa_v4.webp`.
Future<bool> confirmLegacyAnimatedPackReAdd(BuildContext context) async {
  if (!context.mounted) return false;
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Eski Önbellek Dosyaları'),
      content: const Text(
        'Bu paket düzeltmeden önceki eski çıkartma dosyalarını '
        'kullanıyor. Güncel animasyon için paketi aramadan tekrar açıp '
        'yeniden dışa aktarmanız önerilir.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('İptal'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Yine de Ekle'),
        ),
      ],
    ),
  );
  return result ?? false;
}

