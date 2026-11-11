import 'dart:io';
import 'dart:typed_data';

/// Lightweight WebP container metadata parsed from RIFF/VP8X/ANIM/ANMF chunks.
class WebpAnimationMetadata {
  final int width;
  final int height;
  final int frameCount;
  final int totalDurationMs;
  final int loopCount;
  final int fileSizeBytes;
  final bool isAnimated;
  final bool hasAlpha;

  const WebpAnimationMetadata({
    required this.width,
    required this.height,
    required this.frameCount,
    required this.totalDurationMs,
    required this.loopCount,
    required this.fileSizeBytes,
    required this.isAnimated,
    required this.hasAlpha,
  });

  double get fileSizeKb => fileSizeBytes / 1024.0;
  double get durationSeconds => totalDurationMs / 1000.0;
}

/// Inspects WebP container headers without decoding full pixel buffers.
class WebpInspector {
  /// Parses RIFF/WEBP chunk headers from [bytes], returning null if invalid.
  static WebpAnimationMetadata? inspectBytes(Uint8List bytes) {
    if (bytes.length < 12) return null;
    if (!_matchesAscii(bytes, 0, 'RIFF') || !_matchesAscii(bytes, 8, 'WEBP')) {
      return null;
    }

    int width = 0;
    int height = 0;
    int frameCount = 0;
    int totalDurationMs = 0;
    int loopCount = 0;
    bool isAnimated = false;
    bool hasAlpha = false;

    int offset = 12;
    while (offset + 8 <= bytes.length) {
      final fourcc = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final chunkSize = _readUint32LE(bytes, offset + 4);
      final payload = offset + 8;
      if (chunkSize < 0 || payload + chunkSize > bytes.length) {
        break;
      }

      if (fourcc == 'VP8X' && chunkSize >= 10) {
        final flags = bytes[payload];
        hasAlpha = (flags & 0x10) != 0;
        isAnimated = (flags & 0x02) != 0;
        width = 1 + _readUint24LE(bytes, payload + 4);
        height = 1 + _readUint24LE(bytes, payload + 7);
      } else if (fourcc == 'ANIM' && chunkSize >= 6) {
        loopCount = bytes[payload + 4] | (bytes[payload + 5] << 8);
        isAnimated = true;
      } else if (fourcc == 'ANMF' && chunkSize >= 16) {
        final frameDurationMs = _readUint24LE(bytes, payload + 12);
        frameCount++;
        totalDurationMs += frameDurationMs;
        isAnimated = true;
      } else if (fourcc == 'VP8 ' && chunkSize >= 10 && width == 0) {
        if (bytes[payload + 3] == 0x9D &&
            bytes[payload + 4] == 0x01 &&
            bytes[payload + 5] == 0x2A) {
          width = (bytes[payload + 6] | (bytes[payload + 7] << 8)) & 0x3FFF;
          height = (bytes[payload + 8] | (bytes[payload + 9] << 8)) & 0x3FFF;
        }
      } else if (fourcc == 'VP8L' && chunkSize >= 5 && width == 0) {
        if (bytes[payload] == 0x2F) {
          final bits = _readUint32LE(bytes, payload + 1);
          width = 1 + (bits & 0x3FFF);
          height = 1 + ((bits >> 14) & 0x3FFF);
          hasAlpha = ((bits >> 28) & 1) != 0;
        }
      }

      offset = payload + chunkSize + (chunkSize & 1);
    }

    if (width <= 0 || height <= 0) {
      return null;
    }
    if (!isAnimated && frameCount == 0) {
      frameCount = 1;
    }

    return WebpAnimationMetadata(
      width: width,
      height: height,
      frameCount: frameCount,
      totalDurationMs: totalDurationMs,
      loopCount: loopCount,
      fileSizeBytes: bytes.length,
      isAnimated: isAnimated,
      hasAlpha: hasAlpha,
    );
  }

  /// Reads and inspects a WebP file on disk, returning null if missing/invalid.
  static Future<WebpAnimationMetadata?> inspectFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      return inspectBytes(bytes);
    } catch (_) {
      return null;
    }
  }

  static bool _matchesAscii(Uint8List bytes, int offset, String target) {
    if (offset + target.length > bytes.length) return false;
    for (int i = 0; i < target.length; i++) {
      if (bytes[offset + i] != target.codeUnitAt(i)) return false;
    }
    return true;
  }

  static int _readUint24LE(Uint8List bytes, int offset) {
    return bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16);
  }

  static int _readUint32LE(Uint8List bytes, int offset) {
    return bytes[offset] |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24);
  }
}

