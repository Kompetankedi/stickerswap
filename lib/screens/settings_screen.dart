import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../services/telegram_service.dart';
import '../services/storage_service.dart';
import '../services/whatsapp_service.dart';
import '../widgets/glass_card.dart';
import '../widgets/gradient_button.dart';
import '../widgets/bot_token_guide_sheet.dart';

/// Settings screen – theme selection, bot token management, publisher name,
/// WhatsApp status, and cache cleanup.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _telegramService = TelegramService();
  final _storageService = StorageService();
  final _whatsappService = WhatsAppService();

  final _tokenController = TextEditingController();
  final _publisherController = TextEditingController();

  bool _isTestingToken = false;
  String? _tokenTestResult;
  bool _tokenValid = false;

  bool? _isWhatsAppInstalled;
  int _cacheSizeBytes = 0;
  bool _isClearingCache = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _checkWhatsAppStatus();
    _calcCacheSize();
  }

  Future<void> _loadSettings() async {
    await _storageService.init();
    final savedToken = _storageService.getBotToken();
    if (savedToken != null) {
      _tokenController.text = savedToken;
      _telegramService.setBotToken(savedToken);
    }
    _publisherController.text = _storageService.getPublisherName();
    if (mounted) setState(() {});
  }

  Future<void> _checkWhatsAppStatus() async {
    try {
      final installed = await _whatsappService.isWhatsAppInstalled();
      if (mounted) {
        setState(() => _isWhatsAppInstalled = installed);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isWhatsAppInstalled = null);
      }
    }
  }

  Future<void> _calcCacheSize() async {
    final size = await _storageService.getCacheSizeBytes();
    if (mounted) {
      setState(() => _cacheSizeBytes = size);
    }
  }

  Future<void> _testToken() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      setState(() {
        _tokenTestResult = 'Lütfen bir token girin.';
        _tokenValid = false;
      });
      return;
    }

    setState(() {
      _isTestingToken = true;
      _tokenTestResult = null;
    });

    final stopwatch = Stopwatch()..start();
    _telegramService.setBotToken(token);
    final result = await _telegramService.validateToken();
    stopwatch.stop();

    if (mounted) {
      setState(() {
        _isTestingToken = false;
        _tokenValid = result['ok'] == true;
        if (_tokenValid) {
          _tokenTestResult =
              '✅ Bağlantı başarılı (${stopwatch.elapsedMilliseconds} ms)\nBot: @${result['username']}';
          _storageService.setBotToken(token);
        } else {
          _tokenTestResult = '❌ Token geçersiz veya bot yanıt vermiyor.';
        }
      });
    }
  }

  Future<void> _resetToken() async {
    _telegramService.clearToken();
    await _storageService.clearBotToken();
    _tokenController.clear();
    setState(() {
      _tokenTestResult = null;
      _tokenValid = false;
    });
  }

  Future<void> _savePublisher() async {
    final name = _publisherController.text.trim();
    if (name.isNotEmpty) {
      await _storageService.setPublisherName(name);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Yayıncı adı kaydedildi.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _clearCache() async {
    setState(() => _isClearingCache = true);
    await _storageService.clearCache();
    await _calcCacheSize();
    if (mounted) {
      setState(() => _isClearingCache = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Önbellek temizlendi.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _openBotTokenGuide() {
    BotTokenGuideSheet.show(
      context,
      storageService: _storageService,
      onTokenSaved: () {
        _loadSettings();
      },
    );
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _publisherController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final textCol = AppTheme.getText(context);
    final secCol = AppTheme.getTextSec(context);
    final mutCol = AppTheme.getTextMut(context);
    final inputBg = isDark ? AppTheme.backgroundDark : const Color(0xFFF1F5F9);
    final borderCol = isDark ? Colors.white.withAlpha(15) : const Color(0xFFCBD5E1);

    return Scaffold(
      backgroundColor: AppTheme.getBackground(context),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),

              // ─── Header ─────────────────────────────────
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: AppTheme.primaryGradient,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.settings_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    'Ayarlar',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: textCol,
                    ),
                  ),
                ],
              )
                  .animate()
                  .fadeIn(duration: 400.ms)
                  .slideX(begin: -0.04),

              const SizedBox(height: 24),

              // ─── Theme Selection Section ──────────────────
              _SectionTitle(
                icon: Icons.palette_outlined,
                title: 'Uygulama Teması',
                color: AppTheme.primaryBlue,
              ).animate().fadeIn(delay: 100.ms),
              const SizedBox(height: 10),
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Gözü yormayan, sade ve modern 2 tema seçeneği:',
                      style: TextStyle(
                        color: secCol,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        // Dark theme button
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              ThemeController.instance
                                  .setTheme(ThemeMode.dark, _storageService);
                            },
                            borderRadius: BorderRadius.circular(14),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFF090D16),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isDark
                                      ? AppTheme.primaryBlue
                                      : Colors.white.withAlpha(20),
                                  width: isDark ? 2 : 1,
                                ),
                                boxShadow: isDark
                                    ? AppTheme.glowShadow(AppTheme.primaryBlue, blur: 12)
                                    : null,
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        Icons.nightlight_round,
                                        size: 16,
                                        color: AppTheme.lightBlue,
                                      ),
                                      const SizedBox(width: 6),
                                      const Text(
                                        'Koyu Tema',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Siyah / Mavi',
                                    style: TextStyle(
                                      color: Color(0xFF94A3B8),
                                      fontSize: 11,
                                    ),
                                  ),
                                  if (isDark) ...[
                                    const SizedBox(height: 6),
                                    const Icon(
                                      Icons.check_circle_rounded,
                                      color: AppTheme.primaryBlue,
                                      size: 16,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Light theme button
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              ThemeController.instance
                                  .setTheme(ThemeMode.light, _storageService);
                            },
                            borderRadius: BorderRadius.circular(14),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: !isDark
                                      ? AppTheme.primaryBlue
                                      : const Color(0xFFCBD5E1),
                                  width: !isDark ? 2 : 1,
                                ),
                                boxShadow: !isDark
                                    ? [
                                        BoxShadow(
                                          color: AppTheme.primaryBlue.withAlpha(40),
                                          blurRadius: 12,
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        Icons.wb_sunny_rounded,
                                        size: 16,
                                        color: AppTheme.primaryBlue,
                                      ),
                                      const SizedBox(width: 6),
                                      const Text(
                                        'Açık Tema',
                                        style: TextStyle(
                                          color: Color(0xFF0F172A),
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Beyaz / Mavi',
                                    style: TextStyle(
                                      color: Color(0xFF475569),
                                      fontSize: 11,
                                    ),
                                  ),
                                  if (!isDark) ...[
                                    const SizedBox(height: 6),
                                    const Icon(
                                      Icons.check_circle_rounded,
                                      color: AppTheme.primaryBlue,
                                      size: 16,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 150.ms),

              const SizedBox(height: 24),

              // ─── WhatsApp Status ──────────────────────────
              _SectionTitle(
                icon: Icons.check_circle_outline_rounded,
                title: 'WhatsApp Durumu',
                color: AppTheme.whatsappGreen,
              ).animate().fadeIn(delay: 200.ms),
              const SizedBox(height: 10),
              GlassCard(
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppTheme.whatsappGreen.withAlpha(25),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.chat_rounded,
                        color: AppTheme.whatsappGreen,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'WhatsApp Entegrasyonu',
                            style: TextStyle(
                              color: textCol,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _isWhatsAppInstalled == true
                                ? 'WhatsApp cihazınızda yüklü ve hazır'
                                : _isWhatsAppInstalled == false
                                    ? 'WhatsApp bulunamadı'
                                    : 'Durum kontrol ediliyor...',
                            style: TextStyle(
                              color: _isWhatsAppInstalled == true
                                  ? AppTheme.success
                                  : mutCol,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isWhatsAppInstalled == true
                            ? AppTheme.success
                            : AppTheme.warning,
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 250.ms),

              const SizedBox(height: 24),

              // ─── Bot Token Section ────────────────────────
              _SectionTitle(
                icon: Icons.smart_toy_rounded,
                title: 'Telegram Bot Yapılandırması',
                color: AppTheme.primaryBlue,
              ).animate().fadeIn(delay: 300.ms),
              const SizedBox(height: 10),
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Kendi ücretsiz Telegram botunuzu kullanarak çıkartmaları sınırsızca indirin.',
                      style: TextStyle(
                        color: secCol,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      decoration: BoxDecoration(
                        color: inputBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _tokenValid
                              ? AppTheme.success.withAlpha(100)
                              : borderCol,
                        ),
                      ),
                      child: TextField(
                        controller: _tokenController,
                        style: TextStyle(
                          color: textCol,
                          fontSize: 13,
                          fontFamily: 'monospace',
                        ),
                        decoration: InputDecoration(
                          hintText: '123456789:ABCdefGhIJK...',
                          hintStyle: TextStyle(
                            color: mutCol.withAlpha(120),
                            fontSize: 13,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          suffixIcon: _tokenController.text.isNotEmpty
                              ? IconButton(
                                  onPressed: _resetToken,
                                  icon: Icon(
                                    Icons.clear_rounded,
                                    size: 18,
                                    color: mutCol,
                                  ),
                                )
                              : null,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    if (_tokenTestResult != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _tokenValid
                              ? AppTheme.success.withAlpha(20)
                              : AppTheme.error.withAlpha(20),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _tokenValid
                                ? AppTheme.success.withAlpha(50)
                                : AppTheme.error.withAlpha(50),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _tokenValid
                                  ? Icons.check_circle_rounded
                                  : Icons.error_outline_rounded,
                              color: _tokenValid
                                  ? AppTheme.success
                                  : AppTheme.error,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _tokenTestResult!,
                                style: TextStyle(
                                  color: _tokenValid
                                      ? AppTheme.success
                                      : AppTheme.error,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: GradientButton(
                            text: 'Test Et & Kaydet',
                            icon: Icons.wifi_tethering_rounded,
                            height: 44,
                            gradient: AppTheme.primaryGradient,
                            isLoading: _isTestingToken,
                            onPressed: _isTestingToken ? null : _testToken,
                          ),
                        ),
                        const SizedBox(width: 10),
                        InkWell(
                          onTap: _openBotTokenGuide,
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            height: 44,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              color: isDark ? AppTheme.surfaceDarkElevated : const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: AppTheme.primaryBlue.withAlpha(40),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.menu_book_rounded,
                                  color: AppTheme.primaryBlue,
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                const Text(
                                  'Rehber',
                                  style: TextStyle(
                                    color: AppTheme.primaryBlue,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 350.ms),

              const SizedBox(height: 24),

              // ─── Publisher Section ─────────────────────────
              _SectionTitle(
                icon: Icons.person_rounded,
                title: 'WhatsApp Yayıncı Adı',
                color: AppTheme.lightBlue,
              ).animate().fadeIn(delay: 400.ms),
              const SizedBox(height: 10),
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'WhatsApp çıkartma tepsisinde görünecek yazar adı.',
                      style: TextStyle(
                        color: secCol,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: inputBg,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: borderCol),
                            ),
                            child: TextField(
                              controller: _publisherController,
                              style: TextStyle(
                                color: textCol,
                                fontSize: 14,
                              ),
                              decoration: InputDecoration(
                                hintText: 'StickerSwap',
                                hintStyle: TextStyle(
                                  color: mutCol.withAlpha(120),
                                  fontSize: 14,
                                ),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        InkWell(
                          onTap: _savePublisher,
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            height: 48,
                            width: 48,
                            decoration: BoxDecoration(
                              gradient: AppTheme.primaryGradient,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.save_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 450.ms),

              const SizedBox(height: 24),

              // ─── Storage & Cache Management ───────────────
              _SectionTitle(
                icon: Icons.cleaning_services_rounded,
                title: 'Depolama & Önbellek',
                color: AppTheme.cyanBlue,
              ).animate().fadeIn(delay: 500.ms),
              const SizedBox(height: 10),
              GlassCard(
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppTheme.cyanBlue.withAlpha(25),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.storage_rounded,
                        color: AppTheme.cyanBlue,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Geçici Çıkartma Dosyaları',
                            style: TextStyle(
                              color: textCol,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            StorageService.formatBytes(_cacheSizeBytes),
                            style: TextStyle(
                              color: mutCol,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton(
                      onPressed: _isClearingCache || _cacheSizeBytes == 0
                          ? null
                          : _clearCache,
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: AppTheme.cyanBlue.withAlpha(120),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isClearingCache
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.cyanBlue,
                              ),
                            )
                          : const Text(
                              'Temizle',
                              style: TextStyle(
                                color: AppTheme.cyanBlue,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 550.ms),

              const SizedBox(height: 24),

              // ─── About Section ────────────────────────────
              _SectionTitle(
                icon: Icons.info_outline_rounded,
                title: 'Hakkında',
                color: AppTheme.primaryBlue,
              ).animate().fadeIn(delay: 600.ms),
              const SizedBox(height: 10),
              GlassCard(
                child: Column(
                  children: [
                    _AboutRow(label: 'Uygulama', value: 'StickerSwap', textCol: textCol, secCol: secCol),
                    Divider(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0), height: 20),
                    _AboutRow(label: 'Sürüm', value: '1.0.0+1', textCol: textCol, secCol: secCol),
                    Divider(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0), height: 20),
                    _AboutRow(label: 'Platform', value: 'Android (Flutter)', textCol: textCol, secCol: secCol),
                    Divider(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0), height: 20),
                    Row(
                      children: [
                        const Icon(
                          Icons.security_rounded,
                          size: 16,
                          color: AppTheme.success,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Resmi WhatsApp Çıkartma API ve Telegram Bot API standartlarına %100 uygundur.',
                            style: TextStyle(
                              color: secCol,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 650.ms),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;

  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

class _AboutRow extends StatelessWidget {
  final String label;
  final String value;
  final Color textCol;
  final Color secCol;

  const _AboutRow({
    required this.label,
    required this.value,
    required this.textCol,
    required this.secCol,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: secCol,
            fontSize: 13,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: textCol,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
