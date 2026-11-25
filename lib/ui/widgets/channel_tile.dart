import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/constants.dart';
import '../../data/models/channel.dart';
import '../../providers/app_providers.dart';

/// شعار القناة: صورة مخزَّنة مؤقتاً بحجم مصغّر، وعند غيابها أو فشلها يظهر حرفان ملونان.
class ChannelLogo extends StatelessWidget {
  final Channel channel;
  final double size;

  const ChannelLogo({
    super.key,
    required this.channel,
    this.size = AppConstants.logoSize,
  });

  static const List<List<Color>> _tints = [
    [Color(0xFF7C5CFF), Color(0xFF5B3DE0)],
    [Color(0xFF2EE6D6), Color(0xFF1AA89C)],
    [Color(0xFFFF7A59), Color(0xFFE0533A)],
    [Color(0xFF4D9BFF), Color(0xFF2F6FDB)],
    [Color(0xFFB86CFF), Color(0xFF8A3FE0)],
    [Color(0xFFFFB84D), Color(0xFFE08A1F)],
  ];

  Widget _initials() {
    final tint = _tints[channel.name.hashCode.abs() % _tints.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: tint,
        ),
      ),
      child: Text(
        channel.initials,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.34,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final valid = channel.hasLogo && channel.logo.startsWith('http');

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusSm + 2),
      child: SizedBox(
        width: size,
        height: size,
        child: valid
            ? Container(
                color: Colors.white.withOpacity(0.06),
                padding: const EdgeInsets.all(4),
                child: CachedNetworkImage(
                  imageUrl: channel.logo,
                  memCacheWidth: AppConstants.logoCacheWidth,
                  fit: BoxFit.contain,
                  fadeInDuration: AppConstants.animFast,
                  fadeOutDuration: Duration.zero,
                  placeholder: (_, __) => const SizedBox.shrink(),
                  errorWidget: (_, __, ___) => _initials(),
                ),
              )
            : _initials(),
      ),
    );
  }
}

/// صف القناة في القوائم. خفيف، ومعزول بـ RepaintBoundary لتمرير سلس في القوائم الطويلة.
class ChannelTile extends StatelessWidget {
  final Channel channel;
  final bool isFavorite;
  final bool isPlaying;
  final bool showGroup;
  final VoidCallback onTap;
  final VoidCallback? onToggleFavorite;
  final VoidCallback? onLongPress;

  const ChannelTile({
    super.key,
    required this.channel,
    required this.onTap,
    this.isFavorite = false,
    this.isPlaying = false,
    this.showGroup = true,
    this.onToggleFavorite,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurface.withOpacity(0.58);

    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.pagePadding,
          vertical: 4,
        ),
        child: Material(
          color: isPlaying
              ? AppColors.primary.withOpacity(0.14)
              : scheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress == null
                ? null
                : () {
                    HapticFeedback.mediumImpact();
                    onLongPress!();
                  },
            child: Container(
              padding: const EdgeInsetsDirectional.fromSTEB(10, 10, 4, 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                border: Border.all(
                  color: isPlaying
                      ? AppColors.primary.withOpacity(0.6)
                      : scheme.outline.withOpacity(0.7),
                ),
              ),
              child: Row(
                children: [
                  ChannelLogo(channel: channel),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          channel.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        if (showGroup && channel.hasGroup) ...[
                          const SizedBox(height: 3),
                          Text(
                            channel.group,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: muted,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (isPlaying)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(
                        Icons.equalizer_rounded,
                        color: AppColors.secondary,
                        size: 22,
                      ),
                    ),
                  if (onToggleFavorite != null)
                    IconButton(
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        onToggleFavorite!();
                      },
                      visualDensity: VisualDensity.compact,
                      icon: AnimatedSwitcher(
                        duration: AppConstants.animFast,
                        transitionBuilder: (child, anim) =>
                            ScaleTransition(scale: anim, child: child),
                        child: Icon(
                          isFavorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          key: ValueKey(isFavorite),
                          color: isFavorite ? AppColors.live : muted,
                          size: 23,
                        ),
                      ),
                    )
                  else
                    const SizedBox(width: 10),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// قائمة خيارات القناة عند الضغط المطوّل: المفضلة وإخفاء القناة.
Future<void> showChannelActions(
  BuildContext context,
  Channel channel, {
  bool allowHide = true,
}) {
  final container = ProviderScope.containerOf(context);
  final messenger = ScaffoldMessenger.of(context);

  return showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) {
      final s = container.read(stringsProvider);
      final isFav = container.read(favoriteIdsProvider).contains(channel.id);
      final theme = Theme.of(sheetContext);

      void toast(String text) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text(text),
            duration: const Duration(seconds: 2),
          ));
      }

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: Row(
                  children: [
                    ChannelLogo(channel: channel, size: 46),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        channel.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(),
              ListTile(
                leading: Icon(
                  isFav ? Icons.heart_broken_rounded : Icons.favorite_rounded,
                  color: AppColors.live,
                ),
                title: Text(
                  isFav ? s.removeFromFavorites : s.addToFavorites,
                ),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await container
                      .read(favoritesProvider.notifier)
                      .toggle(channel);
                },
              ),
              if (allowHide)
                ListTile(
                  leading: const Icon(Icons.visibility_off_rounded),
                  title: Text(s.hideChannel),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await container
                        .read(hiddenIdsProvider.notifier)
                        .hide(channel);
                    toast('${s.hideChannel}: ${channel.name}');
                  },
                ),
            ],
          ),
        ),
      );
    },
  );
}
