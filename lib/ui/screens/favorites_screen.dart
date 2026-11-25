import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/constants.dart';
import '../../data/models/channel.dart';
import '../../providers/app_providers.dart';
import '../home_shell.dart';
import '../player/player_screen.dart';
import '../widgets/channel_tile.dart';

/// تبويب المفضلة: قنواتك المحفوظة مرتبة بالاسم، مع بحث يظهر عند كثرتها.
/// القنوات في التصنيفات الأبوية المقفلة لا تظهر هنا حتى يُفتح التصنيف.
class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  /// نعرض خانة البحث فقط عندما تكثر المفضلة.
  static const int _searchThreshold = 8;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _search.clear();
    setState(() => _query = '');
  }

  void _openPlayer(Channel c, List<Channel> list) {
    ref.read(recentsProvider.notifier).add(c);
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PlayerScreen(channel: c, queue: List<Channel>.of(list)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final favorites = ref.watch(favoritesProvider);
    final locked = ref.watch(lockedCategoriesProvider);
    final unlocked = ref.watch(unlockedCategoriesProvider);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withOpacity(0.58);

    // استبعاد قنوات التصنيفات المقفلة.
    var list = favorites;
    if (locked.isNotEmpty) {
      list = favorites.where((c) {
        final k = categoryKeyOf(c);
        return !locked.contains(k) || unlocked.contains(k);
      }).toList();
    }

    final showSearch = list.length >= _searchThreshold;
    final q = normalizeSearch(_query);
    final shown = (!showSearch || q.isEmpty)
        ? list
        : list
            .where((c) => normalizeSearch('${c.name} ${c.group}').contains(q))
            .toList();

    Widget body;
    if (list.isEmpty) {
      body = _FavoritesEmpty(
        title: s.noFavorites,
        hint: s.noFavoritesHint,
        actionLabel: s.navChannels,
        onAction: () => ref.read(homeTabProvider.notifier).state = 0,
      );
    } else if (shown.isEmpty) {
      body = Center(
        child: Text(
          s.noResults,
          style: theme.textTheme.bodyLarge?.copyWith(color: muted),
        ),
      );
    } else {
      body = ListView.builder(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.only(top: 4, bottom: 16),
        itemCount: shown.length,
        itemBuilder: (context, i) {
          final c = shown[i];
          return ChannelTile(
            key: ValueKey(c.id),
            channel: c,
            isFavorite: true,
            onTap: () => _openPlayer(c, shown),
            onToggleFavorite: () =>
                ref.read(favoritesProvider.notifier).toggle(c),
            onLongPress: () =>
                showChannelActions(context, c, allowHide: false),
          );
        },
      );
    }

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          // ─── الترويسة ───
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 4),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.live.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm + 2),
                  ),
                  child: const Icon(
                    Icons.favorite_rounded,
                    color: AppColors.live,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.navFavorites,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          height: 1.15,
                        ),
                      ),
                      if (list.isNotEmpty)
                        Text(
                          s.channelsCount(shown.length),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: muted, fontSize: 12),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ─── البحث ───
          if (showSearch)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppConstants.pagePadding,
                8,
                AppConstants.pagePadding,
                8,
              ),
              child: TextField(
                controller: _search,
                onChanged: (v) => setState(() => _query = v),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: s.searchChannelsHint,
                  prefixIcon: Icon(Icons.search_rounded, color: muted),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: _clearSearch,
                        ),
                ),
              ),
            )
          else
            const SizedBox(height: 8),

          Expanded(child: body),
        ],
      ),
    );
  }
}

/// حالة المفضلة الفارغة.
class _FavoritesEmpty extends StatelessWidget {
  final String title;
  final String hint;
  final String actionLabel;
  final VoidCallback onAction;

  const _FavoritesEmpty({
    required this.title,
    required this.hint,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.live.withOpacity(0.12),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.live.withOpacity(0.25),
                    blurRadius: 40,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(
                Icons.favorite_border_rounded,
                size: 46,
                color: AppColors.live,
              ),
            ),
            const SizedBox(height: 28),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.live_tv_rounded),
              label: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}
