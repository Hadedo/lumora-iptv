import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/constants.dart';
import '../../data/models/playlist.dart';
import '../../data/services/playlist_service.dart';
import '../../providers/app_providers.dart';
import '../home_shell.dart';
import '../splash_screen.dart';

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

String _two(int n) => n.toString().padLeft(2, '0');

String _formatDate(DateTime d) =>
    '${d.year}/${_two(d.month)}/${_two(d.day)}  ${_two(d.hour)}:${_two(d.minute)}';

/// تبويب القوائم: عرض القوائم، تفعيل واحدة، تحديثها، حذفها، وإضافة قائمة جديدة.
class PlaylistsScreen extends ConsumerWidget {
  const PlaylistsScreen({super.key});

  void _toast(BuildContext context, String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        duration: const Duration(seconds: 2),
      ));
  }

  Future<void> _openAdd(BuildContext context, WidgetRef ref) async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AddPlaylistSheet(),
    );
    if (added == true && context.mounted) {
      _toast(context, ref.read(stringsProvider).playlistAdded);
      ref.read(homeTabProvider.notifier).state = 0;
    }
  }

  Future<void> _refreshOne(
    BuildContext context,
    WidgetRef ref,
    Playlist p,
  ) async {
    final s = ref.read(stringsProvider);
    try {
      await ref.read(playlistsProvider.notifier).refresh(p);
      if (context.mounted) _toast(context, s.playlistUpdated);
    } catch (e) {
      if (context.mounted) _toast(context, _errorText(s, e));
    }
  }

  Future<void> _refreshAll(BuildContext context, WidgetRef ref) async {
    final s = ref.read(stringsProvider);
    final ok = await ref.read(playlistsProvider.notifier).refreshAll();
    if (!context.mounted) return;
    _toast(context, ok > 0 ? s.playlistUpdated : s.noInternet);
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Playlist p,
  ) async {
    final s = ref.read(stringsProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.deletePlaylistTitle),
        content: Text(s.deletePlaylistBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: Text(s.delete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(playlistsProvider.notifier).delete(p);
    if (context.mounted) _toast(context, s.playlistDeleted);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final playlists = ref.watch(playlistsProvider);
    final activeId = ref.watch(activePlaylistIdProvider);
    final refreshing = ref.watch(refreshingIdsProvider);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withOpacity(0.58);

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          // ─── الترويسة ───
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    s.navPlaylists,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (playlists.length > 1)
                  IconButton(
                    tooltip: s.refreshAll,
                    onPressed: refreshing.isNotEmpty
                        ? null
                        : () => _refreshAll(context, ref),
                    icon: const Icon(Icons.sync_rounded),
                  ),
                const SizedBox(width: 4),
                FilledButton.icon(
                  onPressed: () => _openAdd(context, ref),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 42),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: Text(s.add),
                ),
              ],
            ),
          ),

          // ─── المحتوى ───
          Expanded(
            child: playlists.isEmpty
                ? _PlaylistsEmpty(
                    title: s.noPlaylists,
                    hint: s.noPlaylistsHint,
                    actionLabel: s.addPlaylist,
                    onAction: () => _openAdd(context, ref),
                    disclaimer: s.disclaimer,
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(
                      AppConstants.pagePadding,
                      4,
                      AppConstants.pagePadding,
                      24,
                    ),
                    itemCount: playlists.length + 1,
                    itemBuilder: (context, i) {
                      if (i == playlists.length) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(8, 20, 8, 0),
                          child: Text(
                            s.disclaimer,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: muted, height: 1.5),
                          ),
                        );
                      }
                      final p = playlists[i];
                      return _PlaylistCard(
                        s: s,
                        playlist: p,
                        isActive: p.id == activeId,
                        isRefreshing: refreshing.contains(p.id),
                        onTap: () async {
                          await ref
                              .read(activePlaylistIdProvider.notifier)
                              .select(p.id);
                          ref.read(homeTabProvider.notifier).state = 0;
                        },
                        onRefresh: () => _refreshOne(context, ref, p),
                        onDelete: () => _confirmDelete(context, ref, p),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// بطاقة قائمة واحدة.
class _PlaylistCard extends StatelessWidget {
  final AppStrings s;
  final Playlist playlist;
  final bool isActive;
  final bool isRefreshing;
  final VoidCallback onTap;
  final VoidCallback onRefresh;
  final VoidCallback onDelete;

  const _PlaylistCard({
    required this.s,
    required this.playlist,
    required this.isActive,
    required this.isRefreshing,
    required this.onTap,
    required this.onRefresh,
    required this.onDelete,
  });

  IconData get _icon {
    switch (playlist.type) {
      case PlaylistType.url:
        return Icons.link_rounded;
      case PlaylistType.file:
        return Icons.insert_drive_file_rounded;
      case PlaylistType.xtream:
        return Icons.dns_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurface.withOpacity(0.58);
    final date = playlist.updatedDate;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Material(
        color: isActive ? AppColors.primary.withOpacity(0.12) : scheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 14, 6, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(
                color: isActive
                    ? AppColors.primary.withOpacity(0.7)
                    : scheme.outline.withOpacity(0.7),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: isActive ? AppColors.brandGradient : null,
                    color: isActive ? null : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm + 2),
                  ),
                  child: Icon(
                    _icon,
                    color: isActive ? Colors.white : muted,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              playlist.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                fontSize: 15.5,
                              ),
                            ),
                          ),
                          if (isActive) ...[
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.check_circle_rounded,
                              size: 17,
                              color: AppColors.secondary,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        s.channelsCount(playlist.channelCount),
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: muted, fontSize: 12.5),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        date == null
                            ? s.never
                            : '${s.lastUpdated}: ${_formatDate(date)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface.withOpacity(0.42),
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isRefreshing)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    ),
                  )
                else
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert_rounded, color: muted),
                    onSelected: (v) {
                      if (v == 'refresh') onRefresh();
                      if (v == 'delete') onDelete();
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem<String>(
                        value: 'refresh',
                        child: Row(
                          children: [
                            const Icon(Icons.sync_rounded, size: 20),
                            const SizedBox(width: 12),
                            Text(s.refresh),
                          ],
                        ),
                      ),
                      PopupMenuItem<String>(
                        value: 'delete',
                        child: Row(
                          children: [
                            const Icon(
                              Icons.delete_outline_rounded,
                              size: 20,
                              color: AppColors.error,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              s.delete,
                              style: const TextStyle(color: AppColors.error),
                            ),
                          ],
                        ),
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

/// الحالة الفارغة.
class _PlaylistsEmpty extends StatelessWidget {
  final String title;
  final String hint;
  final String actionLabel;
  final VoidCallback onAction;
  final String disclaimer;

  const _PlaylistsEmpty({
    required this.title,
    required this.hint,
    required this.actionLabel,
    required this.onAction,
    required this.disclaimer,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withOpacity(0.6);
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
              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.add_rounded),
              label: Text(actionLabel),
            ),
            const SizedBox(height: 28),
            Text(
              disclaimer,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: muted.withOpacity(0.7), height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// نافذة إضافة قائمة: رابط، أو ملف، أو Xtream Codes.
class _AddPlaylistSheet extends ConsumerStatefulWidget {
  const _AddPlaylistSheet();

  @override
  ConsumerState<_AddPlaylistSheet> createState() => _AddPlaylistSheetState();
}

class _AddPlaylistSheetState extends ConsumerState<_AddPlaylistSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _url = TextEditingController();
  final _epg = TextEditingController();
  final _server = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();

  int _mode = 0; // 0 رابط، 1 ملف، 2 Xtream
  String? _filePath;
  String _fileName = '';
  bool _busy = false;
  bool _hidePass = true;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _epg.dispose();
    _server.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    try {
      final res = await FilePicker.platform.pickFiles(type: FileType.any);
      final path = res?.files.single.path;
      if (path == null) return;
      setState(() {
        _filePath = path;
        _fileName = path.split('/').last;
        _error = null;
      });
    } catch (_) {
      setState(() => _error = ref.read(stringsProvider).unknownError);
    }
  }

  Future<void> _submit() async {
    final s = ref.read(stringsProvider);
    FocusScope.of(context).unfocus();

    if (_mode == 1 && _filePath == null) {
      setState(() => _error = s.fieldRequired);
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    final notifier = ref.read(playlistsProvider.notifier);
    try {
      switch (_mode) {
        case 0:
          await notifier.addFromUrl(
            name: _name.text,
            url: _url.text,
            epgUrl: _epg.text,
          );
          break;
        case 1:
          await notifier.addFromFile(
            name: _name.text,
            filePath: _filePath!,
            epgUrl: _epg.text,
          );
          break;
        default:
          await notifier.addFromXtream(
            name: _name.text,
            server: _server.text,
            username: _user.text,
            password: _pass.text,
            epgUrl: _epg.text,
          );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _errorText(s, e);
        });
      }
    }
  }

  String? _required(String? v, AppStrings s) =>
      (v == null || v.trim().isEmpty) ? s.fieldRequired : null;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final theme = Theme.of(context);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  s.addPlaylist,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 16),

                SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: 0,
                      icon: const Icon(Icons.link_rounded, size: 18),
                      label: Text(s.fromUrl, maxLines: 1),
                    ),
                    ButtonSegment(
                      value: 1,
                      icon: const Icon(Icons.folder_open_rounded, size: 18),
                      label: Text(s.fromFile, maxLines: 1),
                    ),
                    const ButtonSegment(
                      value: 2,
                      icon: Icon(Icons.dns_rounded, size: 18),
                      label: Text('Xtream', maxLines: 1),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: _busy
                      ? null
                      : (v) => setState(() {
                            _mode = v.first;
                            _error = null;
                          }),
                ),
                const SizedBox(height: 18),

                TextFormField(
                  controller: _name,
                  enabled: !_busy,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(labelText: s.playlistName),
                ),
                const SizedBox(height: 12),

                if (_mode == 0)
                  TextFormField(
                    controller: _url,
                    enabled: !_busy,
                    textDirection: TextDirection.ltr,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.next,
                    validator: (v) => _required(v, s),
                    decoration: InputDecoration(labelText: s.playlistUrl),
                  ),

                if (_mode == 1)
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _pickFile,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                    ),
                    icon: Icon(
                      _filePath == null
                          ? Icons.upload_file_rounded
                          : Icons.check_circle_rounded,
                      color: _filePath == null ? null : AppColors.success,
                    ),
                    label: Text(
                      _filePath == null ? s.pickFile : _fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                if (_mode == 2) ...[
                  TextFormField(
                    controller: _server,
                    enabled: !_busy,
                    textDirection: TextDirection.ltr,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.next,
                    validator: (v) => _required(v, s),
                    decoration: InputDecoration(labelText: s.serverUrl),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _user,
                    enabled: !_busy,
                    textDirection: TextDirection.ltr,
                    autocorrect: false,
                    textInputAction: TextInputAction.next,
                    validator: (v) => _required(v, s),
                    decoration: InputDecoration(labelText: s.username),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _pass,
                    enabled: !_busy,
                    textDirection: TextDirection.ltr,
                    autocorrect: false,
                    obscureText: _hidePass,
                    textInputAction: TextInputAction.next,
                    validator: (v) => _required(v, s),
                    decoration: InputDecoration(
                      labelText: s.password,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _hidePass
                              ? Icons.visibility_rounded
                              : Icons.visibility_off_rounded,
                        ),
                        onPressed: () =>
                            setState(() => _hidePass = !_hidePass),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 12),
                TextFormField(
                  controller: _epg,
                  enabled: !_busy,
                  textDirection: TextDirection.ltr,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(labelText: s.epgUrl),
                ),

                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          color: AppColors.error,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              color: AppColors.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Text(
                                s.importing,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        )
                      : Text(s.add),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
