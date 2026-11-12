import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/saved_pack.dart';
import '../models/telegram_sticker.dart';
import '../models/telegram_sticker_set.dart';
import 'sticker_processor.dart';
import 'storage_service.dart';
import 'telegram_service.dart';
import 'whatsapp_service.dart';

/// Lifecycle states for sticker pack export preparation.
enum ExportStage {
  idle,
  preparing,
  completed,
  cancelled,
  error,
}

/// Immutable snapshot of export preparation progress.
class ExportProgressState {
  final ExportStage stage;
  final double progress;
  final String statusText;

  const ExportProgressState({
    required this.stage,
    required this.progress,
    required this.statusText,
  });

  const ExportProgressState.idle()
      : stage = ExportStage.idle,
        progress = 0.0,
        statusText = '';

  bool get isProcessing => stage == ExportStage.preparing;
}

/// Prepared WhatsApp sticker pack slice (at most 30 stickers per part).
class PreparedPackPart {
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

  PreparedPackPart({
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

/// Coordinates thumbnail loading, sticker selection, metadata overrides,
/// bounded parallel conversion, and multi-part splitting for [PackPreviewScreen].
class StickerExportOrchestrator extends ChangeNotifier {
  final TelegramStickerSet stickerSet;
  final TelegramService telegramService;
  final StickerProcessor stickerProcessor;
  final WhatsAppService whatsappService;
  final StorageService storageService;

  final Map<String, Uint8List> thumbnails = {};
  final Map<String, Uint8List> lottieCache = {};

  final ValueNotifier<ExportProgressState> exportProgress =
      ValueNotifier(const ExportProgressState.idle());
  final ValueNotifier<TelegramSticker?> activePreviewSticker;
  final ValueNotifier<int> mediaCacheVersion = ValueNotifier<int>(0);

  bool _isDisposed = false;
  bool _isCancelled = false;
  bool _selectAll = true;
  int _filterIndex = 0;
  String _emojiSearch = '';
  String? _customPackName;
  String? _customPublisher;
  String _defaultPublisher = 'StickerSwap';

  StickerExportOrchestrator({
    required this.stickerSet,
    TelegramService? telegramService,
    StickerProcessor? stickerProcessor,
    WhatsAppService? whatsappService,
    StorageService? storageService,
  })  : telegramService = telegramService ?? TelegramService(),
        stickerProcessor = stickerProcessor ?? StickerProcessor(),
        whatsappService = whatsappService ?? WhatsAppService(),
        storageService = storageService ?? StorageService(),
        activePreviewSticker = ValueNotifier<TelegramSticker?>(
          stickerSet.stickers.firstOrNull,
        ) {
    _selectAll = stickerSet.stickers.isNotEmpty &&
        stickerSet.stickers.every((s) => s.isSelected);
  }

  bool get isProcessing => exportProgress.value.isProcessing;
  bool get isCancelled => _isCancelled;
  bool get selectAll => _selectAll;
  int get filterIndex => _filterIndex;
  String get emojiSearch => _emojiSearch;
  String get defaultPublisher => _defaultPublisher;
  int get selectedCount => stickerSet.selectedCount;
  int get totalCount => stickerSet.stickers.length;

  bool get hasCustomName {
    final custom = _customPackName?.trim();
    if (custom == null || custom.isEmpty) return false;
    return custom != stickerSet.title.trim();
  }

  bool get hasCustomPublisher {
    final custom = _customPublisher?.trim();
    if (custom == null || custom.isEmpty) return false;
    return custom != _defaultPublisher.trim();
  }

  String get effectiveDisplayTitle {
    final custom = _customPackName?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    return stickerSet.title;
  }

  String get effectivePublisherRaw {
    final custom = _customPublisher?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    return _defaultPublisher;
  }

  String get effectivePublisherSanitized => WhatsAppService.sanitizeForWhatsApp(
        effectivePublisherRaw,
        fallback: 'StickerSwap',
      );

  String previewPackNameForSelection([int? countOverride]) {
    final count = countOverride ?? selectedCount;
    final totalParts = count > 30 ? (count / 30).ceil() : 1;
    final part1 = WhatsAppService.buildPackName(
      customName: _customPackName,
      defaultTitle: stickerSet.title,
      partIndex: 0,
      totalParts: totalParts,
    );
    if (totalParts > 1) {
      return '$part1 (1/$totalParts)';
    }
    return part1;
  }

  List<TelegramSticker> get filteredStickers {
    return stickerSet.stickers.where((s) {
      if (_filterIndex == 1 && !s.isSelected) return false;
      if (_filterIndex == 2 && s.isSelected) return false;
      if (_emojiSearch.isNotEmpty && !s.emoji.contains(_emojiSearch)) {
        return false;
      }
      return true;
    }).toList();
  }

  Future<void> initAndLoad() async {
    await storageService.init();
    if (_isDisposed) return;

    _defaultPublisher = storageService.getPublisherName();
    notifyListeners();

    final savedToken = await storageService.getBotToken();
    if (_isDisposed) return;
    if (savedToken != null && savedToken.isNotEmpty) {
      telegramService.setBotToken(savedToken);
    }
    await _loadThumbnails();
  }

  void setFilterIndex(int index) {
    if (_filterIndex == index) return;
    _filterIndex = index;
    notifyListeners();
  }

  void setEmojiSearch(String query) {
    final trimmed = query.trim();
    if (_emojiSearch == trimmed) return;
    _emojiSearch = trimmed;
    notifyListeners();
  }

  void setActivePreviewSticker(TelegramSticker sticker) {
    activePreviewSticker.value = sticker;
  }

  void toggleStickerSelection(
    TelegramSticker sticker, {
    bool setAsActive = true,
  }) {
    if (setAsActive) {
      activePreviewSticker.value = sticker;
    }
    sticker.isSelected = !sticker.isSelected;
    _selectAll = stickerSet.stickers.every((s) => s.isSelected);
    notifyListeners();
  }

  void toggleSelectAll() {
    _selectAll = !_selectAll;
    for (final sticker in stickerSet.stickers) {
      sticker.isSelected = _selectAll;
    }
    notifyListeners();
  }

  void invertSelection() {
    for (final sticker in stickerSet.stickers) {
      sticker.isSelected = !sticker.isSelected;
    }
    _selectAll = stickerSet.stickers.every((s) => s.isSelected);
    notifyListeners();
  }

  void updateMetadataOverrides({
    required String packName,
    String? publisher,
  }) {
    final nextName = packName.trim();
    _customPackName =
        (nextName.isEmpty || nextName == stickerSet.title.trim())
            ? null
            : nextName;

    final nextPublisher = publisher?.trim() ?? '';
    _customPublisher =
        (nextPublisher.isEmpty || nextPublisher == _defaultPublisher.trim())
            ? null
            : nextPublisher;
    notifyListeners();
  }

  Future<void> _loadThumbnails() async {
    final stickers = stickerSet.stickers;
    const batchSize = 6;

    for (int i = 0; i < stickers.length; i += batchSize) {
      if (_isDisposed) break;
      final end = (i + batchSize < stickers.length)
          ? i + batchSize
          : stickers.length;
      final batch = stickers.sublist(i, end);

      final futures = batch.map((sticker) async {
        final thumbId = sticker.thumbFileId ?? sticker.fileId;
        if (!thumbnails.containsKey(thumbId)) {
          final bytes = await telegramService.downloadThumbnail(thumbId);
          return MapEntry(thumbId, bytes);
        }
        return null;
      });

      final results = await Future.wait(futures);
      if (_isDisposed) break;

      bool hasNew = false;
      for (final res in results) {
        if (res != null && res.value != null) {
          thumbnails[res.key] = res.value!;
          hasNew = true;
        }
      }
      if (hasNew && !_isDisposed) {
        mediaCacheVersion.value++;
      }

      if (stickerSet.isAnimated) {
        for (final sticker in batch) {
          if (sticker.isAnimated && !lottieCache.containsKey(sticker.fileId)) {
            _loadLottieForSticker(sticker);
          }
        }
      }
    }
  }

  Future<void> _loadLottieForSticker(TelegramSticker sticker) async {
    try {
      final filePath = await telegramService.downloadSticker(
        sticker,
        stickerSet.name,
      );
      if (_isDisposed) return;
      final file = File(filePath);
      if (await file.exists()) {
        final compressed = await file.readAsBytes();
        final unzipped = Uint8List.fromList(gzip.decode(compressed));
        if (!_isDisposed) {
          lottieCache[sticker.fileId] = unzipped;
          mediaCacheVersion.value++;
        }
      }
    } catch (_) {
      // Ignored; thumbnail remains as fallback.
    }
  }

  /// Prepares all selected stickers into 1..N WhatsApp-compliant parts (<= 30 each).
  /// Returns `null` if cancelled or disposed before completion.
  Future<List<PreparedPackPart>?> preparePartsForExport() async {
    final selected = stickerSet.stickers.where((s) => s.isSelected).toList();
    if (selected.length < 3) {
      throw StateError('WhatsApp en az 3 çıkartma gerektirir.');
    }

    _isCancelled = false;
    exportProgress.value = const ExportProgressState(
      stage: ExportStage.preparing,
      progress: 0.0,
      statusText: 'Başlatılıyor...',
    );

    try {
      final publisher = effectivePublisherSanitized;
      final outputDir = await stickerProcessor.getPackOutputDir(stickerSet.name);
      final chunks = whatsappService.splitIntoPacks(selected);
      final preparedParts = <PreparedPackPart>[];
      final totalSelected = selected.length;
      int completedTotalCount = 0;

      for (int chunkIdx = 0; chunkIdx < chunks.length; chunkIdx++) {
        if (_isCancelled || _isDisposed) return null;

        final chunk = chunks[chunkIdx];
        final packName = WhatsAppService.buildPackName(
          customName: _customPackName,
          defaultTitle: stickerSet.title,
          partIndex: chunkIdx,
          totalParts: chunks.length,
        );
        final idPartSuffix = chunks.length > 1 ? '_part${chunkIdx + 1}' : '';
        final packId = WhatsAppService.sanitizeIdentifier(
          '${stickerSet.name}$idPartSuffix',
        );

        final isAnimatedPack = stickerSet.isAnimated ||
            stickerSet.isVideo ||
            chunk.any((s) => s.isAnimated || s.isVideo);

        final stickerDataSlots = List<Map<String, dynamic>?>.filled(
          chunk.length,
          null,
        );

        const int maxConcurrency = 3;
        final int workerCount =
            chunk.length < maxConcurrency ? chunk.length : maxConcurrency;
        int nextWorkerIndex = 0;

        Future<void> runStickerWorker() async {
          while (true) {
            if (_isCancelled || _isDisposed) return;
            if (nextWorkerIndex >= chunk.length) return;
            final itemIndex = nextWorkerIndex++;
            final sticker = chunk[itemIndex];

            if (!_isDisposed && !_isCancelled) {
              exportProgress.value = ExportProgressState(
                stage: ExportStage.preparing,
                progress: exportProgress.value.progress,
                statusText: sticker.isVideo
                    ? 'Video işleniyor... (${completedTotalCount + 1}/$totalSelected)'
                    : 'Çıkartma hazırlanıyor... (${completedTotalCount + 1}/$totalSelected)',
              );
            }

            try {
              final processedPath = await _prepareSingleSticker(
                sticker: sticker,
                outputDir: outputDir,
                isAnimatedPack: isAnimatedPack,
                forceRefresh: false,
              );

              if (_isCancelled || _isDisposed) return;

              stickerDataSlots[itemIndex] = {
                'path': processedPath,
                'emojis': WhatsAppService.sanitizeEmojis(sticker.emoji),
              };

              completedTotalCount++;
              if (!_isDisposed && !_isCancelled) {
                final progress =
                    (completedTotalCount / totalSelected).clamp(0.0, 1.0);
                exportProgress.value = ExportProgressState(
                  stage: ExportStage.preparing,
                  progress: progress,
                  statusText:
                      'Hazırlanıyor: $completedTotalCount / $totalSelected (%${(progress * 100).toInt()})',
                );
              }
            } catch (err) {
              if (kDebugMode) {
                debugPrint('Error preparing sticker ${sticker.fileId}: $err');
              }
              rethrow;
            }
          }
        }

        final workers = List.generate(workerCount, (_) => runStickerWorker());
        await Future.wait(workers);

        if (_isCancelled || _isDisposed) return null;

        final stickerData =
            stickerDataSlots.whereType<Map<String, dynamic>>().toList();
        if (stickerData.length < 3) {
          throw Exception('Bu parçada en az 3 geçerli çıkartma hazırlanamadı.');
        }

        if (!_isDisposed && !_isCancelled) {
          exportProgress.value = ExportProgressState(
            stage: ExportStage.preparing,
            progress: exportProgress.value.progress,
            statusText: 'Tepsi simgesi üretiliyor... (Parça ${chunkIdx + 1})',
          );
        }
        final trayFileName = 'tray_$packId.png';
        final trayPath = await stickerProcessor.generateTrayIcon(
          stickerData.first['path'] as String,
          outputDir,
          fileName: trayFileName,
          forceRefresh: false,
        );

        if (_isCancelled || _isDisposed) return null;

        final partItem = PreparedPackPart(
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

        await storageService.savePack(
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

      if (_isCancelled || _isDisposed) return null;

      exportProgress.value = const ExportProgressState(
        stage: ExportStage.completed,
        progress: 1.0,
        statusText: '',
      );
      exportProgress.value = const ExportProgressState.idle();
      return preparedParts;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('❌ WhatsApp Export Error: $e\n$stackTrace');
      }
      if (!_isDisposed) {
        exportProgress.value = ExportProgressState(
          stage: _isCancelled ? ExportStage.cancelled : ExportStage.error,
          progress: 0.0,
          statusText: '',
        );
        exportProgress.value = const ExportProgressState.idle();
      }
      if (_isCancelled || _isDisposed) return null;
      rethrow;
    }
  }

  Future<String> _prepareSingleSticker({
    required TelegramSticker sticker,
    required String outputDir,
    required bool isAnimatedPack,
    bool forceRefresh = false,
  }) async {
    final downloadedPath = await telegramService.downloadSticker(
      sticker,
      stickerSet.name,
    );

    if (!sticker.isVideo && !sticker.isAnimated) {
      return await stickerProcessor.processSticker(
        downloadedPath,
        outputDir,
        asAnimated: isAnimatedPack,
        forceRefresh: forceRefresh,
      );
    }

    Uint8List? thumbBytes;
    final thumbId = sticker.thumbFileId;
    if (thumbId != null && thumbId.isNotEmpty) {
      thumbBytes = thumbnails[thumbId] ??
          await telegramService.downloadThumbnail(thumbId);
    }

    if (sticker.isVideo) {
      return await stickerProcessor.processVideoSticker(
        downloadedPath,
        outputDir,
        fallbackThumbnailBytes: thumbBytes,
        forceRefresh: forceRefresh,
      );
    }

    return await stickerProcessor.processLottieSticker(
      downloadedPath,
      outputDir,
      fallbackThumbnailBytes: thumbBytes,
      forceRefresh: forceRefresh,
    );
  }

  void cancelExport() {
    if (!isProcessing) return;
    _isCancelled = true;
    exportProgress.value = const ExportProgressState(
      stage: ExportStage.cancelled,
      progress: 0.0,
      statusText: '',
    );
    exportProgress.value = const ExportProgressState.idle();
  }

  Future<void> markPackAddedToWhatsApp(String packId) async {
    await storageService.updatePackStatus(packId, true);
  }

  @override
  void dispose() {
    _isDisposed = true;
    _isCancelled = true;
    exportProgress.dispose();
    activePreviewSticker.dispose();
    mediaCacheVersion.dispose();
    super.dispose();
  }
}
