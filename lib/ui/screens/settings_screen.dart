import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/l10n/strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/constants.dart';
import '../../providers/app_providers.dart';
import '../splash_screen.dart';
import '../widgets/channel_tile.dart';

/// تبويب الإعدادات: اللغة، المظهر، التشغيل، التحكم الأبوي، القنوات المخفية، التخزين، وحول التطبيق.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        duration: const Duration(seconds: 2),
      ));
  }

  // ───────── التسميات ─────────

  String _languageLabel(AppStrings s, String pref) {
    switch (pref) {
      case 'ar':
        return s.languageArabic;
      case 'en':
        return s.languageEnglish;
      default:
        return s.languageSystem;
    }
  }

  String _themeLabel(AppStrings s, String pref) {
    switch (pref) {
      case 'light':
        return s.themeLight;
      case 'system':
        return s.themeSystem;
      default:
        return s.themeDark;
    }
  }

  String _bufferLabel(AppStrings s, BufferPreset b) {
    switch (b) {
      case BufferPreset.small:
        return s.bufferSmall;
      case BufferPreset.medium:
        return s.bufferMedium;
      case BufferPreset.large:
        return s.bufferLarge;
    }
  }

  // ───────── نافذة اختيار عامة ─────────

  Future<T?> _pick<T>({
    required String title,
    required List<(T, String)> options,
    required T current,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  title,
                  style: Theme.of(ctx)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ),
            for (final o in options)
              ListTile(
                title: Text(o.$2),
                trailing: o.$1 == current
                    ? const Icon(Icons.check_circle_rounded,
                        color: AppColors.primary)
                    : null,
                onTap: () => Navigator.of(ctx).pop(o.$1),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ───────── اللغة والمظهر والتشغيل ─────────

  Future<void> _pickLanguage(AppStrings s, SettingsState st) async {
    final v = await _pick<String>(
      title: s.language,
      current: st.language,
      options: [
        ('system', s.languageSystem),
        ('ar', s.languageArabic),
        ('en', s.languageEnglish),
      ],
    );
    if (v != null) await ref.read(settingsProvider.notifier).setLanguage(v);
  }

  Future<void> _pickTheme(AppStrings s, SettingsState st) async {
    final v = await _pick<String>(
      title: s.appearance,
      current: st.theme,
      options: [
        ('dark', s.themeDark),
        ('light', s.themeLight),
        ('system', s.themeSystem),
      ],
    );
    if (v != null) await ref.read(settingsProvider.notifier).setTheme(v);
  }

  Future<void> _pickBuffer(AppStrings s, SettingsState st) async {
    final v = await _pick<BufferPreset>(
      title: s.bufferSize,
      current: st.buffer,
      options: [
        (BufferPreset.small, s.bufferSmall),
        (BufferPreset.medium, s.bufferMedium),
        (BufferPreset.large, s.bufferLarge),
      ],
    );
    if (v != null) await ref.read(settingsProvider.notifier).setBuffer(v);
  }

  // ───────── التحكم الأبوي ─────────

  Future<bool> _verifyPin(AppStrings s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _VerifyPinDialog(
        s: s,
        verify: ref.read(hasPinProvider.notifier).verify,
      ),
    );
    return ok == true;
  }

  Future<bool> _createPin(AppStrings s) async {
    final pin = await showDialog<String>(
      context: context,
      builder: (_) => _NewPinDialog(s: s),
    );
    if (pin == null) return false;
    await ref.read(hasPinProvider.notifier).setPin(pin);
    _toast(s.done);
    return true;
  }

  Future<void> _onPinTap(AppStrings s, bool hasPin) async {
    if (!hasPin) {
      await _createPin(s);
      return;
    }
    if (!await _verifyPin(s)) return;
    if (!mounted) return;
    await _createPin(s);
  }

  Future<void> _onRemovePin(AppStrings s) async {
    if (!await _verifyPin(s)) return;
    await ref.read(hasPinProvider.notifier).remove();
    _toast(s.done);
  }

  Future<void> _onLockedCategories(AppStrings s, bool hasPin) async {
    if (!hasPin) {
      if (!await _createPin(s)) return;
    } else {
      if (!await _verifyPin(s)) return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _LockedCategoriesSheet(),
    );
  }

  // ───────── القنوات المخفية والتخزين ─────────

  Future<void> _openHidden() {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _HiddenSheet(),
    );
  }

  Future<void> _clearCache(AppStrings s) async {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    try {
      final tmp = await getTemporaryDirectory();
      final dir = Directory('${tmp.path}/libCachedImageData');
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
    try {
      await ref.read(storageProvider).clearEpgCache();
    } catch (_) {}
    _toast(s.cacheCleared);
  }

  // ───────── البناء ─────────

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final st = ref.watch(settingsProvider);
    final hasPin = ref.watch(hasPinProvider);
    final lockedCount = ref.watch(lockedCategoriesProvider).length;
    final hiddenCount = ref.watch(hiddenIdsProvider).length;
    final notifier = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withOpacity(0.58);

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.pagePadding,
          12,
          AppConstants.pagePadding,
          28,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Text(
              s.navSettings,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),

          _Section(
            title: s.appearance,
            children: [
              _SettingTile(
                icon: Icons.translate_rounded,
                title: s.language,
                value: _languageLabel(s, st.language),
                onTap: () => _pickLanguage(s, st),
              ),
              _SettingTile(
                icon: Icons.palette_rounded,
                title: s.appearance,
                value: _themeLabel(s, st.theme),
                onTap: () => _pickTheme(s, st),
              ),
            ],
          ),

          _Section(
            title: s.playback,
            children: [
              _SettingTile(
                icon: Icons.speed_rounded,
                title: s.bufferSize,
                value: _bufferLabel(s, st.buffer),
                onTap: () => _pickBuffer(s, st),
              ),
              _SwitchTile(
                icon: Icons.memory_rounded,
                title: s.hardwareDecoding,
                value: st.hardwareDecoding,
                onChanged: notifier.setHardwareDecoding,
              ),
              _SwitchTile(
                icon: Icons.sync_alt_rounded,
                title: s.autoReconnect,
                value: st.autoReconnect,
                onChanged: notifier.setAutoReconnect,
              ),
              _SwitchTile(
                icon: Icons.light_mode_rounded,
                title: s.keepScreenOn,
                value: st.keepScreenOn,
                onChanged: notifier.setKeepScreenOn,
              ),
            ],
          ),

          _Section(
            title: s.parentalControl,
            children: [
              _SettingTile(
                icon: Icons.pin_rounded,
                title: hasPin ? s.changePin : s.setPin,
                onTap: () => _onPinTap(s, hasPin),
              ),
              _SettingTile(
                icon: Icons.lock_rounded,
                title: s.lockedCategories,
                value: hasPin && lockedCount > 0 ? '$lockedCount' : null,
                onTap: () => _onLockedCategories(s, hasPin),
              ),
              if (hasPin)
                _SettingTile(
                  icon: Icons.lock_open_rounded,
                  title: s.removePin,
                  danger: true,
                  onTap: () => _onRemovePin(s),
                ),
            ],
          ),

          _Section(
            title: s.navChannels,
            children: [
              _SettingTile(
                icon: Icons.visibility_off_rounded,
                title: s.hiddenChannels,
                value: hiddenCount > 0 ? '$hiddenCount' : null,
                onTap: _openHidden,
              ),
            ],
          ),

          _Section(
            title: s.storage,
            children: [
              _SettingTile(
                icon: Icons.cleaning_services_rounded,
                title: s.clearCache,
                onTap: () => _clearCache(s),
              ),
            ],
          ),

          _Section(
            title: s.about,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const LumoraLogo(size: 52, glow: false),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.appName,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${s.version} ${AppConstants.appVersion}',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: muted),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            s.tagline,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Text(
                  s.disclaimer,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: muted, height: 1.5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════
// عناصر الواجهة المشتركة
// ═════════════════════════════════════════════

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) items.add(const Divider(height: 1, indent: 66));
      items.add(children[i]);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
            child: Text(
              title,
              style: theme.textTheme.labelLarge?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Material(
            color: scheme.surface,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              side: BorderSide(color: scheme.outline.withOpacity(0.7)),
            ),
            child: Column(children: items),
          ),
        ],
      ),
    );
  }
}

class _IconBox extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _IconBox({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Icon(icon, size: 20, color: color),
    );
  }
}

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? value;
  final VoidCallback? onTap;
  final bool danger;

  const _SettingTile({
    required this.icon,
    required this.title,
    this.value,
    this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.error : AppColors.primary;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final muted = Theme.of(context).colorScheme.onSurface.withOpacity(0.58);

    return ListTile(
      onTap: onTap,
      minVerticalPadding: 12,
      leading: _IconBox(icon: icon, color: color),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: danger ? AppColors.error : null,
        ),
      ),
      subtitle: value == null
          ? null
          : Text(value!, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: onTap == null
          ? null
          : Icon(
              rtl ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
              color: muted,
            ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      secondary: _IconBox(icon: icon, color: AppColors.primary),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ═════════════════════════════════════════════
// نوافذ الرمز
// ═════════════════════════════════════════════

/// يتحقق من الرمز تلقائياً عند إدخال 4 أرقام.
class _VerifyPinDialog extends StatefulWidget {
  final AppStrings s;
  final bool Function(String pin) verify;

  const _VerifyPinDialog({required this.s, required this.verify});

  @override
  State<_VerifyPinDialog> createState() => _VerifyPinDialogState();
}

class _VerifyPinDialogState extends State<_VerifyPinDialog> {
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

/// رمز جديد بحقلين: الرمز وتأكيده.
class _NewPinDialog extends StatefulWidget {
  final AppStrings s;

  const _NewPinDialog({required this.s});

  @override
  State<_NewPinDialog> createState() => _NewPinDialogState();
}

class _NewPinDialogState extends State<_NewPinDialog> {
  final TextEditingController _a = TextEditingController();
  final TextEditingController _b = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  void _save() {
    final s = widget.s;
    if (_a.text.length != AppConstants.pinLength) {
      setState(() => _error = s.pinLength);
      return;
    }
    if (_a.text != _b.text) {
      setState(() => _error = s.pinMismatch);
      return;
    }
    Navigator.of(context).pop(_a.text);
  }

  InputDecoration _decoration(String label) =>
      InputDecoration(labelText: label, counterText: '');

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    const style = TextStyle(fontSize: 24, letterSpacing: 10);

    return AlertDialog(
      title: Text(s.setPin),
      content: Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _a,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: AppConstants.pinLength,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: style,
              decoration: _decoration(s.enterPin),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _b,
              obscureText: true,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: AppConstants.pinLength,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: style,
              decoration: _decoration(s.confirmPin).copyWith(errorText: _error),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _save(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s.cancel),
        ),
        TextButton(onPressed: _save, child: Text(s.save)),
      ],
    );
  }
}

// ═════════════════════════════════════════════
// النوافذ السفلية
// ═════════════════════════════════════════════

/// اختيار التصنيفات المقفلة.
class _LockedCategoriesSheet extends ConsumerWidget {
  const _LockedCategoriesSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final categories = ref.watch(categoriesProvider);
    final locked = ref.watch(lockedCategoriesProvider);
    final theme = Theme.of(context);
    final height = MediaQuery.sizeOf(context).height * 0.7;

    return SafeArea(
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  s.lockedCategories,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ),
            Expanded(
              child: categories.isEmpty
                  ? Center(
                      child: Text(
                        s.noChannels,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.58),
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: categories.length,
                      itemBuilder: (context, i) {
                        final c = categories[i];
                        return SwitchListTile(
                          value: locked.contains(c.key),
                          onChanged: (_) => ref
                              .read(lockedCategoriesProvider.notifier)
                              .toggle(c.key),
                          title: Text(
                            c.isUncategorized ? s.uncategorized : c.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(s.channelsCount(c.count)),
                          secondary: Icon(
                            locked.contains(c.key)
                                ? Icons.lock_rounded
                                : Icons.lock_open_rounded,
                            color: locked.contains(c.key)
                                ? AppColors.primary
                                : theme.colorScheme.onSurface.withOpacity(0.5),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// القنوات المخفية مع إظهار واحدة أو الكل.
class _HiddenSheet extends ConsumerWidget {
  const _HiddenSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final hidden = ref.watch(hiddenChannelsProvider);
    final theme = Theme.of(context);
    final height = MediaQuery.sizeOf(context).height * 0.7;

    return SafeArea(
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      s.hiddenChannels,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  if (hidden.isNotEmpty)
                    TextButton(
                      onPressed: () =>
                          ref.read(hiddenIdsProvider.notifier).unhideAll(),
                      child: Text('${s.unhide} ${s.allChannels}'),
                    ),
                ],
              ),
            ),
            Expanded(
              child: hidden.isEmpty
                  ? Center(
                      child: Text(
                        s.noChannels,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.58),
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: hidden.length,
                      itemBuilder: (context, i) {
                        final c = hidden[i];
                        return ListTile(
                          leading: ChannelLogo(channel: c, size: 42),
                          title: Text(
                            c.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: c.hasGroup
                              ? Text(
                                  c.group,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                )
                              : null,
                          trailing: TextButton(
                            onPressed: () => ref
                                .read(hiddenIdsProvider.notifier)
                                .unhide(c.id),
                            child: Text(s.unhide),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
