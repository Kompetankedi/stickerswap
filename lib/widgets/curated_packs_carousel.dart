import 'package:flutter/material.dart';
import '../models/curated_pack.dart';
import '../theme/app_theme.dart';

/// Horizontal carousel displaying curated popular Telegram sticker packs
/// with category filter pills and single-tap selection.
class CuratedPacksCarousel extends StatefulWidget {
  final ValueChanged<CuratedPack> onPackSelected;

  const CuratedPacksCarousel({
    super.key,
    required this.onPackSelected,
  });

  @override
  State<CuratedPacksCarousel> createState() => _CuratedPacksCarouselState();
}

class _CuratedPacksCarouselState extends State<CuratedPacksCarousel> {
  String _selectedCategory = CuratedPack.categories.first;

  List<CuratedPack> get _filteredPacks {
    if (_selectedCategory == 'Tümü') {
      return CuratedPack.popularPacks;
    }
    return CuratedPack.popularPacks
        .where((pack) => pack.category == _selectedCategory)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final textCol = AppTheme.getText(context);
    final secCol = AppTheme.getTextSec(context);
    final mutCol = AppTheme.getTextMut(context);
    final filtered = _filteredPacks;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.local_fire_department_rounded,
              size: 18,
              color: Colors.deepOrangeAccent,
            ),
            const SizedBox(width: 6),
            Text(
              'Popüler ve Trend Paketler',
              style: TextStyle(
                color: textCol,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 32,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: CuratedPack.categories.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final category = CuratedPack.categories[index];
              final isSelected = category == _selectedCategory;
              return ChoiceChip(
                label: Text(category),
                selected: isSelected,
                onSelected: (_) {
                  if (_selectedCategory != category) {
                    setState(() => _selectedCategory = category);
                  }
                },
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? Colors.white : secCol,
                ),
                selectedColor: AppTheme.primaryBlue,
                backgroundColor: isDark
                    ? AppTheme.cardDark
                    : const Color(0xFFF1F5F9),
                side: BorderSide(
                  color: isSelected
                      ? AppTheme.primaryBlue
                      : (isDark
                          ? const Color(0xFF334155)
                          : const Color(0xFFE2E8F0)),
                ),
                showCheckmark: false,
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 148,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: filtered.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final pack = filtered[index];
              return _CuratedPackCard(
                pack: pack,
                isDark: isDark,
                textCol: textCol,
                secCol: secCol,
                mutCol: mutCol,
                onTap: () => widget.onPackSelected(pack),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CuratedPackCard extends StatelessWidget {
  final CuratedPack pack;
  final bool isDark;
  final Color textCol;
  final Color secCol;
  final Color mutCol;
  final VoidCallback onTap;

  const _CuratedPackCard({
    required this.pack,
    required this.isDark,
    required this.textCol,
    required this.secCol,
    required this.mutCol,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 184,
      child: Material(
        color: isDark ? AppTheme.cardDark : AppTheme.cardLight,
        borderRadius: AppTheme.cardRadius,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppTheme.cardRadius,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: AppTheme.cardRadius,
              border: AppTheme.getBorder(context),
              boxShadow: isDark ? null : AppTheme.lightCardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryBlue.withAlpha(isDark ? 35 : 20),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        pack.iconEmoji,
                        style: const TextStyle(fontSize: 20),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryBlue.withAlpha(isDark ? 30 : 16),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          pack.tag,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primaryBlue,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  pack.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textCol,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '@${pack.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: mutCol,
                    fontSize: 11,
                  ),
                ),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '~${pack.estimatedCount} çıkartma',
                      style: TextStyle(
                        color: secCol,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      size: 14,
                      color: AppTheme.primaryBlue,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
