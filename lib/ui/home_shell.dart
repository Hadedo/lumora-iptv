import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_colors.dart';
import '../providers/app_providers.dart';
import 'screens/channels_screen.dart';
import 'screens/favorites_screen.dart';
import 'screens/playlists_screen.dart';
import 'screens/settings_screen.dart';

/// التبويب الحالي: 0 القنوات، 1 المفضلة، 2 القوائم، 3 الإعدادات.
/// يمكن لأي شاشة تغييره، مثلاً زر "أضف قائمة" في شاشة القنوات الفارغة ينقل للتبويب 2.
final homeTabProvider = StateProvider<int>((ref) => 0);

/// الهيكل الرئيسي: أربعة تبويبات بشريط تنقل سفلي.
/// التبويبات تُبنى عند أول زيارة فقط (بدء أسرع) وتحافظ على حالتها بعد ذلك.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  final Set<int> _visited = {0};

  Widget _page(int index) {
    if (!_visited.contains(index)) return const SizedBox.shrink();
    switch (index) {
      case 0:
        return const ChannelsScreen();
      case 1:
        return const FavoritesScreen();
      case 2:
        return const PlaylistsScreen();
      default:
        return const SettingsScreen();
    }
  }

  void _select(int index) {
    if (index == ref.read(homeTabProvider)) return;
    HapticFeedback.selectionClick();
    setState(() => _visited.add(index));
    ref.read(homeTabProvider.notifier).state = index;
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final tab = ref.watch(homeTabProvider);
    _visited.add(tab);

    return PopScope(
      // زر الرجوع يعيد للتبويب الأول قبل الخروج من التطبيق.
      canPop: tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ref.read(homeTabProvider.notifier).state = 0;
      },
      child: Scaffold(
        body: Column(
          children: [
            Expanded(
              child: IndexedStack(
                index: tab,
                children: List.generate(4, _page),
              ),
            ),
            const _OfflineBanner(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: _select,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.live_tv_outlined),
              selectedIcon: const Icon(Icons.live_tv_rounded),
              label: s.navChannels,
            ),
            NavigationDestination(
              icon: const Icon(Icons.favorite_border_rounded),
              selectedIcon: const Icon(Icons.favorite_rounded),
              label: s.navFavorites,
            ),
            NavigationDestination(
              icon: const Icon(Icons.playlist_play_outlined),
              selectedIcon: const Icon(Icons.playlist_play_rounded),
              label: s.navPlaylists,
            ),
            NavigationDestination(
              icon: const Icon(Icons.tune_outlined),
              selectedIcon: const Icon(Icons.tune_rounded),
              label: s.navSettings,
            ),
          ],
        ),
      ),
    );
  }
}

/// شريط رفيع يظهر فوق شريط التنقل عند انقطاع الإنترنت ويختفي عند عودته.
class _OfflineBanner extends ConsumerWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(isOnlineProvider).valueOrNull == false;
    final s = ref.watch(stringsProvider);

    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomCenter,
      child: offline
          ? Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
              color: AppColors.warning.withOpacity(0.16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.wifi_off_rounded,
                      size: 16, color: AppColors.warning),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      s.noInternet,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.warning,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            )
          : const SizedBox(width: double.infinity),
    );
  }
}
