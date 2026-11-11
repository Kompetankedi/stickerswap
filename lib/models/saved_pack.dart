import 'dart:convert';

/// Represents a locally saved WhatsApp sticker pack.
class SavedPack {
  final String identifier;
  final String name;
  final String publisher;
  final String trayImagePath;
  final List<String> stickerPaths;
  final List<String> emojis;
  final int stickerCount;
  final DateTime savedAt;
  final bool isAnimated;
  bool addedToWhatsApp;

  SavedPack({
    required this.identifier,
    required this.name,
    required this.publisher,
    required this.trayImagePath,
    required this.stickerPaths,
    required this.emojis,
    required this.stickerCount,
    required this.savedAt,
    this.isAnimated = false,
    this.addedToWhatsApp = false,
  });

  /// Returns a copy of this pack with any specified metadata fields updated.
  SavedPack copyWith({
    String? identifier,
    String? name,
    String? publisher,
    String? trayImagePath,
    List<String>? stickerPaths,
    List<String>? emojis,
    int? stickerCount,
    DateTime? savedAt,
    bool? isAnimated,
    bool? addedToWhatsApp,
  }) {
    return SavedPack(
      identifier: identifier ?? this.identifier,
      name: name ?? this.name,
      publisher: publisher ?? this.publisher,
      trayImagePath: trayImagePath ?? this.trayImagePath,
      stickerPaths: stickerPaths ?? List<String>.from(this.stickerPaths),
      emojis: emojis ?? List<String>.from(this.emojis),
      stickerCount: stickerCount ?? this.stickerCount,
      savedAt: savedAt ?? this.savedAt,
      isAnimated: isAnimated ?? this.isAnimated,
      addedToWhatsApp: addedToWhatsApp ?? this.addedToWhatsApp,
    );
  }

  Map<String, dynamic> toJson() => {
        'identifier': identifier,
        'name': name,
        'publisher': publisher,
        'trayImagePath': trayImagePath,
        'stickerPaths': stickerPaths,
        'emojis': emojis,
        'stickerCount': stickerCount,
        'savedAt': savedAt.toIso8601String(),
        'isAnimated': isAnimated,
        'addedToWhatsApp': addedToWhatsApp,
      };

  factory SavedPack.fromJson(Map<String, dynamic> json) {
    return SavedPack(
      identifier: json['identifier'] ?? '',
      name: json['name'] ?? '',
      publisher: json['publisher'] ?? '',
      trayImagePath: json['trayImagePath'] ?? '',
      stickerPaths: List<String>.from(json['stickerPaths'] ?? []),
      emojis: List<String>.from(json['emojis'] ?? []),
      stickerCount: json['stickerCount'] ?? 0,
      savedAt: DateTime.tryParse(json['savedAt'] ?? '') ?? DateTime.now(),
      isAnimated: json['isAnimated'] ?? false,
      addedToWhatsApp: json['addedToWhatsApp'] ?? false,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory SavedPack.fromJsonString(String jsonString) =>
      SavedPack.fromJson(jsonDecode(jsonString));
}
