import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../widgets/gradient_button.dart';
import '../widgets/glass_card.dart';
import '../widgets/bot_token_guide_sheet.dart';
import '../services/telegram_service.dart';
import '../services/storage_service.dart';
import 'pack_preview_screen.dart';

/// Home screen – primary sticker pack import screen with direct link processing,
/// recent searches, theme toggle, and bot token guide.
class HomeScreen extends StatefulWidget {
  final VoidCallback? onNavigateToSettings;

  const HomeScreen({super.key, this.onNavigateToSettings});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  final _linkController = TextEditingController();
  final _telegramService = TelegramService();
  final _storageService = StorageService();

  bool _isLoading = false;
  String? _errorMessage;
  List<String> _recentPacks = [];

  @override
  void initState() {
    super.initState();
    _initStorage();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkTokenState();
  }

  void _checkTokenState() {
    if (mounted) setState(() {});
  }

  Future<void> _initStorage() async {
    await _storageService.init();
    final savedToken = _storageService.getBotToken();
    if (savedToken != null && savedToken.isNotEmpty) {
      _telegramService.setBotToken(savedToken);
    }
    _loadRecents();
  }

  void _loadRecents() {
    if (mounted) {
      setState(() {
        _recentPacks = _storageService.getRecentPacks();
      });
    }
  }

  /// Called externally when a link is shared into the app via Android Intent.
  void handleSharedText(String text) {
    _linkController.text = text;
    _fetchStickerPack();
  }

  Future<void> _fetchStickerPack([String? directSetName]) async {
    final input = directSetName ?? _linkController.text.trim();
    if (input.isEmpty) {
      setState(() => _errorMessage = 'Lütfen bir bağlantı veya paket adı girin.');
      return;
    }

    final setName = TelegramService.extractSetName(input);
    if (setName == null) {
      setState(() => _errorMessage =
          'Geçerli bir Telegram çıkartma bağlantısı girin.\n'
          'Örnek: https://t.me/addstickers/PaketAdi');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final stickerSet = await _telegramService.getStickerSet(setName);

      // Save to recent searches
      await _storageService.addRecentPack(setName);
      _loadRecents();

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PackPreviewScreen(
            stickerSet: stickerSet,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString().replaceAll('Exception: ', '').trim();
      setState(() {
        if (raw.toLowerCase().contains('unauthorized')) {
          _errorMessage =
              'Telegram Bot Token geçersiz veya yetkilendirilmedi.\n'
              'Lütfen yukarıdaki rehberden kendi botunuzu ekleyin.';
        } else if (raw.toLowerCase().contains('not found')) {
          _errorMessage =
              'Çıkartma paketi bulunamadı. Bağlantıyı kontrol edin.';
        } else {
          _errorMessage = raw;
        }
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      _linkController.text = data.text!.trim();
      setState(() => _errorMessage = null);
    }
  }

  void _openBotTokenGuide() {
    BotTokenGuideSheet.show(
      context,
      storageService: _storageService,
      onTokenSaved: () {
        setState(() {});
      },
    );
  }

  @override
  void dispose() {
    _linkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final textCol = AppTheme.getText(context);
    final secCol = AppTheme.getTextSec(context);
    final mutCol = AppTheme.getTextMut(context);
    final surfaceMuted = AppTheme.getSurfaceMuted(context);

    return Scaffold(
      backgroundColor: AppTheme.getBackground(context),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),

              // ─── Top Bar with Actions ──────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Bot Token Guide button
                  IconButton(
                    onPressed: _openBotTokenGuide,
                    icon: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryBlue.withAlpha(isDark ? 40 : 25),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.help_outline_rounded,
                        color: AppTheme.primaryBlue,
                        size: 20,
                      ),
                    ),
                    tooltip: 'Bot Token Rehberi',
                  ),
                  const SizedBox(width: 4),
                  // Theme Toggle Button (Light / Dark)
                  IconButton(
                    onPressed: () =>
                        ThemeController.instance.toggleTheme(_storageService),
                    icon: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1E293B)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Icon(
                        isDark
                            ? Icons.wb_sunny_rounded
                            : Icons.nightlight_round,
                        color: isDark ? Colors.amber : const Color(0xFF1E293B),
                        size: 20,
                      ),
                    ),
                    tooltip: isDark ? 'Açık Temaya Geç' : 'Koyu Temaya Geç',
                  ),
                ],
              ),

              // ─── Header Branding ───────────────────────────
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryBlue,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.swap_horiz_rounded,
                        size: 36,
                        color: Colors.white,
                      ),
                    )
                        .animate()
                        .fadeIn(duration: 500.ms)
                        .scale(
                          begin: const Offset(0.85, 0.85),
                          duration: 500.ms,
                          curve: Curves.easeOutBack,
                        ),
                    const SizedBox(height: 14),
                    Text(
                      'StickerSwap',
                      style: Theme.of(context).textTheme.displayLarge?.copyWith(
                            color: textCol,
                          ),
                    )
                        .animate()
                        .fadeIn(delay: 150.ms, duration: 400.ms)
                        .slideY(begin: 0.15),
                    const SizedBox(height: 4),
                    Text(
                      'Telegram → WhatsApp çıkartma aktarıcı',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: secCol,
                          ),
                    )
                        .animate()
                        .fadeIn(delay: 250.ms, duration: 400.ms),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ─── Bot Token Missing Banner ─────────────────
              if (!_telegramService.hasToken)
                InkWell(
                  onTap: _openBotTokenGuide,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.warning.withAlpha(isDark ? 20 : 30),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppTheme.warning.withAlpha(isDark ? 70 : 90),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.warning.withAlpha(35),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.vpn_key_rounded,
                            color: AppTheme.warning,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Telegram Bot Token Gerekli',
                                style: TextStyle(
                                  color: textCol,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Rehbere dokunarak 1 dakikada ücretsiz botunuzu bağlayın.',
                                style: TextStyle(
                                  color: secCol,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: _openBotTokenGuide,
                          style: TextButton.styleFrom(
                            backgroundColor: AppTheme.warning.withAlpha(35),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            'Rehber',
                            style: TextStyle(
                              color: AppTheme.warning,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1),

              // ─── Link Input Card ──────────────────────────
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryBlue.withAlpha(isDark ? 35 : 25),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.link_rounded,
                            color: AppTheme.primaryBlue,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Çıkartma Paketi Bağlantısı',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: textCol,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      decoration: BoxDecoration(
                        color: isDark ? AppTheme.backgroundDark : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _errorMessage != null
                              ? AppTheme.error.withAlpha(120)
                              : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _linkController,
                              style: TextStyle(
                                color: textCol,
                                fontSize: 14,
                              ),
                              decoration: InputDecoration(
                                hintText: 'https://t.me/addstickers/PaketAdi',
                                hintStyle: TextStyle(
                                  color: mutCol.withAlpha(140),
                                  fontSize: 13,
                                ),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                              ),
                              onSubmitted: (_) => _fetchStickerPack(),
                            ),
                          ),
                          if (_linkController.text.isNotEmpty)
                            IconButton(
                              onPressed: () {
                                _linkController.clear();
                                setState(() => _errorMessage = null);
                              },
                              icon: Icon(
                                Icons.clear_rounded,
                                size: 18,
                                color: mutCol,
                              ),
                              tooltip: 'Temizle',
                            ),
                          IconButton(
                            onPressed: _pasteFromClipboard,
                            icon: const Icon(
                              Icons.content_paste_rounded,
                              size: 18,
                              color: AppTheme.primaryBlue,
                            ),
                            tooltip: 'Yapıştır',
                          ),
                        ],
                      ),
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            size: 16,
                            color: AppTheme.error,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(
                                color: AppTheme.error,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    GradientButton(
                      text: 'Paketi Getir',
                      icon: Icons.download_rounded,
                      isLoading: _isLoading,
                      onPressed: () => _fetchStickerPack(),
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 300.ms, duration: 400.ms),

              // ─── Recent Searches Chips ─────────────────────
              if (_recentPacks.isNotEmpty) ...[
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.history_rounded,
                          size: 16,
                          color: mutCol,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Son Arananlar',
                          style: TextStyle(
                            color: secCol,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    TextButton(
                      onPressed: () async {
                        await _storageService.clearRecentPacks();
                        _loadRecents();
                      },
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(50, 24),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        'Temizle',
                        style: TextStyle(
                          color: mutCol,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _recentPacks.map((name) {
                    return InkWell(
                      onTap: () {
                        _linkController.text = name;
                        _fetchStickerPack(name);
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: surfaceMuted,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.north_west_rounded,
                              size: 12,
                              color: AppTheme.primaryBlue,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              name,
                              style: TextStyle(
                                color: secCol,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ).animate().fadeIn(duration: 400.ms),
              ],

              const SizedBox(height: 24),

              // ─── Bot Token Guide Card ─────────────────────
              GlassCard(
                onTap: _openBotTokenGuide,
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryBlue,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.auto_awesome_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Telegram Bot Token Rehberi',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: textCol,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Kendi ücretsiz botunuz ile sınırsız çıkartma aktarın.',
                            style: TextStyle(
                              fontSize: 12,
                              color: secCol,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryBlue.withAlpha(isDark ? 30 : 20),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 12,
                        color: AppTheme.primaryBlue,
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 350.ms),

              const SizedBox(height: 28),

              // ─── How It Works Guide ───────────────────────
              Row(
                children: [
                  const Icon(
                    Icons.help_outline_rounded,
                    size: 18,
                    color: AppTheme.primaryBlue,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Nasıl Çalışır?',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: textCol,
                    ),
                  ),
                ],
              ).animate().fadeIn(delay: 400.ms),
              const SizedBox(height: 12),
              _FeatureTile(
                icon: Icons.link_rounded,
                title: 'Bağlantı Yapıştır',
                subtitle: 'Telegram çıkartma bağlantısını girin veya yapıştırın',
                color: AppTheme.primaryBlue,
                delay: 450,
              ),
              const SizedBox(height: 10),
              _FeatureTile(
                icon: Icons.checklist_rounded,
                title: 'Önizle & Seç',
                subtitle: 'Hareketli ve statik çıkartmaları canlı izleyip seçin',
                color: AppTheme.lightBlue,
                delay: 500,
              ),
              const SizedBox(height: 10),
              _FeatureTile(
                icon: Icons.auto_fix_high_rounded,
                title: 'Otomatik WhatsApp Dönüşümü',
                subtitle: '512×512 WebP kanvası ve hareketli WebP oluşturulur',
                color: AppTheme.primaryBlue,
                delay: 550,
              ),
              const SizedBox(height: 10),
              _FeatureTile(
                icon: Icons.send_rounded,
                title: 'WhatsApp\'a Aktar',
                subtitle: 'Tek dokunuşla paketi WhatsApp tepsisine ekleyin!',
                color: AppTheme.whatsappGreen,
                delay: 600,
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final int delay;

  const _FeatureTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final textCol = AppTheme.getText(context);
    final secCol = AppTheme.getTextSec(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.cardDark : AppTheme.cardLight,
        borderRadius: AppTheme.cardRadius,
        border: AppTheme.getBorder(context),
        boxShadow: isDark ? null : AppTheme.lightCardShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withAlpha(isDark ? 30 : 20),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: textCol,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: secCol,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.arrow_forward_ios_rounded,
            color: color.withAlpha(120),
            size: 14,
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(delay: Duration(milliseconds: delay), duration: 350.ms)
        .slideX(begin: 0.04);
  }
}
