/// Represents a curated or trending sticker pack recommendation.
class CuratedPack {
  final String name;
  final String title;
  final String category;
  final String iconEmoji;
  final String previewStickerName;
  final String tag;
  final int estimatedCount;

  const CuratedPack({
    required this.name,
    required this.title,
    required this.category,
    required this.iconEmoji,
    required this.previewStickerName,
    required this.tag,
    this.estimatedCount = 30,
  });

  static const List<CuratedPack> popularPacks = [
    // Trendler & Memeler
    CuratedPack(
      name: 'PepeTheKing',
      title: 'Pepe The Frog',
      category: 'Memeler',
      iconEmoji: '🐸',
      previewStickerName: 'Pepe',
      tag: '🔥 Çok Popüler',
      estimatedCount: 50,
    ),
    CuratedPack(
      name: 'DogeMemePack',
      title: 'Doge & Cheems',
      category: 'Memeler',
      iconEmoji: '🐕',
      previewStickerName: 'Doge',
      tag: '⭐ Klasik',
      estimatedCount: 40,
    ),
    CuratedPack(
      name: 'TurkishMemesPack',
      title: 'Türkçe Komik Tepkiler',
      category: 'Memeler',
      iconEmoji: '🇹🇷',
      previewStickerName: 'TR',
      tag: '🔥 Trend',
      estimatedCount: 35,
    ),
    CuratedPack(
      name: 'CatMemesTelegram',
      title: 'Komik Kediler & Caps',
      category: 'Sevimli',
      iconEmoji: '🐱',
      previewStickerName: 'Cat',
      tag: '❤️ Sevilen',
      estimatedCount: 45,
    ),
    // Sevimli & Hayvanlar
    CuratedPack(
      name: 'BrownAndFriends',
      title: 'Brown & Cony',
      category: 'Sevimli',
      iconEmoji: '🐻',
      previewStickerName: 'Brown',
      tag: '✨ Klasik',
      estimatedCount: 36,
    ),
    CuratedPack(
      name: 'MeowPack',
      title: 'Miyav Çıkartmaları',
      category: 'Sevimli',
      iconEmoji: '🐾',
      previewStickerName: 'Meow',
      tag: '🐱 Sevimli',
      estimatedCount: 28,
    ),
    CuratedPack(
      name: 'CuteHamsterLife',
      title: 'Tontiş Hamster',
      category: 'Sevimli',
      iconEmoji: '🐹',
      previewStickerName: 'Hamster',
      tag: '💫 Tatlı',
      estimatedCount: 30,
    ),
    // Tepkiler & İfadeler
    CuratedPack(
      name: 'DailyReactionsHQ',
      title: 'Günlük Sohbet Tepkileri',
      category: 'Tepkiler',
      iconEmoji: '💬',
      previewStickerName: 'Reactions',
      tag: '⚡ Popüler',
      estimatedCount: 48,
    ),
    CuratedPack(
      name: 'FacepalmAndSarcasm',
      title: 'İroni & Şaşkınlık',
      category: 'Tepkiler',
      iconEmoji: '🤦‍♂️',
      previewStickerName: 'Facepalm',
      tag: '😂 Eğlenceli',
      estimatedCount: 32,
    ),
    // Oyun & Anime
    CuratedPack(
      name: 'AmongUsStickers',
      title: 'Among Us Karakterleri',
      category: 'Oyun',
      iconEmoji: '🎮',
      previewStickerName: 'AmongUs',
      tag: '👾 Oyun',
      estimatedCount: 30,
    ),
    CuratedPack(
      name: 'PixelGamingRetro',
      title: 'Piksel Retro Oyunlar',
      category: 'Oyun',
      iconEmoji: '🕹️',
      previewStickerName: 'Pixel',
      tag: '✨ Retro',
      estimatedCount: 30,
    ),
    CuratedPack(
      name: 'AnimeChibiReactions',
      title: 'Anime Chibi Emojiler',
      category: 'Oyun',
      iconEmoji: '🍙',
      previewStickerName: 'Anime',
      tag: '🌸 Anime',
      estimatedCount: 40,
    ),
  ];

  static List<String> get categories => [
        'Tümü',
        'Memeler',
        'Sevimli',
        'Tepkiler',
        'Oyun',
      ];
}
