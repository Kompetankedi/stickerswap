import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/telegram_sticker_set.dart';
import '../services/sticker_export_orchestrator.dart';
import '../theme/app_theme.dart';
import '../widgets/export_progress_sheet.dart';
import '../widgets/gradient_button.dart';
import '../widgets/installed_pack_cache_dialog.dart';
import '../widgets/live_hero_preview.dart';
import '../widgets/pack_metadata_dialog.dart';
import '../widgets/pre_flight_dialog.dart';
import '../widgets/status_badge.dart';
import '../widgets/sticker_selection_grid.dart';

/// Preview screen showing all stickers in a pack with selection controls,
/// live hero preview, emoji search, and WhatsApp export with automatic splitting.
class PackPreviewScreen extends StatefulWidget {
  final TelegramStickerSet stickerSet;

  const PackPreviewScreen({super.key, required this.stickerSet});

  @override
  State<PackPreviewScreen> createState() => _PackPreviewScreenState();
}

class _PackPreviewScreenState extends State<PackPreviewScreen> {
  late final StickerExportOrchestrator _orchestrator;
  final _searchController = TextEditingController();
  bool _isSearchOpen = false;

  @override
  void initState() {
    super.initState();
    _orchestrator = StickerExportOrchestrator(stickerSet: widget.stickerSet);
    _orchestrator.initAndLoad();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _orchestrator.dispose();
    super.dispose();
  }

  Future<void> _openPackMetadataEditor() async {
    if (_orchestrator.isProcessing) return;
    final selectedCount = _orchestrator.selectedCount;
    final totalParts = selectedCount > 30 ? (selectedCount / 30).ceil() : 1;

    final result = await showPackMetadataDialog(
      context: context,
      defaultTitle: widget.stickerSet.title,
      initialPackName: _orchestrator.effectiveDisplayTitle,
      totalParts: totalParts,
      showPublisherField: true,
      defaultPublisher: _orchestrator.defaultPublisher,
      initialPublisher: _orchestrator.effectivePublisherRaw,
    );
    if (result == null || !mounted) return;

    _orchestrator.updateMetadataOverrides(
      packName: result.packName,
      publisher: result.publisher,
    );
  }

  Future<void> _exportToWhatsApp() async {
    if (_orchestrator.selectedCount < 3) {
      _showSnackBar('WhatsApp en az 3 çıkartma gerektirir.', isError: true);
      return;
    }

    try {
      final preparedParts = await _orchestrator.preparePartsForExport();
      if (preparedParts == null || preparedParts.isEmpty || !mounted) return;

      if (preparedParts.length == 1) {
        await _exportSinglePart(preparedParts.first);
      } else {
        await showMultiPartExportSheet(
          context: context,
          preparedParts: preparedParts,
          whatsappService: _orchestrator.whatsappService,
          storageService: _orchestrator.storageService,
          isCustomName: _orchestrator.hasCustomName,
        );
      }
    } catch (e) {
      if (mounted && !_orchestrator.isCancelled) {
        _showSnackBar(
          'Hata: ${e.toString().replaceAll('Exception: ', '')}',
          isError: true,
        );
      }
    }
  }

  Future<void> _exportSinglePart(PreparedPackPart part) async {
    final validatedStickers = await runPreFlightValidationGate(
      context: context,
      trayPath: part.trayPath,
      stickerData: part.stickerData,
      isAnimatedPack: part.isAnimated,
      stickerProcessor: _orchestrator.stickerProcessor,
    );
    if (validatedStickers == null || !mounted) {
      if (mounted) _showSnackBar('WhatsApp\'a ekleme iptal edildi.');
      return;
    }

    final targetPackId = await resolveAnimatedPackExportIdentifier(
      context: context,
      baseIdentifier: part.packId,
      whatsappService: _orchestrator.whatsappService,
      isAnimated: part.isAnimated,
      checkIfInstalled: part.isAnimated || _orchestrator.hasCustomName,
      isNameUpdated: _orchestrator.hasCustomName,
    );
    if (targetPackId == null) {
      if (mounted) _showSnackBar('WhatsApp\'a ekleme iptal edildi.');
      return;
    }

    final result = await _orchestrator.whatsappService.addStickerPack(
      identifier: targetPackId,
      name: part.packName,
      publisher: part.publisher,
      trayPath: part.trayPath,
      stickerData: validatedStickers,
      animatedStickerPack: part.isAnimated,
    );
    if (!mounted) return;

    if (result.isAdded) {
      await _orchestrator.markPackAddedToWhatsApp(part.packId);
      HapticFeedback.mediumImpact();
      _showSnackBar('✅ Paket başarıyla WhatsApp\'a eklendi!');
    } else if (result.isCancelled) {
      _showSnackBar('WhatsApp\'a ekleme iptal edildi.');
    } else {
      _showSnackBar(
        'Hata: ${result.errorMessage ?? "Bilinmeyen bir hata oluştu."}',
        isError: true,
      );
    }
  }

  void _cancelExport() {
    if (!_orchestrator.isProcessing) return;
    _orchestrator.cancelExport();
    _showSnackBar('WhatsApp\'a aktarım işlemi iptal edildi.');
  }

  Future<void> _confirmAndCancelExport() async {
    final shouldCancel = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.isDark(ctx)
            ? AppTheme.surfaceDark
            : AppTheme.surfaceLightMode,
        title: const Text('Aktarımı İptal Et?'),
        content: const Text(
          'Çıkartmalar hazırlanıyor. İşlemi iptal etmek istiyor musunuz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Devam Et'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('İptal Et'),
          ),
        ],
      ),
    );

    if (shouldCancel == true && mounted) {
      _cancelExport();
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppTheme.error : AppTheme.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final set = widget.stickerSet;
    final totalCount = set.stickers.length;

    return ValueListenableBuilder<ExportProgressState>(
      valueListenable: _orchestrator.exportProgress,
      builder: (context, exportState, child) {
        final isProcessing = exportState.isProcessing;
        return PopScope(
          canPop: !isProcessing,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && isProcessing) {
              _confirmAndCancelExport();
            }
          },
          child: child!,
        );
      },
      child: Scaffold(
        backgroundColor: AppTheme.getBackground(context),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          leading: IconButton(
            icon: Icon(
              Icons.arrow_back_ios_rounded,
              size: 20,
              color: AppTheme.getText(context),
            ),
            onPressed: () {
              if (_orchestrator.isProcessing) {
                _confirmAndCancelExport();
              } else {
                Navigator.pop(context);
              }
            },
          ),
          title: ListenableBuilder(
            listenable: _orchestrator,
            builder: (context, _) {
              return Column(
                children: [
                  InkWell(
                    onTap: _orchestrator.isProcessing
                        ? null
                        : _openPackMetadataEditor,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              _orchestrator.effectiveDisplayTitle,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.getText(context),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Icon(
                            Icons.edit_rounded,
                            size: 15,
                            color: _orchestrator.hasCustomName
                                ? AppTheme.primaryBlue
                                : AppTheme.getTextMut(context),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$totalCount çıkartma',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textMuted,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: set.isStatic
                              ? AppTheme.accentPrimary.withAlpha(25)
                              : AppTheme.accentSecondary.withAlpha(25),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          set.typeLabel,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: set.isStatic
                                ? AppTheme.accentPrimary
                                : AppTheme.accentSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          actions: [
            IconButton(
              icon: Icon(
                _isSearchOpen ? Icons.close_rounded : Icons.search_rounded,
                color: AppTheme.textPrimary,
                size: 20,
              ),
              onPressed: () {
                setState(() {
                  _isSearchOpen = !_isSearchOpen;
                  if (!_isSearchOpen) {
                    _searchController.clear();
                    _orchestrator.setEmojiSearch('');
                  }
                });
              },
            ),
            ListenableBuilder(
              listenable: _orchestrator,
              builder: (context, _) {
                return PopupMenuButton<String>(
                  icon: const Icon(
                    Icons.more_vert_rounded,
                    color: AppTheme.textPrimary,
                  ),
                  color: AppTheme.surfaceDark,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  onSelected: (val) {
                    HapticFeedback.selectionClick();
                    if (val == 'all') _orchestrator.toggleSelectAll();
                    if (val == 'invert') _orchestrator.invertSelection();
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'all',
                      child: Text(
                        _orchestrator.selectAll
                            ? 'Seçimi Kaldır'
                            : 'Tümünü Seç',
                        style: const TextStyle(color: AppTheme.textPrimary),
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'invert',
                      child: Text(
                        'Seçimi Tersine Çevir',
                        style: TextStyle(color: AppTheme.textPrimary),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
        body: Column(
          children: [
            if (_isSearchOpen)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.cardDark : AppTheme.cardLight,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF334155)
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 13,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Emojiye göre filtrele (örn: 😂, 🐱, ❤️)...',
                      hintStyle: TextStyle(
                        color: AppTheme.textMuted.withAlpha(120),
                        fontSize: 12,
                      ),
                      prefixIcon: const Icon(
                        Icons.emoji_emotions_outlined,
                        color: AppTheme.accentPrimary,
                        size: 18,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                    ),
                    onChanged: _orchestrator.setEmojiSearch,
                  ),
                ),
              ),
            ListenableBuilder(
              listenable: _orchestrator,
              builder: (context, _) {
                final selectedCount = _orchestrator.selectedCount;
                final filterIndex = _orchestrator.filterIndex;
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      _FilterChip(
                        label: 'Tümü ($totalCount)',
                        isSelected: filterIndex == 0,
                        onTap: () => _orchestrator.setFilterIndex(0),
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: 'Seçili ($selectedCount)',
                        isSelected: filterIndex == 1,
                        onTap: () => _orchestrator.setFilterIndex(1),
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: 'Kalan (${totalCount - selectedCount})',
                        isSelected: filterIndex == 2,
                        onTap: () => _orchestrator.setFilterIndex(2),
                      ),
                    ],
                  ),
                );
              },
            ),
            LiveHeroPreview(orchestrator: _orchestrator),
            Expanded(
              child: StickerSelectionGrid(orchestrator: _orchestrator),
            ),
            _BottomExportBar(
              orchestrator: _orchestrator,
              onEditMetadata: _openPackMetadataEditor,
              onExport: _exportToWhatsApp,
              onCancelExport: _cancelExport,
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomExportBar extends StatelessWidget {
  final StickerExportOrchestrator orchestrator;
  final VoidCallback onEditMetadata;
  final VoidCallback onExport;
  final VoidCallback onCancelExport;

  const _BottomExportBar({
    required this.orchestrator,
    required this.onEditMetadata,
    required this.onExport,
    required this.onCancelExport,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLightMode,
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: ValueListenableBuilder<ExportProgressState>(
          valueListenable: orchestrator.exportProgress,
          builder: (context, exportState, _) {
            if (exportState.isProcessing) {
              return ExportProgressSheet(
                progressListenable: orchestrator.exportProgress,
                onCancel: onCancelExport,
              );
            }

            return ListenableBuilder(
              listenable: orchestrator,
              builder: (context, _) {
                final selectedCount = orchestrator.selectedCount;
                final totalCount = orchestrator.totalCount;
                final hasCustom =
                    orchestrator.hasCustomName || orchestrator.hasCustomPublisher;

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '$selectedCount / $totalCount seçili',
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (selectedCount > 30)
                          StatusBadge(
                            label: '${(selectedCount / 30).ceil()} parça paket olacak',
                            color: AppTheme.warning,
                            icon: Icons.splitscreen_rounded,
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    InkWell(
                      onTap: onEditMetadata,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppTheme.surfaceDarkElevated.withAlpha(140)
                              : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: hasCustom
                                ? AppTheme.primaryBlue.withAlpha(140)
                                : (isDark
                                    ? const Color(0xFF334155)
                                    : const Color(0xFFE2E8F0)),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.label_outline_rounded,
                              size: 16,
                              color: hasCustom
                                  ? AppTheme.primaryBlue
                                  : AppTheme.getTextMut(context),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Paket Adı: ${orchestrator.previewPackNameForSelection(selectedCount)}',
                                    style: TextStyle(
                                      color: AppTheme.getText(context),
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    'Yayıncı: ${orchestrator.effectivePublisherSanitized}',
                                    style: TextStyle(
                                      color: AppTheme.getTextMut(context),
                                      fontSize: 11,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryBlue.withAlpha(24),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'Düzenle',
                                style: TextStyle(
                                  color: AppTheme.primaryBlue,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: GradientButton(
                        text: 'WhatsApp\'a Aktar',
                        icon: Icons.send_rounded,
                        gradient: AppTheme.whatsappGradient,
                        isLoading: false,
                        onPressed: selectedCount < 3 ? null : onExport,
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryBlue.withAlpha(isDark ? 35 : 20)
              : (isDark
                  ? AppTheme.surfaceDarkElevated
                  : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? AppTheme.primaryBlue
                : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? AppTheme.primaryBlue
                : (isDark
                    ? AppTheme.textSecondaryDark
                    : AppTheme.textSecondaryLight),
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
