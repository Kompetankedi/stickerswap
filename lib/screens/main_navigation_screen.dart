import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';
import 'my_packs_screen.dart';
import 'settings_screen.dart';

/// Root navigation scaffold with animated bottom navigation bar.
class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => MainNavigationScreenState();
}

class MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  final _pageController = PageController();

  // Expose so HomeScreen can trigger shared text handling
  final GlobalKey<HomeScreenState> homeKey = GlobalKey<HomeScreenState>();

  static const _channel = MethodChannel('com.example.stickerswap/share');

  @override
  void initState() {
    super.initState();
    _handleInitialSharedText();
    _channel.setMethodCallHandler(_onMethodCall);
  }

  Future<void> _handleInitialSharedText() async {
    try {
      final sharedText = await _channel.invokeMethod<String>(
        'getInitialSharedText',
      );
      if (sharedText != null && sharedText.isNotEmpty) {
        // Give the widget tree a frame to build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          homeKey.currentState?.handleSharedText(sharedText);
        });
      }
    } on PlatformException catch (_) {}
  }

  Future<dynamic> _onMethodCall(MethodCall call) async {
    if (call.method == 'onSharedText') {
      final text = call.arguments as String?;
      if (text != null && text.isNotEmpty) {
        // Switch to home tab
        setState(() => _currentIndex = 0);
        _pageController.jumpToPage(0);
        homeKey.currentState?.handleSharedText(text);
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onTabTapped(int index) {
    setState(() => _currentIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          HomeScreen(key: homeKey, onNavigateToSettings: () => _onTabTapped(2)),
          MyPacksScreen(onNavigateToExplore: () => _onTabTapped(0)),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppTheme.getSurface(context),
          border: Border(
            top: BorderSide(
              color: AppTheme.isDark(context)
                  ? const Color(0xFF334155)
                  : const Color(0xFFE2E8F0),
              width: 1,
            ),
          ),
          boxShadow: AppTheme.isDark(context)
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withAlpha(10),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(
                  icon: Icons.swap_horiz_rounded,
                  label: 'Aktar',
                  isSelected: _currentIndex == 0,
                  onTap: () => _onTabTapped(0),
                ),
                _NavItem(
                  icon: Icons.folder_rounded,
                  label: 'Paketlerim',
                  isSelected: _currentIndex == 1,
                  onTap: () => _onTabTapped(1),
                ),
                _NavItem(
                  icon: Icons.settings_rounded,
                  label: 'Ayarlar',
                  isSelected: _currentIndex == 2,
                  onTap: () => _onTabTapped(2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final mutCol = AppTheme.getTextMut(context);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryBlue.withAlpha(isDark ? 25 : 20)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              child: Icon(
                icon,
                size: isSelected ? 26 : 24,
                color: isSelected ? AppTheme.primaryBlue : mutCol,
              ),
            ),
            const SizedBox(height: 4),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 250),
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? AppTheme.primaryBlue : mutCol,
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}
