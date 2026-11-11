import 'package:flutter/material.dart';
import '../services/whatsapp_service.dart';
import '../theme/app_theme.dart';

/// Result returned from [showPackMetadataDialog].
class PackMetadataEditResult {
  final String packName;
  final String? publisher;
  final bool exportImmediately;

  const PackMetadataEditResult({
    required this.packName,
    this.publisher,
    this.exportImmediately = false,
  });
}

/// Shows a dialog allowing the user to customize the WhatsApp sticker pack name
/// (and optionally the per-export publisher override).
Future<PackMetadataEditResult?> showPackMetadataDialog({
  required BuildContext context,
  String title = 'Paket Bilgilerini Düzenle',
  required String defaultTitle,
  required String initialPackName,
  int totalParts = 1,
  bool showPublisherField = false,
  String? defaultPublisher,
  String? initialPublisher,
  bool showExportImmediatelyAction = false,
  String blankFallbackNote =
      'Boş bırakılırsa orijinal Telegram başlığı kullanılır.',
}) {
  return showDialog<PackMetadataEditResult>(
    context: context,
    builder: (dialogContext) => _PackMetadataDialog(
      title: title,
      defaultTitle: defaultTitle,
      initialPackName: initialPackName,
      totalParts: totalParts,
      showPublisherField: showPublisherField,
      defaultPublisher: defaultPublisher,
      initialPublisher: initialPublisher,
      showExportImmediatelyAction: showExportImmediatelyAction,
      blankFallbackNote: blankFallbackNote,
    ),
  );
}

class _PackMetadataDialog extends StatefulWidget {
  final String title;
  final String defaultTitle;
  final String initialPackName;
  final int totalParts;
  final bool showPublisherField;
  final String? defaultPublisher;
  final String? initialPublisher;
  final bool showExportImmediatelyAction;
  final String blankFallbackNote;

  const _PackMetadataDialog({
    required this.title,
    required this.defaultTitle,
    required this.initialPackName,
    required this.totalParts,
    required this.showPublisherField,
    required this.defaultPublisher,
    required this.initialPublisher,
    required this.showExportImmediatelyAction,
    required this.blankFallbackNote,
  });

  @override
  State<_PackMetadataDialog> createState() => _PackMetadataDialogState();
}

class _PackMetadataDialogState extends State<_PackMetadataDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _publisherController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialPackName);
    _publisherController = TextEditingController(
      text: widget.initialPublisher ?? widget.defaultPublisher ?? 'StickerSwap',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _publisherController.dispose();
    super.dispose();
  }

  void _submit({bool exportImmediately = false}) {
    Navigator.of(context).pop(
      PackMetadataEditResult(
        packName: _nameController.text.trim(),
        publisher: widget.showPublisherField
            ? _publisherController.text.trim()
            : null,
        exportImmediately: exportImmediately,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final textCol = AppTheme.getText(context);
    final secCol = AppTheme.getTextSec(context);
    final mutCol = AppTheme.getTextMut(context);
    final inputBg = isDark ? AppTheme.backgroundDark : const Color(0xFFF1F5F9);
    final borderCol = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFCBD5E1);

    final rawName = _nameController.text;
    final sanitizedInputOnly = WhatsAppService.sanitizeForWhatsApp(
      rawName,
      fallback: '',
    );
    final previewPackName = WhatsAppService.buildPackName(
      customName: rawName,
      defaultTitle: widget.defaultTitle,
      partIndex: 0,
      totalParts: widget.totalParts,
    );
    final partSuffixLen = widget.totalParts > 1 ? ' Part 1'.length : 0;
    final maxBaseLen = 120 - partSuffixLen;
    final isBlank = rawName.trim().isEmpty;
    final isAllStripped = !isBlank && sanitizedInputOnly.isEmpty;
    final isTruncated = !isBlank && sanitizedInputOnly.length > maxBaseLen;
    final canResetName =
        rawName.trim() != widget.defaultTitle.trim() &&
        widget.defaultTitle.trim().isNotEmpty;

    final fallbackPublisher = widget.defaultPublisher ?? 'StickerSwap';
    final rawPublisher = _publisherController.text;
    final previewPublisher = rawPublisher.trim().isEmpty
        ? WhatsAppService.sanitizeForWhatsApp(
            fallbackPublisher,
            fallback: 'StickerSwap',
          )
        : WhatsAppService.sanitizeForWhatsApp(
            rawPublisher,
            fallback: fallbackPublisher,
          );
    final canResetPublisher =
        widget.showPublisherField &&
        rawPublisher.trim() != fallbackPublisher.trim();

    return AlertDialog(
      backgroundColor: AppTheme.getSurface(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withAlpha(24),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.drive_file_rename_outline_rounded,
              color: AppTheme.primaryBlue,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.title,
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
        child: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'WhatsApp Paket Adı',
                    style: TextStyle(
                      color: secCol,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (canResetName)
                    InkWell(
                      onTap: () {
                        setState(() {
                          _nameController.text = widget.defaultTitle;
                          _nameController.selection = TextSelection.collapsed(
                            offset: _nameController.text.length,
                          );
                        });
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        child: Text(
                          'Varsayılana Dön',
                          style: TextStyle(
                            color: AppTheme.primaryBlue,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  color: inputBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderCol),
                ),
                child: TextField(
                  controller: _nameController,
                  autofocus: true,
                  textInputAction: widget.showPublisherField
                      ? TextInputAction.next
                      : TextInputAction.done,
                  onSubmitted: (_) {
                    if (!widget.showPublisherField) _submit();
                  },
                  onChanged: (_) => setState(() {}),
                  style: TextStyle(color: textCol, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: widget.defaultTitle,
                    hintStyle: TextStyle(
                      color: mutCol.withAlpha(140),
                      fontSize: 13.5,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    suffixIcon: rawName.isNotEmpty
                        ? IconButton(
                            icon: Icon(
                              Icons.clear_rounded,
                              size: 18,
                              color: mutCol,
                            ),
                            onPressed: () {
                              setState(() => _nameController.clear());
                            },
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Live WhatsApp sanitization preview
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppTheme.surfaceDarkElevated.withAlpha(110)
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: (isAllStripped || isTruncated)
                        ? AppTheme.warning.withAlpha(140)
                        : borderCol.withAlpha(140),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          widget.totalParts > 1
                              ? 'WhatsApp ön izleme (Parça 1/${widget.totalParts})'
                              : 'WhatsApp\'ta görünecek ad',
                          style: TextStyle(
                            color: mutCol,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          '${previewPackName.length}/120',
                          style: TextStyle(
                            color: isTruncated ? AppTheme.warning : mutCol,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      previewPackName,
                      style: TextStyle(
                        color: textCol,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (isBlank) ...[
                      const SizedBox(height: 4),
                      Text(
                        widget.blankFallbackNote,
                        style: TextStyle(color: mutCol, fontSize: 11),
                      ),
                    ] else if (isAllStripped) ...[
                      const SizedBox(height: 4),
                      const Text(
                        'Desteklenmeyen semboller temizlendi; varsayılan ada dönülecek.',
                        style: TextStyle(
                          color: AppTheme.warning,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ] else if (isTruncated) ...[
                      const SizedBox(height: 4),
                      const Text(
                        '120 karakter sınırı nedeniyle başlık kısaltılacak.',
                        style: TextStyle(
                          color: AppTheme.warning,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (widget.showPublisherField) ...[
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Yayıncı Adı (Bu Aktarıma Özel)',
                      style: TextStyle(
                        color: secCol,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (canResetPublisher)
                      InkWell(
                        onTap: () {
                          setState(() {
                            _publisherController.text = fallbackPublisher;
                            _publisherController.selection =
                                TextSelection.collapsed(
                              offset: _publisherController.text.length,
                            );
                          });
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          child: Text(
                            'Varsayılana Dön',
                            style: TextStyle(
                              color: AppTheme.primaryBlue,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(
                    color: inputBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: borderCol),
                  ),
                  child: TextField(
                    controller: _publisherController,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(color: textCol, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: fallbackPublisher,
                      hintStyle: TextStyle(
                        color: mutCol.withAlpha(140),
                        fontSize: 13.5,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      suffixIcon: rawPublisher.isNotEmpty
                          ? IconButton(
                              icon: Icon(
                                Icons.clear_rounded,
                                size: 18,
                                color: mutCol,
                              ),
                              onPressed: () {
                                setState(() => _publisherController.clear());
                              },
                            )
                          : null,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  rawPublisher.trim().isEmpty
                      ? 'Boş bırakılırsa Ayarlar\'daki yayıncı adı ($previewPublisher) kullanılır.'
                      : 'WhatsApp yayıncı adı: $previewPublisher',
                  style: TextStyle(color: mutCol, fontSize: 11),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text('İptal', style: TextStyle(color: mutCol)),
        ),
        if (widget.showExportImmediatelyAction) ...[
          OutlinedButton(
            onPressed: () => _submit(exportImmediately: false),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppTheme.primaryBlue.withAlpha(120)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Kaydet'),
          ),
          ElevatedButton(
            onPressed: () => _submit(exportImmediately: true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.whatsappGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Kaydet ve Ekle'),
          ),
        ] else
          ElevatedButton(
            onPressed: () => _submit(exportImmediately: false),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Kaydet'),
          ),
      ],
    );
  }
}

