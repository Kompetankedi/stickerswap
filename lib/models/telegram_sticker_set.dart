import 'telegram_sticker.dart';

/// Represents a full Telegram sticker set / pack.
class TelegramStickerSet {
  final String name;
  final String title;
  final String stickerType;
  final List<TelegramSticker> stickers;

  bool get isAnimated => stickers.any((s) => s.isAnimated);
  bool get isVideo => stickers.any((s) => s.isVideo);
  bool get isStatic => !isAnimated && !isVideo;

  String get typeLabel {
    if (isVideo) return 'Video';
    if (isAnimated) return 'Hareketli';
    return 'Statik';
  }

  int get selectedCount => stickers.where((s) => s.isSelected).length;

  TelegramStickerSet({
    required this.name,
    required this.title,
    this.stickerType = 'regular',
    required this.stickers,
  });

  factory TelegramStickerSet.fromJson(Map<String, dynamic> json) {
    final rawStickers = json['stickers'] as List? ?? [];
    return TelegramStickerSet(
      name: json['name'] ?? '',
      title: json['title'] ?? '',
      stickerType: json['sticker_type'] ?? 'regular',
      stickers: rawStickers
          .map((s) => TelegramSticker.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }
}
