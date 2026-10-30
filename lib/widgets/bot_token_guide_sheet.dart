import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../services/storage_service.dart';
import '../services/telegram_service.dart';
import 'gradient_button.dart';

class BotTokenGuideSheet extends StatefulWidget {
  final StorageService storageService;
  final VoidCallback? onTokenSaved;

  const BotTokenGuideSheet({
    super.key,
    required this.storageService,
    this.onTokenSaved,
  });

  static Future<void> show(
    BuildContext context, {
    required StorageService storageService,
    VoidCallback? onTokenSaved,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BotTokenGuideSheet(
        storageService: storageService,
        onTokenSaved: onTokenSaved,
      ),
    );
  }

  @override
  State<BotTokenGuideSheet> createState() => _BotTokenGuideSheetState();
}

class _BotTokenGuideSheetState extends State<BotTokenGuideSheet> {
  final _tokenController = TextEditingController();
  bool _isTesting = false;
  String? _statusMessage;
  bool _isSuccess = false;

  @override
  void initState() {
    super.initState();
    final saved = widget.storageService.getBotToken();
    if (saved != null) {
      _tokenController.text = saved;
    }
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _openBotFather() async {
    final uri = Uri.parse('https://t.me/BotFather');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Telegram açılamadı. @BotFather aratabilirsiniz.'),
          ),
        );
      }
    }
  }

  Future<void> _saveAndTestToken() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      setState(() {
        _statusMessage = 'Lütfen bir token girin.';
        _isSuccess = false;
      });
      return;
    }

    setState(() {
      _isTesting = true;
      _statusMessage = null;
    });

    final res = await TelegramService().validateToken(token);
    final isValid = res['ok'] == true;
    if (!mounted) return;

    if (isValid) {
      await widget.storageService.setBotToken(token);
      TelegramService().setBotToken(token);
      final botUser = res['username'] ?? '';
      setState(() {
        _isTesting = false;
        _isSuccess = true;
        _statusMessage =
            'Harika! @$botUser botu başarıyla doğrulandı ve kaydedildi.';
      });
      widget.onTokenSaved?.call();
    } else {
      setState(() {
        _isTesting = false;
        _isSuccess = false;
        _statusMessage =
            'Geçersiz token. Lütfen BotFather\'dan aldığınız tokenı kontrol edin.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final bgColor = isDark ? AppTheme.surfaceDark : Colors.white;
    final textCol = isDark
        ? AppTheme.textPrimaryDark
        : AppTheme.textPrimaryLight;
    final secCol = isDark
        ? AppTheme.textSecondaryDark
        : AppTheme.textSecondaryLight;
    final stepBg = isDark
        ? AppTheme.surfaceDarkElevated
        : const Color(0xFFEFF6FF);

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          // Drag handle
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withAlpha(isDark ? 50 : 25),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.vpn_key_rounded,
                    color: AppTheme.primaryBlue,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bot Token Alma Rehberi',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: textCol,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '1 dakikada ücretsiz kendi botunuzu kurun',
                        style: TextStyle(fontSize: 13, color: secCol),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close_rounded, color: secCol),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Divider(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),

          // Scrollable Steps
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              children: [
                _buildStep(
                  step: 1,
                  title: "Telegram'da @BotFather'ı Açın",
                  description:
                      'Telegram arama çubuğuna @BotFather yazın veya aşağıdaki butona dokunun.',
                  stepBg: stepBg,
                  textCol: textCol,
                  secCol: secCol,
                  action: ElevatedButton.icon(
                    onPressed: _openBotFather,
                    icon: const Icon(Icons.send_rounded, size: 16),
                    label: const Text("Telegram'da @BotFather'ı Aç"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0088CC),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                _buildStep(
                  step: 2,
                  title: '/newbot Komutunu Gönderin',
                  description: 'BotFather sohbetine /newbot yazıp gönderin.',
                  stepBg: stepBg,
                  textCol: textCol,
                  secCol: secCol,
                  action: InkWell(
                    onTap: () {
                      Clipboard.setData(const ClipboardData(text: '/newbot'));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('/newbot kopyalandı!')),
                      );
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.black38 : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppTheme.primaryBlue.withAlpha(60),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.copy_rounded,
                            size: 14,
                            color: AppTheme.primaryBlue,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '/newbot',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              color: textCol,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '(Kopyala)',
                            style: TextStyle(fontSize: 11, color: secCol),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                _buildStep(
                  step: 3,
                  title: 'Bota Bir İsim Verin',
                  description:
                      'Botunuzun görünen adını yazın. Örnek: "Sticker Aktarıcım".',
                  stepBg: stepBg,
                  textCol: textCol,
                  secCol: secCol,
                ),
                const SizedBox(height: 12),

                _buildStep(
                  step: 4,
                  title: 'Benzersiz Kullanıcı Adı Seçin',
                  description:
                      'Sonu mutlaka "bot" ile bitmelidir. Örnek: "benim_stickerswap_bot".',
                  stepBg: stepBg,
                  textCol: textCol,
                  secCol: secCol,
                ),
                const SizedBox(height: 12),

                _buildStep(
                  step: 5,
                  title: "API Token'ı Kopyalayın ve Yapıştırın",
                  description:
                      'BotFather\'ın verdiği "Use this token to access the HTTP API" altındaki tokenı kopyalayıp aşağıdaki alana yapıştırın.',
                  stepBg: stepBg,
                  textCol: textCol,
                  secCol: secCol,
                ),
                const SizedBox(height: 20),

                // Token Input Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF151E32)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _isSuccess
                          ? AppTheme.success
                          : (isDark ? Colors.white12 : const Color(0xFFCBD5E1)),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _isSuccess
                                ? Icons.check_circle_rounded
                                : Icons.key_rounded,
                            size: 18,
                            color: _isSuccess
                                ? AppTheme.success
                                : AppTheme.primaryBlue,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Bot Tokeninizi Yapıştırın',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: textCol,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _tokenController,
                        style: TextStyle(
                          color: textCol,
                          fontSize: 13,
                          fontFamily: 'monospace',
                        ),
                        decoration: InputDecoration(
                          hintText: '123456789:ABCdefGHIjklmno...',
                          hintStyle: TextStyle(
                            color: secCol.withAlpha(120),
                            fontSize: 13,
                          ),
                          filled: true,
                          fillColor: isDark
                              ? AppTheme.surfaceDark
                              : Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: isDark
                                  ? Colors.white12
                                  : const Color(0xFFE2E8F0),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: isDark
                                  ? Colors.white12
                                  : const Color(0xFFE2E8F0),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: AppTheme.primaryBlue,
                              width: 1.5,
                            ),
                          ),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.paste_rounded, size: 20),
                            onPressed: () async {
                              final data = await Clipboard.getData(
                                Clipboard.kTextPlain,
                              );
                              if (data?.text != null) {
                                _tokenController.text = data!.text!.trim();
                              }
                            },
                          ),
                        ),
                      ),
                      if (_statusMessage != null) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(
                              _isSuccess
                                  ? Icons.check_circle
                                  : Icons.error_outline,
                              size: 16,
                              color: _isSuccess
                                  ? AppTheme.success
                                  : AppTheme.error,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _statusMessage!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _isSuccess
                                      ? AppTheme.success
                                      : AppTheme.error,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 14),
                      GradientButton(
                        text: _isSuccess ? 'Kaydedildi ✓' : 'Kaydet ve Test Et',
                        isLoading: _isTesting,
                        height: 48,
                        onPressed: _saveAndTestToken,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Info note
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withAlpha(isDark ? 25 : 15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.shield_outlined,
                        size: 18,
                        color: AppTheme.primaryBlue,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Tokenınız tamamen kendi cihazınızda saklanır ve doğrudan Telegram API ile haberleşir.',
                          style: TextStyle(fontSize: 12, color: secCol),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep({
    required int step,
    required String title,
    required String description,
    required Color stepBg,
    required Color textCol,
    required Color secCol,
    Widget? action,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: stepBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: AppTheme.primaryBlue,
            child: Text(
              '$step',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: textCol,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(fontSize: 12, color: secCol, height: 1.35),
                ),
                if (action != null) ...[const SizedBox(height: 8), action],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
