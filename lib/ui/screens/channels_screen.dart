import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/constants.dart';
import '../../data/models/channel.dart';
import '../../data/services/playlist_service.dart';
import '../../providers/app_providers.dart';
import '../home_shell.dart';
import '../player/player_screen.dart';
import '../splash_screen.dart';
import '../widgets/channel_tile.dart';

const String _allPlaylistsValue = '__all_playlists__';

class _ChipData {
  final String key;
  final String label;
  final bool locked;
  const _ChipData(this.key, this.label, this.locked);
}

String _errorText(AppStrings s, Object e) {
  if (e is PlaylistException) {
    switch (e.error) {
      case PlaylistError.network:
        return s.noInternet;
      case PlaylistError.invalidUrl:
        return s.invalidUrl;
      case PlaylistError.invalidPlaylist:
        return s.invalidPlaylist;
      case PlaylistError.loginFailed:
        return s.loginFailed;
      case PlaylistError.fileRead:
        return s.unknownError;
    }
  }
  return s.unknownError;
}

/// تبويب القنوات: بحث فوري، تصنيفات، قفل أبوي، وسحب للتحديث.
class ChannelsScreen extends ConsumerStatefulWidget {
  const ChannelsScreen({super.key});

  @override
  ConsumerState<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends ConsumerState<ChannelsScreen> {
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () {
      if (mounted) ref.read(searchQueryProvider.notifier).set(v);
    });
    setState(() {});
  }

  void _clearSearch() {
    _debounce?.cancel();
    _search.clear();
    ref.read(searchQueryProvider.notifier).set('');
    setState(() {});
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        duration: const Duration(seconds: 2),
      ));
  }

  void _openPlayer(Channel c, List<Channel> list) {
    ref.read(recentsProvider.notifier).add(c);
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PlayerScreen(channel: c, queue: List<Channel>.of(list)),
    ));
  }

  Future<void> _unlock(String key) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _PinDialog(
        s: ref.read(stringsProvider),
        verify: ref.read(hasPinProvider.notifier).verify,
      ),
    );
    if (ok == true) {
      ref.read(unlockedCategoriesProvider.notifier).unlock(key);
    }
  }

  Future<void> _refresh() async {
    final s = ref.read(stringsProvider);
    final playlists = ref.read(playlistsProvider);
    if (playlists.isEmpty) return;
    final active = ref.read(activePlaylistIdProvider);
    final notifier = ref.read(playlistsProvider.notifier);

    try {
      if (active != null) {
        final p = playlists.firstWhere(
          (e) => e.id == active,
          orElse: () => playlists.first,
        );
        await notifier.refresh(p);
      } else {
        final ok = await notifier.refreshAll();
        if (ok == 0) throw const PlaylistException(PlaylistError.network);
      }
      _toast(s.playlistUpdated);
    } catch (e) {
      _toast(_errorText(s, e));
    }
  }

  void _goToPlaylists() => ref.read(homeTabProvider.notifier).state = 2;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final playlists = ref.watch(playlistsProvider);
    final activeId = ref.watch(activePlaylistIdProvider);
    final visible = ref.watch(visibleChannelsProvider);
    final categories = ref.watch(categoriesProvider);
    final selected = ref.watch(selectedCategoryProvider);
    final recents = ref.watch(recentsProvider);
    final favIds = ref.watch(favoriteIdsProvider);
    final locked = ref.watch(lockedCategoriesProvider);
    final isLocked = ref.watch(selectedCategoryLockedProvider);
    final displayed = ref.watch(displayedChannelsProvider);
    final query = ref.watch(searchQueryProvider);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withOpacity(0.58);

    // إن اختفى التصنيف المحدد بعد تحديث القائمة نعود إلى "الكل".
    final validSelection = selected == AppConstants.allCategoryKey ||
        (selected == AppConstants.recentCategoryKey && recents.isNotEmpty) ||
        categories.any((c) => c.key == selected);
    if (!validSelection) {
      Future.microtask(() {
        if (mounted) {
          ref
              .read(selectedCategoryProvider.notifier)
              .set(AppConstants.allCategoryKey);
        }
      });
    }

    final chips = <_ChipData>[
      _ChipData(AppConstants.allCategoryKey, s.allChannels, false),
      if (recents.isNotEmpty)
        _ChipData(AppConstants.recentCategoryKey, s.recent, false),
      for (final c in categories)
        _ChipData(
          c.key,
          c.isUncategorized ? s.uncategorized : c.name,
          locked.contains(c.key),
        ),
    ];

    final hasChannels = playlists.isNotEmpty && visible.isNotEmpty;

    Widget body;
    if (playlists.isEmpty) {
      body = _EmptyState(
        title: s.noPlaylists,
        hint: s.noPlaylistsHint,
        actionLabel: s.addPlaylist,
        onAction: _goToPlaylists,
      );
    } else if (visible.isEmpty) {
      body = _EmptyState(
        title: s.noChannels,
        hint: s.noChannelsHint,
        actionLabel: s.addPlaylist,
        onAction: _goToPlaylists,
      );
    } else if (isLocked) {
      body = _LockedView(
        s: s,
        categoryName: selected,
        onUnlock: () => _unlock(selected),
      );
    } else if (displayed.isEmpty) {
      body = Center(
        child: Text(
          s.noResults,
          style: theme.textTheme.bodyLarge?.copyWith(color: muted),
        ),
      );
    } else {
      final showGroup = selected == AppConstants.allCategoryKey ||
          selected == AppConstants.recentCategoryKey ||
          query.isNotEmpty;
      body = RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: theme.colorScheme.surface,
        onRefresh: _refresh,
        child: ListView.builder(
          key: ValueKey('$selected|${query.isEmpty}'),
          physics: const AlwaysScrollableScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.only(top: 4, bottom: 16),
          itemCount: displayed.length,
          itemBuilder: (context, i) {
            final c = displayed[i];
            return ChannelTile(
              key: ValueKey(c.id),
              channel: c,
              isFavorite: favIds.contains(c.id),
              showGroup: showGroup,
              onTap: () => _openPlayer(c, displayed),
              onToggleFavorite: () =>
                  ref.read(favoritesProvider.notifier).toggle(c),
              onLongPress: () => showChannelActions(context, c),
            );
          },
        ),
      );
    }

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          // ─── الترويسة ───
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 8, 4),
            child: Row(
              children: [
                const LumoraLogo(size: 34, glow: false),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.appName,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          height: 1.15,
                        ),
                      ),
                      if (hasChannels)
                        Text(
                          s.channelsCount(displayed.length),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: muted, fontSize: 12),
                        ),
                    ],
                  ),
                ),
                if (playlists.length > 1)
                  PopupMenuButton<String>(
                    tooltip: s.navPlaylists,
                    icon: const Icon(Icons.layers_rounded),
                    onSelected: (v) => ref
                        .read(activePlaylistIdProvider.notifier)
                        .select(v == _allPlaylistsValue ? null : v),
                    itemBuilder: (_) => [
                      CheckedPopupMenuItem<String>(
                        value: _allPlaylistsValue,
                        checked: activeId == null,
                        child: Text(s.allChannels),
                      ),
                      for (final p in playlists)
                        CheckedPopupMenuItem<String>(
                          value: p.id,
                          checked: activeId == p.id,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 200),
                            child: Text(
                              p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),

          // ─── البحث والتصنيفات ───
          if (hasChannels) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _search,
                onChanged: _onSearchChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: s.searchChannelsHint,
                  prefixIcon: Icon(Icons.search_rounded, color: muted),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: _clearSearch,
                        ),
                ),
              ),
            ),
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: chips.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final chip = chips[i];
                  final isSelected = chip.key == selected;
                  return ChoiceChip(
                    selected: isSelected,
                    avatar: chip.locked
                        ? Icon(
                            Icons.lock_rounded,
                            size: 15,
                            color: isSelected ? Colors.white : muted,
                          )
                        : null,
                    label: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 180),
                      child: Text(
                        chip.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    onSelected: (_) {
                      HapticFeedback.selectionClick();
                      ref.read(selectedCategoryProvider.notifier).set(chip.key);
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 6),
          ],

          // ─── المحتوى ───
          Expanded(child: body),
        ],
      ),
    );
  }
}

/// حالة فارغة: شعار + رسالة + زر.
class _EmptyState extends StatelessWidget {
  final String title;
  final String hint;
  final String actionLabel;
  final VoidCallback onAction;

  const _EmptyState({
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
            const LumoraLogo(size: 96),
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
            FilledButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.add_rounded),
              label: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

/// واجهة التصنيف المقفل.
class _LockedView extends StatelessWidget {
  final AppStrings s;
  final String categoryName;
  final VoidCallback onUnlock;

  const _LockedView({
    required this.s,
    required this.categoryName,
    required this.onUnlock,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.16),
                borderRadius: BorderRadius.circular(AppTheme.radiusLg),
              ),
              child: const Icon(
                Icons.lock_rounded,
                size: 40,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 22),
            Text(
              s.lockedCategory,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              categoryName,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: onUnlock,
              icon: const Icon(Icons.lock_open_rounded),
              label: Text(s.enterPin),
            ),
          ],
        ),
      ),
    );
  }
}

/// نافذة إدخال الرمز: تتحقق تلقائياً عند اكتمال 4 أرقام.
class _PinDialog extends StatefulWidget {
  final AppStrings s;
  final bool Function(String pin) verify;

  const _PinDialog({required this.s, required this.verify});

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final TextEditingController _c = TextEditingController();
  bool _error = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    if (_error) setState(() => _error = false);
    if (v.length != AppConstants.pinLength) return;

    if (widget.verify(v)) {
      Navigator.of(context).pop(true);
    } else {
      HapticFeedback.heavyImpact();
      _c.clear();
      setState(() => _error = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return AlertDialog(
      title: Text(s.enterPin),
      content: Directionality(
        textDirection: TextDirection.ltr,
        child: TextField(
          controller: _c,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: AppConstants.pinLength,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(fontSize: 26, letterSpacing: 12),
          decoration: InputDecoration(
            counterText: '',
            errorText: _error ? s.wrongPin : null,
          ),
          onChanged: _onChanged,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(s.cancel),
        ),
      ],
    );
  }
}
