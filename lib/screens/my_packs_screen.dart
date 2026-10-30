import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../models/saved_pack.dart';
import '../services/storage_service.dart';
import '../services/whatsapp_service.dart';
import '../widgets/glass_card.dart';
import '../widgets/gradient_button.dart';
import '../widgets/status_badge.dart';

/// "My Packs" screen – lists locally saved sticker packs with storage info,
/// search filter, single-sticker inspection, and quick WhatsApp export.
class MyPacksScreen extends StatefulWidget {
  final VoidCallback? onNavigateToExplore;

  const MyPacksScreen({super.key, this.onNavigateToExplore});

  @override
  State<MyPacksScreen> createState() => _MyPacksScreenState();
}

class _MyPacksScreenState extends State<MyPacksScreen> {
  final _storageService = StorageService();
  final _whatsappService = WhatsAppService();
  List<SavedPack> _packs = [];
  bool _loaded = false;
  int _cacheBytes = 0;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadPacks();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) _loadPacks();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPacks() async {
    await _storageService.init();
    final packs = _storageService.getSavedPacks();
    final cacheBytes = await _storageService.getCacheSizeBytes();
    if (mounted) {
      setState(() {
        _packs = packs;
        _cacheBytes = cacheBytes;
        _loaded = true;
      });
    }
  }

  Future<void> _reAddToWhatsApp(SavedPack pack) async {
    try {
      HapticFeedback.lightImpact();
      final stickerData = <Map<String, dynamic>>[];
      for (int i = 0; i < pack.stickerPaths.length; i++) {
        stickerData.add({
          'path': pack.stickerPaths[i],
          'emojis': [i < pack.emojis.length ? pack.emojis[i] : '⭐'],
        });
      }

      final result = await _whatsappService.addStickerPack(
        identifier: pack.identifier,
        name: pack.name,
        publisher: pack.publisher,
        trayPath: pack.trayImagePath,
        stickerData: stickerData,
        animatedStickerPack: pack.isAnimated,
      );

      if (result.isAdded) {
        await _storageService.updatePackStatus(pack.identifier, true);
        _loadPacks();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('✅ WhatsApp\'a yeniden eklendi!'),
              backgroundColor: AppTheme.success,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
      } else if (result.isCancelled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('WhatsApp\'a ekleme iptal edildi.'),
              backgroundColor: AppTheme.textMuted,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Hata: ${result.errorMessage ?? 'Eklenemedi'}',
              ),
              backgroundColor: AppTheme.error,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Hata: ${e.toString().replaceAll('Exception: ', '')}',
            ),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  Future<void> _deletePack(SavedPack pack) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Paketi Sil',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: Text(
          '"${pack.name}" paketi yerel depolamadan silinecek. Devam edilsin mi?',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'İptal',
              style: TextStyle(color: AppTheme.textMuted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil', style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _whatsappService.deleteStickerPack(pack.identifier);
      await _storageService.removePack(pack.identifier);
      _loadPacks();
    }
  }

  void _showStickerPreviewModal(String imagePath, String emoji) {
    HapticFeedback.lightImpact();
    final file = File(imagePath);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final isDark = AppTheme.isDark(context);
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLightMode,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(
              top: BorderSide(
                color: isDark
                    ? const Color(0xFF334155)
                    : const Color(0xFFE2E8F0),
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF475569)
                      : const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  color: isDark
                      ? AppTheme.backgroundDark
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF334155)
                        : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Center(
                  child: file.existsSync()
                      ? Image.file(file, fit: BoxFit.contain)
                      : Text(emoji, style: const TextStyle(fontSize: 48)),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Emoji: $emoji',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
            ],
          ),
        );
      },
    );
  }

  List<SavedPack> get _filteredPacks {
    if (_searchQuery.trim().isEmpty) return _packs;
    final q = _searchQuery.toLowerCase();
    return _packs.where((p) {
      return p.name.toLowerCase().contains(q) ||
          p.publisher.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final filtered = _filteredPacks;

    return Scaffold(
      backgroundColor: AppTheme.getBackground(context),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Header ───────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryBlue,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.folder_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Paketlerim',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          Text(
                            '${_packs.length} paket kaydedildi',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (_cacheBytes > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppTheme.surfaceDarkElevated
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF334155)
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.storage_rounded,
                            size: 14,
                            color: AppTheme.accentPrimary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            StorageService.formatBytes(_cacheBytes),
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ).animate().fadeIn(duration: 400.ms).slideX(begin: -0.04),
            ),

            const SizedBox(height: 16),

            // ─── Search Bar (if packs exist) ───────────────
            if (_packs.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.cardDark : AppTheme.cardLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF334155)
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() => _searchQuery = val),
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 13,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Paketlerde ara...',
                      hintStyle: TextStyle(
                        color: AppTheme.textMuted.withAlpha(120),
                        fontSize: 13,
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: AppTheme.textMuted,
                        size: 20,
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(
                                Icons.clear_rounded,
                                size: 16,
                                color: AppTheme.textMuted,
                              ),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 14),

            // ─── Pack list ─────────────────────────────────
            Expanded(
              child: _packs.isEmpty
                  ? _buildEmptyState()
                  : filtered.isEmpty
                  ? Center(
                      child: Text(
                        '"$_searchQuery" ile eşleşen paket bulunamadı.',
                        style: TextStyle(
                          color: AppTheme.textMuted.withAlpha(160),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final pack = filtered[index];
                        return _PackCard(
                              pack: pack,
                              onReAdd: () => _reAddToWhatsApp(pack),
                              onDelete: () => _deletePack(pack),
                              onStickerTap: _showStickerPreviewModal,
                            )
                            .animate()
                            .fadeIn(
                              delay: Duration(milliseconds: 70 * index),
                              duration: 350.ms,
                            )
                            .slideY(begin: 0.04);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceLight,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(
                  Icons.folder_off_rounded,
                  size: 36,
                  color: AppTheme.textMuted,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Henüz kaydedilmiş paket yok',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Telegram çıkartmalarınızı aktardığınızda\nburada listelenecektir.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
              ),
              if (widget.onNavigateToExplore != null) ...[
                const SizedBox(height: 20),
                GradientButton(
                  text: 'Çıkartma Keşfet',
                  icon: Icons.explore_rounded,
                  height: 44,
                  gradient: AppTheme.telegramGradient,
                  onPressed: widget.onNavigateToExplore,
                ),
              ],
            ],
          ),
        )
        .animate()
        .fadeIn(duration: 500.ms)
        .scale(begin: const Offset(0.9, 0.9), curve: Curves.easeOutBack);
  }
}

class _PackCard extends StatelessWidget {
  final SavedPack pack;
  final VoidCallback onReAdd;
  final VoidCallback onDelete;
  final void Function(String path, String emoji) onStickerTap;

  const _PackCard({
    required this.pack,
    required this.onReAdd,
    required this.onDelete,
    required this.onStickerTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final trayFile = File(pack.trayImagePath);
    final hasTray = trayFile.existsSync();

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Tray icon
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: isDark
                      ? AppTheme.surfaceDarkElevated
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF334155)
                        : const Color(0xFFE2E8F0),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: hasTray
                      ? Image.file(trayFile, fit: BoxFit.contain)
                      : const Icon(
                          Icons.image_rounded,
                          color: AppTheme.textMuted,
                        ),
                ),
              ),
              const SizedBox(width: 14),
              // Pack info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pack.name,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          '${pack.stickerCount} çıkartma',
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '·',
                          style: TextStyle(
                            color: AppTheme.textMuted.withAlpha(100),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            pack.publisher,
                            style: const TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Status badge
              pack.addedToWhatsApp
                  ? StatusBadge.installed()
                  : StatusBadge.pending(),
            ],
          ),
          const SizedBox(height: 14),
          // Sticker preview row
          if (pack.stickerPaths.isNotEmpty)
            SizedBox(
              height: 52,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: pack.stickerPaths.length > 10
                    ? 10
                    : pack.stickerPaths.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (context, i) {
                  final path = pack.stickerPaths[i];
                  final file = File(path);
                  final emoji = i < pack.emojis.length ? pack.emojis[i] : '⭐';

                  return InkWell(
                    onTap: () => onStickerTap(path, emoji),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppTheme.surfaceDarkElevated
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF334155)
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: file.existsSync()
                            ? Image.file(file, fit: BoxFit.contain)
                            : Center(
                                child: Text(
                                  emoji,
                                  style: const TextStyle(fontSize: 20),
                                ),
                              ),
                      ),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 14),
          // Action buttons
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: GradientButton(
                    text: 'WhatsApp\'a Ekle',
                    icon: Icons.send_rounded,
                    height: 42,
                    gradient: AppTheme.whatsappGradient,
                    onPressed: onReAdd,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: onDelete,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppTheme.error.withAlpha(20),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.error.withAlpha(50)),
                  ),
                  child: const Icon(
                    Icons.delete_outline_rounded,
                    color: AppTheme.error,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
