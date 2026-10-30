import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lottie/lottie.dart';
import '../theme/app_theme.dart';
import '../models/telegram_sticker.dart';
import '../models/telegram_sticker_set.dart';
import '../models/saved_pack.dart';
import '../services/telegram_service.dart';
import '../services/sticker_processor.dart';
import '../services/whatsapp_service.dart';
import '../services/storage_service.dart';
import '../widgets/gradient_button.dart';
import '../widgets/status_badge.dart';
import '../widgets/animated_sticker_player.dart';

/// Preview screen showing all stickers in a pack with selection controls,
/// zooming inspector, emoji search, and WhatsApp export with automatic splitting.
class PackPreviewScreen extends StatefulWidget {
  final TelegramStickerSet stickerSet;

  const PackPreviewScreen({super.key, required this.stickerSet});

  @override
  State<PackPreviewScreen> createState() => _PackPreviewScreenState();
}

class _PackPreviewScreenState extends State<PackPreviewScreen> {
  final _telegramService = TelegramService();
  final _stickerProcessor = StickerProcessor();
  final _whatsappService = WhatsAppService();
  final _storageService = StorageService();

  // Thumbnail caching
  final Map<String, Uint8List> _thumbnails = {};
  // Vector Lottie JSON caching
  final Map<String, Uint8List> _lottieCache = {};
  // Active animated sticker shown in the live hero preview stage
  TelegramSticker? _activePreviewSticker;

  bool _isProcessing = false;
  double _progress = 0.0;
  String _statusText = '';
  bool _selectAll = true;

  // Filter mode: 0: All, 1: Selected, 2: Unselected
  int _filterIndex = 0;
  String _emojiSearch = '';
  bool _isSearchOpen = false;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initAndLoad();
  }

  Future<void> _initAndLoad() async {
    await _storageService.init();
    final savedToken = _storageService.getBotToken();
    if (savedToken != null && savedToken.isNotEmpty) {
      _telegramService.setBotToken(savedToken);
    }
    if (widget.stickerSet.stickers.isNotEmpty) {
      _activePreviewSticker = widget.stickerSet.stickers.first;
    }
    _loadThumbnails();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadThumbnails() async {
    final stickers = widget.stickerSet.stickers;
    const batchSize = 6;

    for (int i = 0; i < stickers.length; i += batchSize) {
      if (!mounted) break;
      final end = (i + batchSize < stickers.length)
          ? i + batchSize
          : stickers.length;
      final batch = stickers.sublist(i, end);

      final futures = batch.map((sticker) async {
        final thumbId = sticker.thumbFileId ?? sticker.fileId;
        if (!_thumbnails.containsKey(thumbId)) {
          final bytes = await _telegramService.downloadThumbnail(thumbId);
          return MapEntry(thumbId, bytes);
        }
        return null;
      });

      final results = await Future.wait(futures);
      if (!mounted) break;

      bool hasNew = false;
      for (final res in results) {
        if (res != null && res.value != null) {
          _thumbnails[res.key] = res.value!;
          hasNew = true;
        }
      }
      if (hasNew && mounted) {
        setState(() {});
      }

      // If pack is animated vector (.tgs), decompress Lottie bytes in background
      if (widget.stickerSet.isAnimated) {
        for (final sticker in batch) {
          if (sticker.isAnimated && !_lottieCache.containsKey(sticker.fileId)) {
            _loadLottieForSticker(sticker);
          }
        }
      }
    }
  }

  Future<void> _loadLottieForSticker(TelegramSticker sticker) async {
    try {
      final filePath = await _telegramService.downloadSticker(
        sticker,
        widget.stickerSet.name,
      );
      final file = File(filePath);
      if (await file.exists()) {
        final compressed = await file.readAsBytes();
        final unzipped = Uint8List.fromList(gzip.decode(compressed));
        if (mounted) {
          setState(() {
            _lottieCache[sticker.fileId] = unzipped;
          });
        }
      }
    } catch (_) {
      // Ignored, thumbnail will be used as fallback
    }
  }

  void _toggleSelectAll() {
    HapticFeedback.selectionClick();
    setState(() {
      _selectAll = !_selectAll;
      for (final sticker in widget.stickerSet.stickers) {
        sticker.isSelected = _selectAll;
      }
    });
  }

  void _invertSelection() {
    HapticFeedback.selectionClick();
    setState(() {
      for (final sticker in widget.stickerSet.stickers) {
        sticker.isSelected = !sticker.isSelected;
      }
      _selectAll = widget.stickerSet.stickers.every((s) => s.isSelected);
    });
  }

  void _showStickerDetail(TelegramSticker sticker) {
    HapticFeedback.lightImpact();
    final thumbId = sticker.thumbFileId ?? sticker.fileId;
    final thumbBytes = _thumbnails[thumbId];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final isDark = AppTheme.isDark(context);
            return Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              decoration: BoxDecoration(
                color: isDark
                    ? AppTheme.surfaceDark
                    : AppTheme.surfaceLightMode,
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
                  // Handle
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

                  // Animated sticker player (loops video/lottie live!)
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
                        packName: widget.stickerSet.name,
                        thumbnailBytes: thumbBytes,
                        size: 200,
                        autoPlay: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Emoji & Type info
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
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
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
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

                  // WhatsApp standard note
                  Text(
                    'WhatsApp standartları: 512×512 piksel, şeffaf arka plan, < 100 KB',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppTheme.textMuted.withAlpha(150),
                      fontSize: 11,
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Toggle selection button
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
                        setState(() {
                          sticker.isSelected = !sticker.isSelected;
                          _selectAll = widget.stickerSet.stickers.every(
                            (s) => s.isSelected,
                          );
                        });
                        setModalState(() {});
                        Navigator.pop(context);
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

  Future<void> _exportToWhatsApp() async {
    final selected = widget.stickerSet.stickers
        .where((s) => s.isSelected)
        .toList();
    if (selected.length < 3) {
      _showSnackBar('WhatsApp en az 3 çıkartma gerektirir.', isError: true);
      return;
    }

    setState(() {
      _isProcessing = true;
      _progress = 0;
      _statusText = 'Hazırlanıyor...';
    });

    try {
      final publisher = _storageService.getPublisherName();
      final outputDir = await _stickerProcessor.getPackOutputDir(
        widget.stickerSet.name,
      );

      // Split into WhatsApp packs (max 30 each)
      final chunks = _whatsappService.splitIntoPacks(selected);
      final preparedParts = <_PreparedPackPart>[];

      for (int chunkIdx = 0; chunkIdx < chunks.length; chunkIdx++) {
        final chunk = chunks[chunkIdx];
        final partSuffix = chunks.length > 1 ? ' Part ${chunkIdx + 1}' : '';
        final rawPackName = '${widget.stickerSet.title}$partSuffix';
        final packName = WhatsAppService.sanitizeForWhatsApp(
          rawPackName,
          fallback: 'Sticker Pack ${chunkIdx + 1}',
        );
        final idPartSuffix = chunks.length > 1 ? '_part${chunkIdx + 1}' : '';
        final packId = WhatsAppService.sanitizeIdentifier(
          '${widget.stickerSet.name}$idPartSuffix',
        );

        final stickerData = <Map<String, dynamic>>[];
        String? trayPath;

        for (int i = 0; i < chunk.length; i++) {
          final sticker = chunk[i];
          final totalIdx = chunkIdx * 30 + i;
          final totalCount = selected.length;

          final isAnimatedPack =
              widget.stickerSet.isAnimated ||
              widget.stickerSet.isVideo ||
              selected.any((s) => s.isAnimated || s.isVideo);

          setState(() {
            _progress = (totalIdx + 1) / totalCount;
            _statusText = sticker.isVideo
                ? 'Video işleniyor... (${totalIdx + 1}/$totalCount)'
                : 'İndiriliyor... (${totalIdx + 1}/$totalCount)';
          });

          String processedPath;
          if (sticker.isVideo) {
            // Download the actual .webm video file
            final videoPath = await _telegramService.downloadSticker(
              sticker,
              widget.stickerSet.name,
            );
            final thumbId = sticker.thumbFileId ?? sticker.fileId;
            var thumbBytes = _thumbnails[thumbId];
            thumbBytes ??= await _telegramService.downloadThumbnail(thumbId);

            processedPath = await _stickerProcessor.processVideoSticker(
              videoPath,
              outputDir,
              fallbackThumbnailBytes: thumbBytes,
            );
          } else if (sticker.isAnimated) {
            // Lottie / animated sticker
            final animatedPath = await _telegramService.downloadSticker(
              sticker,
              widget.stickerSet.name,
            );
            final thumbId = sticker.thumbFileId ?? sticker.fileId;
            var thumbBytes = _thumbnails[thumbId];
            thumbBytes ??= await _telegramService.downloadThumbnail(thumbId);

            processedPath = await _stickerProcessor.processLottieSticker(
              animatedPath,
              outputDir,
              fallbackThumbnailBytes: thumbBytes,
            );
          } else {
            // Static WebP sticker
            final downloadedPath = await _telegramService.downloadSticker(
              sticker,
              widget.stickerSet.name,
            );
            processedPath = await _stickerProcessor.processSticker(
              downloadedPath,
              outputDir,
              asAnimated: isAnimatedPack,
            );
          }

          // Generate tray icon from first sticker of each chunk
          if (i == 0) {
            setState(() {
              _statusText = 'Tepsi simgesi üretiliyor...';
            });
            trayPath = await _stickerProcessor.generateTrayIcon(
              processedPath,
              outputDir,
            );
          }

          stickerData.add({
            'path': processedPath,
            'emojis': [sticker.emoji],
          });
        }

        // Ensure we have a tray icon
        trayPath ??= await _stickerProcessor.generateTrayIcon(
          stickerData.first['path'] as String,
          outputDir,
        );

        final isAnimatedPack =
            widget.stickerSet.isAnimated ||
            widget.stickerSet.isVideo ||
            selected.any((s) => s.isAnimated || s.isVideo);

        final partItem = _PreparedPackPart(
          index: chunkIdx,
          totalParts: chunks.length,
          packId: packId,
          packName: packName,
          publisher: publisher,
          trayPath: trayPath,
          stickerData: stickerData,
          isAnimated: isAnimatedPack,
        );
        preparedParts.add(partItem);

        // Pre-save to local storage so pack is never lost
        await _storageService.savePack(
          SavedPack(
            identifier: packId,
            name: packName,
            publisher: publisher,
            trayImagePath: trayPath,
            stickerPaths: stickerData.map((d) => d['path'] as String).toList(),
            emojis: stickerData
                .map((d) => (d['emojis'] as List).first as String)
                .toList(),
            stickerCount: stickerData.length,
            savedAt: DateTime.now(),
            isAnimated: isAnimatedPack,
            addedToWhatsApp: false,
          ),
        );
      }

      // Finish processing state
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _progress = 0;
          _statusText = '';
        });
      }

      if (preparedParts.isEmpty) return;

      // Single-part export
      if (preparedParts.length == 1) {
        final part = preparedParts.first;
        final result = await _whatsappService.addStickerPack(
          identifier: part.packId,
          name: part.packName,
          publisher: part.publisher,
          trayPath: part.trayPath,
          stickerData: part.stickerData,
          animatedStickerPack: part.isAnimated,
        );

        if (!mounted) return;

        if (result.isAdded) {
          await _storageService.updatePackStatus(part.packId, true);
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
      } else {
        // Multi-part export: present controlled multi-step sheet
        if (!mounted) return;
        await _showMultiPartExportSheet(preparedParts);
      }
    } catch (e, stackTrace) {
      debugPrint('❌ WhatsApp Export Error: $e\n$stackTrace');
      if (mounted) {
        _showSnackBar(
          'Hata: ${e.toString().replaceAll('Exception: ', '')}',
          isError: true,
        );
      }
    } finally {
      if (mounted && _isProcessing) {
        setState(() {
          _isProcessing = false;
          _progress = 0;
          _statusText = '';
        });
      }
    }
  }

  Future<void> _showMultiPartExportSheet(
    List<_PreparedPackPart> preparedParts,
  ) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _MultiPartExportSheet(
          preparedParts: preparedParts,
          whatsappService: _whatsappService,
          storageService: _storageService,
        );
      },
    );
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

  Widget _buildLiveHeroPreview(
    TelegramStickerSet set,
    List<TelegramSticker> filtered,
  ) {
    final isDark = AppTheme.isDark(context);
    final active = _activePreviewSticker ?? set.stickers.firstOrNull;
    if (active == null) return const SizedBox.shrink();

    final thumbId = active.thumbFileId ?? active.fileId;
    final thumbBytes = _thumbnails[thumbId];
    final activeIndex = filtered.indexOf(active);

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
          // Live Looping Player Stage
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
                  packName: widget.stickerSet.name,
                  thumbnailBytes: thumbBytes,
                  size: 104,
                  autoPlay: true,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Details & Controls
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Live Badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color:
                        (set.isVideo
                                ? AppTheme.accentSecondary
                                : AppTheme.accentPrimary)
                            .withAlpha(30),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color:
                          (set.isVideo
                                  ? AppTheme.accentSecondary
                                  : AppTheme.accentPrimary)
                              .withAlpha(80),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        set.isVideo
                            ? Icons.videocam_rounded
                            : Icons.auto_awesome_rounded,
                        size: 12,
                        color: set.isVideo
                            ? AppTheme.accentSecondary
                            : AppTheme.accentPrimary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        set.isVideo
                            ? 'Canlı Video Döngüsü'
                            : 'Canlı Lottie Animasyon',
                        style: TextStyle(
                          color: set.isVideo
                              ? AppTheme.accentSecondary
                              : AppTheme.accentPrimary,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),

                // Emoji & Index
                Row(
                  children: [
                    Text(active.emoji, style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        activeIndex >= 0
                            ? 'Canlı Önizleme #${activeIndex + 1}'
                            : 'Canlı Önizleme',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),

                // Helper text
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

                // Full screen inspector button
                InkWell(
                  onTap: () => _showStickerDetail(active),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.open_in_full_rounded,
                        size: 12,
                        color: AppTheme.accentPrimary,
                      ),
                      const SizedBox(width: 4),
                      const Text(
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
  }

  List<TelegramSticker> get _filteredStickers {
    return widget.stickerSet.stickers.where((s) {
      if (_filterIndex == 1 && !s.isSelected) return false;
      if (_filterIndex == 2 && s.isSelected) return false;
      if (_emojiSearch.isNotEmpty && !s.emoji.contains(_emojiSearch)) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final set = widget.stickerSet;
    final selectedCount = set.selectedCount;
    final totalCount = set.stickers.length;
    final filtered = _filteredStickers;

    return Scaffold(
      backgroundColor: AppTheme.getBackground(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_rounded,
            size: 20,
            color: AppTheme.getText(context),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          children: [
            Text(
              set.title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppTheme.getText(context),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
                  _emojiSearch = '';
                  _searchController.clear();
                }
              });
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(
              Icons.more_vert_rounded,
              color: AppTheme.textPrimary,
            ),
            color: AppTheme.surfaceDark,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            onSelected: (val) {
              if (val == 'all') _toggleSelectAll();
              if (val == 'invert') _invertSelection();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'all',
                child: Text(
                  _selectAll ? 'Seçimi Kaldır' : 'Tümünü Seç',
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
          ),
        ],
      ),
      body: Column(
        children: [
          // ─── Search Bar ──────────────────────────────────
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
                  onChanged: (val) => setState(() => _emojiSearch = val.trim()),
                ),
              ),
            ),

          // ─── Filter & Selection Bar ───────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _FilterChip(
                  label: 'Tümü ($totalCount)',
                  isSelected: _filterIndex == 0,
                  onTap: () => setState(() => _filterIndex = 0),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Seçili ($selectedCount)',
                  isSelected: _filterIndex == 1,
                  onTap: () => setState(() => _filterIndex = 1),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Kalan (${totalCount - selectedCount})',
                  isSelected: _filterIndex == 2,
                  onTap: () => setState(() => _filterIndex = 2),
                ),
              ],
            ),
          ),

          // ─── Live Animated / Video Hero Preview Stage ─────
          if (set.isAnimated || set.isVideo)
            _buildLiveHeroPreview(set, filtered),

          // ─── Sticker Grid ────────────────────────────────
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      'Bu filtreye uygun çıkartma bulunamadı.',
                      style: TextStyle(
                        color: AppTheme.textMuted.withAlpha(150),
                      ),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final sticker = filtered[index];
                      final thumbId = sticker.thumbFileId ?? sticker.fileId;
                      final thumbBytes = _thumbnails[thumbId];
                      final isCurrentHero =
                          _activePreviewSticker?.fileId == sticker.fileId;

                      return GestureDetector(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() {
                                _activePreviewSticker = sticker;
                                sticker.isSelected = !sticker.isSelected;
                                _selectAll = set.stickers.every(
                                  (s) => s.isSelected,
                                );
                              });
                            },
                            onLongPress: () {
                              setState(() => _activePreviewSticker = sticker);
                              _showStickerDetail(sticker);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              decoration: BoxDecoration(
                                color: sticker.isSelected
                                    ? (isDark
                                          ? AppTheme.surfaceDarkElevated
                                          : const Color(0xFFEFF6FF))
                                    : (isDark
                                          ? AppTheme.cardDark
                                          : AppTheme.cardLight),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isCurrentHero
                                      ? AppTheme.primaryBlue
                                      : (sticker.isSelected
                                            ? AppTheme.primaryBlue
                                            : (isDark
                                                  ? const Color(0xFF334155)
                                                  : const Color(0xFFE2E8F0))),
                                  width: isCurrentHero
                                      ? 2.0
                                      : (sticker.isSelected ? 2.0 : 1.0),
                                ),
                              ),
                              child: Stack(
                                children: [
                                  // Sticker image or live vector Lottie
                                  Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(6),
                                      child:
                                          sticker.isAnimated &&
                                              _lottieCache.containsKey(
                                                sticker.fileId,
                                              )
                                          ? Lottie.memory(
                                              _lottieCache[sticker.fileId]!,
                                              fit: BoxFit.contain,
                                              repeat: true,
                                              errorBuilder: (_, _, _) =>
                                                  thumbBytes != null
                                                  ? Image.memory(
                                                      thumbBytes,
                                                      fit: BoxFit.contain,
                                                      errorBuilder: (_, _, _) =>
                                                          _placeholderIcon(
                                                            sticker.emoji,
                                                          ),
                                                    )
                                                  : _placeholderIcon(
                                                      sticker.emoji,
                                                    ),
                                            )
                                          : (thumbBytes != null
                                                ? Image.memory(
                                                    thumbBytes,
                                                    fit: BoxFit.contain,
                                                    errorBuilder: (_, _, _) =>
                                                        _placeholderIcon(
                                                          sticker.emoji,
                                                        ),
                                                  )
                                                : _placeholderIcon(
                                                    sticker.emoji,
                                                  )),
                                    ),
                                  ),
                                  // Selection indicator
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: AnimatedScale(
                                      scale: sticker.isSelected ? 1.0 : 0.0,
                                      duration: const Duration(
                                        milliseconds: 200,
                                      ),
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
                                  // Emoji label
                                  Positioned(
                                    bottom: 4,
                                    left: 4,
                                    child: Text(
                                      sticker.emoji,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  // Play / Live badge indicator
                                  Positioned(
                                    bottom: 2,
                                    right: 2,
                                    child: InkWell(
                                      onTap: () {
                                        setState(
                                          () => _activePreviewSticker = sticker,
                                        );
                                        _showStickerDetail(sticker);
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isCurrentHero
                                              ? AppTheme.accentSecondary
                                                    .withAlpha(200)
                                              : ((sticker.isVideo ||
                                                        sticker.isAnimated)
                                                    ? AppTheme.accentPrimary
                                                          .withAlpha(80)
                                                    : Colors.black.withAlpha(
                                                        80,
                                                      )),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              sticker.isVideo ||
                                                      sticker.isAnimated
                                                  ? Icons.play_arrow_rounded
                                                  : Icons.zoom_in_rounded,
                                              size: 11,
                                              color: Colors.white,
                                            ),
                                            if (sticker.isVideo ||
                                                sticker.isAnimated) ...[
                                              const SizedBox(width: 1),
                                              Text(
                                                isCurrentHero
                                                    ? 'OYNATILIYOR'
                                                    : 'CANLI',
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
                  ),
          ),

          // ─── Bottom Action Bar ────────────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLightMode,
              border: Border(
                top: BorderSide(
                  color: isDark
                      ? const Color(0xFF334155)
                      : const Color(0xFFE2E8F0),
                ),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Progress bar
                  if (_isProcessing) ...[
                    Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _statusText,
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              '${(_progress * 100).toInt()}%',
                              style: const TextStyle(
                                color: AppTheme.accentPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: _progress,
                            minHeight: 6,
                            backgroundColor: AppTheme.backgroundDark,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              AppTheme.accentPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                    ),
                  ],
                  // Info row
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
                          label:
                              '${(selectedCount / 30).ceil()} parça paket olacak',
                          color: AppTheme.warning,
                          icon: Icons.splitscreen_rounded,
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: GradientButton(
                      text: 'WhatsApp\'a Aktar',
                      icon: Icons.send_rounded,
                      gradient: AppTheme.whatsappGradient,
                      isLoading: _isProcessing,
                      onPressed: _isProcessing || selectedCount < 3
                          ? null
                          : _exportToWhatsApp,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholderIcon(String emoji, {double size = 26}) {
    final isDark = AppTheme.isDark(context);
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDarkElevated : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(emoji, style: TextStyle(fontSize: size)),
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

class _PreparedPackPart {
  final int index;
  final int totalParts;
  final String packId;
  final String packName;
  final String publisher;
  final String trayPath;
  final List<Map<String, dynamic>> stickerData;
  final bool isAnimated;
  bool isAddedToWhatsApp = false;
  bool isCancelled = false;
  String? error;

  _PreparedPackPart({
    required this.index,
    required this.totalParts,
    required this.packId,
    required this.packName,
    required this.publisher,
    required this.trayPath,
    required this.stickerData,
    required this.isAnimated,
  });
}

class _MultiPartExportSheet extends StatefulWidget {
  final List<_PreparedPackPart> preparedParts;
  final WhatsAppService whatsappService;
  final StorageService storageService;

  const _MultiPartExportSheet({
    required this.preparedParts,
    required this.whatsappService,
    required this.storageService,
  });

  @override
  State<_MultiPartExportSheet> createState() => _MultiPartExportSheetState();
}

class _MultiPartExportSheetState extends State<_MultiPartExportSheet> {
  int? _activeSendingIndex;

  int get _nextPendingIndex {
    return widget.preparedParts.indexWhere((p) => !p.isAddedToWhatsApp);
  }

  bool get _isAllAdded {
    return widget.preparedParts.every((p) => p.isAddedToWhatsApp);
  }

  int get _addedCount {
    return widget.preparedParts.where((p) => p.isAddedToWhatsApp).length;
  }

  Future<void> _exportPart(_PreparedPackPart part) async {
    if (_activeSendingIndex != null) return;

    setState(() {
      _activeSendingIndex = part.index;
      part.error = null;
      part.isCancelled = false;
    });

    try {
      final result = await widget.whatsappService.addStickerPack(
        identifier: part.packId,
        name: part.packName,
        publisher: part.publisher,
        trayPath: part.trayPath,
        stickerData: part.stickerData,
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
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Title & Progress Summary
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
                    const Text(
                      'Çok Parçalı WhatsApp Aktarımı',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      allDone
                          ? 'Tüm parçalar WhatsApp\'a eklendi!'
                          : '$_addedCount / $total parça eklendi (WhatsApp paketi başına maks 30 çıkartma)',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? AppTheme.textMutedDark : AppTheme.textMutedLight,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Informational note
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.surfaceDarkElevated : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: isDark ? AppTheme.textMutedDark : AppTheme.textMutedLight,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'WhatsApp her paketi ayrı bir onay ekranıyla kabul eder. Parçaları sırayla onaylayarak kolayca aktarabilirsiniz.',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? AppTheme.textMutedDark : AppTheme.textMutedLight,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Parts list
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: widget.preparedParts.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, idx) {
                final part = widget.preparedParts[idx];
                final isSendingThis = _activeSendingIndex == part.index;
                final isNext = nextIdx == part.index;

                Color borderColor;
                if (part.isAddedToWhatsApp) {
                  borderColor = AppTheme.success.withAlpha(120);
                } else if (isNext) {
                  borderColor = AppTheme.whatsappGreen;
                } else {
                  borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
                }

                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.cardDark : AppTheme.cardLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: borderColor, width: isNext ? 1.5 : 1),
                  ),
                  child: Row(
                    children: [
                      // Tray icon preview
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
                                color: isDark ? AppTheme.surfaceDarkElevated : const Color(0xFFE2E8F0),
                                child: const Icon(Icons.image_outlined, size: 20),
                              ),
                      ),
                      const SizedBox(width: 12),

                      // Part title and count
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              part.packName,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${part.stickerData.length} çıkartma ${part.isAnimated ? "• Hareketli" : ""}',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? AppTheme.textMutedDark : AppTheme.textMutedLight,
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
                                maxLines: 1,
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

                      // Action / Status indicator
                      if (isSendingThis)
                        const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(AppTheme.whatsappGreen),
                          ),
                        )
                      else if (part.isAddedToWhatsApp)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.success.withAlpha(25),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppTheme.success.withAlpha(80)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle_rounded, size: 13, color: AppTheme.success),
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
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            minimumSize: Size.zero,
                            side: BorderSide(
                              color: isNext ? AppTheme.whatsappGreen : (isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1)),
                            ),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: Text(
                            part.isCancelled || part.error != null ? 'Tekrar Dene' : 'Ekle',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isNext ? AppTheme.whatsappGreen : AppTheme.textPrimary,
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

          // Primary bottom button
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
              onPressed: _activeSendingIndex != null ? null : () => Navigator.pop(context),
              child: Text(
                'Daha Sonra Tamamla',
                style: TextStyle(
                  color: isDark ? AppTheme.textMutedDark : AppTheme.textMutedLight,
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
