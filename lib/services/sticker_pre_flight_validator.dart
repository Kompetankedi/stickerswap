import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'webp_inspector.dart';
import 'whatsapp_service.dart';

/// Specific WhatsApp compliance issue detected before triggering the export intent.
enum PreFlightIssueType {
  missingFile,
  emptyFile,
  invalidWebpHeader,
  invalidDimensions,
  oversizedFile,
  invalidFrameCount,
  exceedsMaxDuration,
  invalidEmojis,
}

/// Validation failure details for a single sticker inside a pack.
class StickerValidationIssue {
  final int stickerIndex;
  final String path;
  final List<PreFlightIssueType> issues;
  final List<String> reasons;
  final int? fileSizeBytes;
  final int? width;
  final int? height;
  final int? frameCount;
  final int? durationMs;
  final bool canFixByRecompress;

  const StickerValidationIssue({
    required this.stickerIndex,
    required this.path,
    required this.issues,
    required this.reasons,
    this.fileSizeBytes,
    this.width,
    this.height,
    this.frameCount,
    this.durationMs,
    this.canFixByRecompress = false,
  });

  String get fileName => path.isEmpty ? '#${stickerIndex + 1}' : p.basename(path);
}

/// Result of inspecting an entire sticker pack before sending it to WhatsApp.
class PreFlightValidationReport {
  final int totalStickers;
  final bool isAnimatedPack;
  final List<String> packErrors;
  final List<StickerValidationIssue> stickerIssues;
  final List<Map<String, dynamic>> validStickerData;

  const PreFlightValidationReport({
    required this.totalStickers,
    required this.isAnimatedPack,
    required this.packErrors,
    required this.stickerIssues,
    required this.validStickerData,
  });

  bool get isValid => packErrors.isEmpty && stickerIssues.isEmpty;

  int get invalidCount => stickerIssues.length;

  int get validCount => validStickerData.length;

  /// True when removing invalid stickers still leaves a valid >= 3 sticker pack.
  bool get canContinueByExcluding =>
      packErrors.isEmpty && stickerIssues.isNotEmpty && validStickerData.length >= 3;

  bool get hasRecompressibleIssues =>
      stickerIssues.any((issue) => issue.canFixByRecompress);

  List<int> get invalidIndices =>
      stickerIssues.map((issue) => issue.stickerIndex).toList(growable: false);

  String buildSummaryHeadline() {
    if (isValid) {
      return 'Tüm çıkartmalar WhatsApp kurallarına uygun.';
    }
    if (packErrors.isNotEmpty) {
      return packErrors.first;
    }
    return '${stickerIssues.length} çıkartma WhatsApp sınırlarını veya biçim kurallarını karşılamıyor.';
  }
}

/// Validates processed WebP stickers, tray icon, dimensions, duration,
/// frame count, and emojis locally before invoking WhatsApp's all-or-nothing Intent.
class StickerPreFlightValidator {
  static const int requiredDimension = 512;
  static const int requiredTrayDimension = 96;
  static const int minPackStickers = 3;
  static const int maxPackStickers = 30;
  static const int maxStaticBytes = 96 * 1024;
  static const int maxAnimatedBytes = 470 * 1024;
  static const int maxTrayBytes = 48 * 1024;
  static const int maxAnimatedDurationMs = 3000;

  final int staticByteLimit;
  final int animatedByteLimit;
  final int trayByteLimit;
  final int durationLimitMs;

  const StickerPreFlightValidator({
    this.staticByteLimit = maxStaticBytes,
    this.animatedByteLimit = maxAnimatedBytes,
    this.trayByteLimit = maxTrayBytes,
    this.durationLimitMs = maxAnimatedDurationMs,
  });

  /// Runs pre-flight checks on [trayPath] and every entry in [stickerData].
  Future<PreFlightValidationReport> validatePack({
    required String trayPath,
    required List<Map<String, dynamic>> stickerData,
    required bool isAnimatedPack,
  }) async {
    final packErrors = <String>[];
    final stickerIssues = <StickerValidationIssue>[];
    final validStickerData = <Map<String, dynamic>>[];

    if (stickerData.length < minPackStickers) {
      packErrors.add(
        'WhatsApp en az $minPackStickers çıkartma gerektirir (pakette ${stickerData.length} adet var).',
      );
    } else if (stickerData.length > maxPackStickers) {
      packErrors.add(
        'WhatsApp tek pakette en fazla $maxPackStickers çıkartmaya izin verir (${stickerData.length} adet).',
      );
    }

    await _validateTrayIcon(trayPath, packErrors);

    for (int i = 0; i < stickerData.length; i++) {
      final item = stickerData[i];
      final issue = await _validateSingleSticker(
        index: i,
        item: item,
        isAnimatedPack: isAnimatedPack,
      );
      if (issue != null) {
        stickerIssues.add(issue);
      } else {
        validStickerData.add(item);
      }
    }

    return PreFlightValidationReport(
      totalStickers: stickerData.length,
      isAnimatedPack: isAnimatedPack,
      packErrors: packErrors,
      stickerIssues: stickerIssues,
      validStickerData: validStickerData,
    );
  }

  Future<void> _validateTrayIcon(
    String trayPath,
    List<String> packErrors,
  ) async {
    if (trayPath.trim().isEmpty) {
      packErrors.add('Tepsi simgesi (tray icon) yolu boş.');
      return;
    }
    final trayFile = File(trayPath);
    if (!await trayFile.exists()) {
      packErrors.add('Tepsi simgesi (tray icon) dosyası bulunamadı.');
      return;
    }

    final bytes = await trayFile.readAsBytes();
    if (bytes.isEmpty) {
      packErrors.add('Tepsi simgesi dosyası boş (0 bayt).');
      return;
    }
    if (bytes.length > trayByteLimit) {
      final kb = (bytes.length / 1024).toStringAsFixed(1);
      final limitKb = (trayByteLimit / 1024).toStringAsFixed(0);
      packErrors.add(
        'Tepsi simgesi boyutu ($kb KB) WhatsApp $limitKb KB sınırını aşıyor.',
      );
    }

    final pngDims = _readPngDimensions(bytes);
    if (pngDims == null) {
      packErrors.add('Tepsi simgesi geçerli bir PNG dosyası değil.');
    } else if (pngDims.width != requiredTrayDimension ||
        pngDims.height != requiredTrayDimension) {
      packErrors.add(
        'Tepsi simgesi boyutu ${pngDims.width}×${pngDims.height}px; '
        'WhatsApp $requiredTrayDimension×$requiredTrayDimension px gerektirir.',
      );
    }
  }

  Future<StickerValidationIssue?> _validateSingleSticker({
    required int index,
    required Map<String, dynamic> item,
    required bool isAnimatedPack,
  }) async {
    final path = (item['path'] as String?) ?? '';
    final issues = <PreFlightIssueType>[];
    final reasons = <String>[];

    _checkEmojiCompliance(item['emojis'], issues, reasons);

    if (path.isEmpty) {
      issues.add(PreFlightIssueType.missingFile);
      reasons.add('Çıkartma dosya yolu belirtilmemiş.');
      return StickerValidationIssue(
        stickerIndex: index,
        path: path,
        issues: issues,
        reasons: reasons,
      );
    }

    final file = File(path);
    if (!await file.exists()) {
      issues.add(PreFlightIssueType.missingFile);
      reasons.add('Dosya diskte bulunamadı.');
      return StickerValidationIssue(
        stickerIndex: index,
        path: path,
        issues: issues,
        reasons: reasons,
      );
    }

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      issues.add(PreFlightIssueType.emptyFile);
      reasons.add('Dosya boş (0 bayt).');
      return StickerValidationIssue(
        stickerIndex: index,
        path: path,
        issues: issues,
        reasons: reasons,
        fileSizeBytes: 0,
      );
    }

    final maxBytes = isAnimatedPack ? animatedByteLimit : staticByteLimit;
    if (bytes.length > maxBytes) {
      final actualKb = (bytes.length / 1024).toStringAsFixed(1);
      final limitKb = (maxBytes / 1024).toStringAsFixed(0);
      issues.add(PreFlightIssueType.oversizedFile);
      reasons.add('Dosya boyutu ($actualKb KB) $limitKb KB sınırını aşıyor.');
    }

    final meta = WebpInspector.inspectBytes(bytes);
    if (meta == null) {
      issues.add(PreFlightIssueType.invalidWebpHeader);
      reasons.add('Geçerli bir RIFF/WebP konteyneri değil.');
      return StickerValidationIssue(
        stickerIndex: index,
        path: path,
        issues: issues,
        reasons: reasons,
        fileSizeBytes: bytes.length,
      );
    }

    if (meta.width != requiredDimension || meta.height != requiredDimension) {
      issues.add(PreFlightIssueType.invalidDimensions);
      reasons.add(
        'Çözünürlük ${meta.width}×${meta.height}px; '
        '$requiredDimension×$requiredDimension px olmalı.',
      );
    }

    if (isAnimatedPack) {
      if (!meta.isAnimated || meta.frameCount < 2) {
        issues.add(PreFlightIssueType.invalidFrameCount);
        reasons.add(
          'Hareketli paket çıkartması en az 2 kare içermeli '
          '(bulunan: ${meta.frameCount}).',
        );
      }
      if (meta.totalDurationMs <= 0 || meta.totalDurationMs > durationLimitMs) {
        issues.add(PreFlightIssueType.exceedsMaxDuration);
        reasons.add(
          'Animasyon süresi (${meta.totalDurationMs} ms) 1–$durationLimitMs ms '
          'aralığında olmalı.',
        );
      }
    }

    if (issues.isEmpty) return null;

    final canRecompress = issues.any(
      (issue) =>
          issue == PreFlightIssueType.oversizedFile ||
          issue == PreFlightIssueType.invalidDimensions ||
          issue == PreFlightIssueType.exceedsMaxDuration ||
          issue == PreFlightIssueType.invalidFrameCount,
    );

    return StickerValidationIssue(
      stickerIndex: index,
      path: path,
      issues: issues,
      reasons: reasons,
      fileSizeBytes: bytes.length,
      width: meta.width,
      height: meta.height,
      frameCount: meta.frameCount,
      durationMs: meta.totalDurationMs,
      canFixByRecompress: canRecompress,
    );
  }

  void _checkEmojiCompliance(
    dynamic rawEmojis,
    List<PreFlightIssueType> issues,
    List<String> reasons,
  ) {
    final list = <String>[];
    if (rawEmojis is List) {
      for (final e in rawEmojis) {
        if (e != null && e.toString().trim().isNotEmpty) {
          list.add(e.toString().trim());
        }
      }
    } else if (rawEmojis is String && rawEmojis.trim().isNotEmpty) {
      list.add(rawEmojis.trim());
    }

    if (list.isEmpty || list.length > 3) {
      issues.add(PreFlightIssueType.invalidEmojis);
      reasons.add(
        'Her çıkartmada 1–3 adet geçerli emoji bulunmalı (bulunan: ${list.length}).',
      );
      return;
    }

    // Verify each entry actually carries valid emoji characters.
    for (final entry in list) {
      final sanitized = WhatsAppService.sanitizeEmojis(entry);
      if (sanitized.isEmpty || (sanitized.length == 1 && sanitized.first == '⭐' && entry != '⭐')) {
        issues.add(PreFlightIssueType.invalidEmojis);
        reasons.add('Geçersiz emoji biçimi: "$entry".');
        return;
      }
    }
  }

  static ({int width, int height})? _readPngDimensions(Uint8List bytes) {
    if (bytes.length < 24) return null;
    const pngSig = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    for (int i = 0; i < pngSig.length; i++) {
      if (bytes[i] != pngSig[i]) return null;
    }
    final width =
        (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
    final height =
        (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
    if (width <= 0 || height <= 0) return null;
    return (width: width, height: height);
  }
}
