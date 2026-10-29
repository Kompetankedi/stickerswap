/// Represents a single sticker within a Telegram sticker set.
class TelegramSticker {
  final String fileId;
  final String fileUniqueId;
  final int width;
  final int height;
  final bool isAnimated;
  final bool isVideo;
  final String emoji;
  final String? thumbFileId;

  /// Local path after download/conversion. Null until processed.
  String? localPath;

  /// Whether the user has selected this sticker for export.
  bool isSelected;

  TelegramSticker({
    required this.fileId,
    required this.fileUniqueId,
    required this.width,
    required this.height,
    this.isAnimated = false,
    this.isVideo = false,
    this.emoji = '⭐',
    this.thumbFileId,
    this.localPath,
    this.isSelected = true,
  });

  factory TelegramSticker.fromJson(Map<String, dynamic> json) {
    String emoji = '⭐';
    if (json['emoji'] != null && json['emoji'].toString().isNotEmpty) {
      emoji = json['emoji'];
    }

    String? thumbId;
    final thumbObj = json['thumbnail'] ?? json['thumb'];
    if (thumbObj is Map) {
      thumbId = thumbObj['file_id'];
    } else if (thumbObj is List && thumbObj.isNotEmpty) {
      final last = thumbObj.last;
      if (last is Map) {
        thumbId = last['file_id'];
      }
    }

    return TelegramSticker(
      fileId: json['file_id'] ?? '',
      fileUniqueId: json['file_unique_id'] ?? '',
      width: json['width'] ?? 512,
      height: json['height'] ?? 512,
      isAnimated: json['is_animated'] ?? false,
      isVideo: json['is_video'] ?? false,
      emoji: emoji,
      thumbFileId: thumbId,
    );
  }
}
