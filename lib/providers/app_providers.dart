import 'dart:ui' show PlatformDispatcher;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/l10n/strings.dart';
import '../core/utils/constants.dart';
import '../data/models/channel.dart';
import '../data/models/playlist.dart';
import '../data/services/playlist_service.dart';
import '../data/services/storage_service.dart';

// ═════════════════════════════════════════════
// أدوات مساعدة
// ═════════════════════════════════════════════

final RegExp _arabicRe = RegExp(r'[\u0600-\u06FF]');

bool hasArabic(String s) => _arabicRe.hasMatch(s);

/// مفتاح تصنيف القناة.
String categoryKeyOf(Channel c) {
  final g = c.group.trim();
  return g.isEmpty ? AppConstants.uncategorizedKey : g;
}

/// يوحّد النص للبحث: أحرف صغيرة، بلا تشكيل، وتوحيد الألف والياء والتاء المربوطة.
String normalizeSearch(String s) {
  final b = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    if ((r >= 0x064B && r <= 0x065F) || r == 0x0640 || r == 0x0670) continue;
    if (r == 0x0622 || r == 0x0623 || r == 0x0625) {
      b.writeCharCode(0x0627);
    } else if (r == 0x0649) {
      b.writeCharCode(0x064A);
    } else if (r == 0x0629) {
      b.writeCharCode(0x0647);
    } else {
      b.writeCharCode(r);
    }
  }
  return b.toString().trim();
}

class CategoryInfo {
  final String key;
  final String name; // فارغ للتصنيف "بدون تصنيف"
  final int count;
  const CategoryInfo({required this.key, required this.name, required this.count});

  bool get isUncategorized => key == AppConstants.uncategorizedKey;
}

// ═════════════════════════════════════════════
// الأساس
// ═════════════════════════════════════════════

/// يُستبدل في main.dart بعد تهيئة التخزين.
final storageProvider = Provider<StorageService>(
  (ref) => throw UnimplementedError('storageProvider must be overridden in main.dart'),
);

final playlistServiceProvider = Provider<PlaylistService>((ref) {
  final service = PlaylistService(ref.watch(storageProvider));
  ref.onDispose(service.dispose);
  return service;
});

/// حالة الاتصال بالإنترنت.
final isOnlineProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  bool online(List<ConnectivityResult> r) =>
      r.any((e) => e != ConnectivityResult.none);
  yield online(await connectivity.checkConnectivity());
  await for (final r in connectivity.onConnectivityChanged) {
    yield online(r);
  }
});

// ═════════════════════════════════════════════
// الإعدادات واللغة والمظهر
// ═════════════════════════════════════════════

class SettingsState {
  final String language; // system | ar | en
  final String theme; // system | dark | light
  final BufferPreset buffer;
  final AspectMode aspect;
  final bool hardwareDecoding;
  final bool autoReconnect;
  final bool keepScreenOn;

  const SettingsState({
    required this.language,
    required this.theme,
    required this.buffer,
    required this.aspect,
    required this.hardwareDecoding,
    required this.autoReconnect,
    required this.keepScreenOn,
  });

  SettingsState copyWith({
    String? language,
    String? theme,
    BufferPreset? buffer,
    AspectMode? aspect,
    bool? hardwareDecoding,
    bool? autoReconnect,
    bool? keepScreenOn,
  }) {
    return SettingsState(
      language: language ?? this.language,
      theme: theme ?? this.theme,
      buffer: buffer ?? this.buffer,
      aspect: aspect ?? this.aspect,
      hardwareDecoding: hardwareDecoding ?? this.hardwareDecoding,
      autoReconnect: autoReconnect ?? this.autoReconnect,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
    );
  }
}

class SettingsNotifier extends Notifier<SettingsState> {
  StorageService get _s => ref.read(storageProvider);

  @override
  SettingsState build() {
    final s = _s;
    return SettingsState(
      language: s.language,
      theme: s.theme,
      buffer: BufferPreset.fromKey(s.buffer),
      aspect: AspectMode.fromKey(s.aspect),
      hardwareDecoding: s.hardwareDecoding,
      autoReconnect: s.autoReconnect,
      keepScreenOn: s.keepScreenOn,
    );
  }

  Future<void> setLanguage(String v) async {
    state = state.copyWith(language: v);
    await _s.setLanguage(v);
  }

  Future<void> setTheme(String v) async {
    state = state.copyWith(theme: v);
    await _s.setTheme(v);
  }

  Future<void> setBuffer(BufferPreset v) async {
    state = state.copyWith(buffer: v);
    await _s.setBuffer(v.key);
  }

  Future<void> setAspect(AspectMode v) async {
    state = state.copyWith(aspect: v);
    await _s.setAspect(v.key);
  }

  Future<void> setHardwareDecoding(bool v) async {
    state = state.copyWith(hardwareDecoding: v);
    await _s.setHardwareDecoding(v);
  }

  Future<void> setAutoReconnect(bool v) async {
    state = state.copyWith(autoReconnect: v);
    await _s.setAutoReconnect(v);
  }

  Future<void> setKeepScreenOn(bool v) async {
    state = state.copyWith(keepScreenOn: v);
    await _s.setKeepScreenOn(v);
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, SettingsState>(SettingsNotifier.new);

/// لغة الجهاز؛ يحدّثها main.dart عند تغيّرها أثناء التشغيل.
final deviceLanguageProvider = StateProvider<String>(
  (ref) => PlatformDispatcher.instance.locale.languageCode,
);

/// لغة العرض الفعلية: ar أو en.
final languageCodeProvider = Provider<String>((ref) {
  final pref = ref.watch(settingsProvider.select((s) => s.language));
  final device = ref.watch(deviceLanguageProvider);
  return AppStrings.resolveCode(pref, device);
});

final stringsProvider =
    Provider<AppStrings>((ref) => AppStrings.of(ref.watch(languageCodeProvider)));

final themeModeProvider = Provider<ThemeMode>((ref) {
  switch (ref.watch(settingsProvider.select((s) => s.theme))) {
    case 'light':
      return ThemeMode.light;
    case 'system':
      return ThemeMode.system;
    default:
      return ThemeMode.dark;
  }
});

// ═════════════════════════════════════════════
// قوائم التشغيل
// ═════════════════════════════════════════════

final importingProvider = StateProvider<bool>((ref) => false);
final refreshingIdsProvider = StateProvider<Set<String>>((ref) => <String>{});

/// القائمة النشطة. null تعني عرض قنوات كل القوائم.
class ActivePlaylistNotifier extends Notifier<String?> {
  @override
  String? build() => ref.read(storageProvider).activePlaylistId;

  Future<void> select(String? id) async {
    state = id;
    ref.read(selectedCategoryProvider.notifier).set(AppConstants.allCategoryKey);
    await ref.read(storageProvider).setActivePlaylistId(id);
  }
}

final activePlaylistIdProvider =
    NotifierProvider<ActivePlaylistNotifier, String?>(ActivePlaylistNotifier.new);

class PlaylistsNotifier extends Notifier<List<Playlist>> {
  StorageService get _storage => ref.read(storageProvider);
  PlaylistService get _service => ref.read(playlistServiceProvider);

  @override
  List<Playlist> build() => _storage.getPlaylists();

  void _reload() => state = _storage.getPlaylists();

  Future<Playlist> _runImport(Future<Playlist> Function() job) async {
    final flag = ref.read(importingProvider.notifier);
    flag.state = true;
    try {
      final p = await job();
      _reload();
      await ref.read(activePlaylistIdProvider.notifier).select(p.id);
      return p;
    } finally {
      flag.state = false;
    }
  }

  Future<Playlist> addFromUrl({
    required String name,
    required String url,
    String epgUrl = '',
  }) =>
      _runImport(() => _service.addFromUrl(name: name, url: url, epgUrl: epgUrl));

  Future<Playlist> addFromFile({
    required String name,
    required String filePath,
    String epgUrl = '',
  }) =>
      _runImport(() =>
          _service.addFromFile(name: name, filePath: filePath, epgUrl: epgUrl));

  Future<Playlist> addFromXtream({
    required String name,
    required String server,
    required String username,
    required String password,
    String epgUrl = '',
  }) =>
      _runImport(() => _service.addFromXtream(
            name: name,
            server: server,
            username: username,
            password: password,
            epgUrl: epgUrl,
          ));

  Future<void> refresh(Playlist p) async {
    final ids = ref.read(refreshingIdsProvider.notifier);
    ids.state = {...ids.state, p.id};
    try {
      await _service.refresh(p);
      _reload();
    } finally {
      ids.state = ids.state.where((e) => e != p.id).toSet();
    }
  }

  /// يحدّث كل القوائم ويعيد عدد التي نجحت.
  Future<int> refreshAll() async {
    var ok = 0;
    for (final p in List<Playlist>.of(state)) {
      try {
        await refresh(p);
        ok++;
      } catch (_) {}
    }
    return ok;
  }

  Future<void> delete(Playlist p) async {
    await _service.delete(p);
    _reload();

    if (ref.read(activePlaylistIdProvider) == p.id) {
      await ref
          .read(activePlaylistIdProvider.notifier)
          .select(state.isEmpty ? null : state.first.id);
    }
    // التخزين نظّف بيانات القائمة، فنعيد قراءتها.
    ref.invalidate(favoritesProvider);
    ref.invalidate(recentsProvider);
    ref.invalidate(hiddenIdsProvider);
  }
}

final playlistsProvider =
    NotifierProvider<PlaylistsNotifier, List<Playlist>>(PlaylistsNotifier.new);

// ═════════════════════════════════════════════
// المفضلة والأخيرة والمخفية
// ═════════════════════════════════════════════

class FavoritesNotifier extends Notifier<List<Channel>> {
  @override
  List<Channel> build() => ref.read(storageProvider).getFavorites();

  /// يعيد true إن أصبحت القناة مفضلة.
  Future<bool> toggle(Channel c) async {
    final storage = ref.read(storageProvider);
    final nowFav = await storage.toggleFavorite(c);
    state = storage.getFavorites();
    return nowFav;
  }
}

final favoritesProvider =
    NotifierProvider<FavoritesNotifier, List<Channel>>(FavoritesNotifier.new);

final favoriteIdsProvider = Provider<Set<String>>(
  (ref) => ref.watch(favoritesProvider).map((c) => c.id).toSet(),
);

class RecentsNotifier extends Notifier<List<Channel>> {
  @override
  List<Channel> build() => ref.read(storageProvider).getRecents();

  Future<void> add(Channel c) async {
    final storage = ref.read(storageProvider);
    await storage.addRecent(c);
    state = storage.getRecents();
  }

  Future<void> clear() async {
    await ref.read(storageProvider).clearRecents();
    state = <Channel>[];
  }
}

final recentsProvider =
    NotifierProvider<RecentsNotifier, List<Channel>>(RecentsNotifier.new);

class HiddenIdsNotifier extends Notifier<Set<String>> {
  StorageService get _s => ref.read(storageProvider);

  @override
  Set<String> build() => _s.hiddenIds;

  Future<void> hide(Channel c) async {
    state = {...state, c.id};
    await _s.hideChannel(c);
  }

  Future<void> unhide(String id) async {
    state = state.where((e) => e != id).toSet();
    await _s.unhideChannel(id);
  }

  Future<void> unhideAll() async {
    state = <String>{};
    await _s.unhideAll();
  }
}

final hiddenIdsProvider =
    NotifierProvider<HiddenIdsNotifier, Set<String>>(HiddenIdsNotifier.new);

// ═════════════════════════════════════════════
// التحكم الأبوي
// ═════════════════════════════════════════════

class PinNotifier extends Notifier<bool> {
  StorageService get _s => ref.read(storageProvider);

  @override
  bool build() => _s.hasPin;

  Future<void> setPin(String pin) async {
    await _s.setPin(pin);
    state = true;
  }

  bool verify(String pin) => _s.verifyPin(pin);

  Future<void> remove() async {
    await _s.removePin();
    state = false;
    ref.invalidate(lockedCategoriesProvider);
    ref.read(unlockedCategoriesProvider.notifier).lockAll();
  }
}

/// هل يوجد رمز PIN؟
final hasPinProvider = NotifierProvider<PinNotifier, bool>(PinNotifier.new);

class LockedCategoriesNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => ref.read(storageProvider).lockedCategories;

  Future<void> toggle(String key) async {
    final next = {...state};
    if (!next.remove(key)) next.add(key);
    state = next;
    await ref.read(storageProvider).setLockedCategories(next);
  }
}

final lockedCategoriesProvider =
    NotifierProvider<LockedCategoriesNotifier, Set<String>>(
        LockedCategoriesNotifier.new);

/// التصنيفات المفتوحة مؤقتاً في هذه الجلسة فقط.
class UnlockedCategoriesNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => <String>{};

  void unlock(String key) => state = {...state, key};
  void lockAll() => state = <String>{};
}

final unlockedCategoriesProvider =
    NotifierProvider<UnlockedCategoriesNotifier, Set<String>>(
        UnlockedCategoriesNotifier.new);

// ═════════════════════════════════════════════
// القنوات والتصنيفات والبحث
// ═════════════════════════════════════════════

/// قنوات القائمة النشطة (أو كل القوائم). تُقرأ مرة واحدة وتُخزَّن حتى تتغير القوائم.
final allChannelsProvider = Provider<List<Channel>>((ref) {
  final storage = ref.watch(storageProvider);
  final playlists = ref.watch(playlistsProvider);
  final activeId = ref.watch(activePlaylistIdProvider);

  if (activeId != null && playlists.any((p) => p.id == activeId)) {
    return storage.getChannels(activeId);
  }
  final out = <Channel>[];
  for (final p in playlists) {
    out.addAll(storage.getChannels(p.id));
  }
  return out;
});

/// القنوات بعد استبعاد المخفية.
final visibleChannelsProvider = Provider<List<Channel>>((ref) {
  final all = ref.watch(allChannelsProvider);
  final hidden = ref.watch(hiddenIdsProvider);
  if (hidden.isEmpty) return all;
  return all.where((c) => !hidden.contains(c.id)).toList();
});

/// القنوات المخفية (لشاشة الإعدادات).
final hiddenChannelsProvider = Provider<List<Channel>>((ref) {
  final all = ref.watch(allChannelsProvider);
  final hidden = ref.watch(hiddenIdsProvider);
  if (hidden.isEmpty) return const <Channel>[];
  return all.where((c) => hidden.contains(c.id)).toList();
});

/// فهرس بحث جاهز: معرّف القناة ← الاسم والتصنيف بعد التوحيد.
final searchIndexProvider = Provider<Map<String, String>>((ref) {
  final channels = ref.watch(visibleChannelsProvider);
  return {
    for (final c in channels) c.id: normalizeSearch('${c.name} ${c.group}'),
  };
});

/// التصنيفات مرتبة بأولوية لغة التطبيق:
/// العربية أولاً عند اللغة العربية، وغير العربية أولاً عند الإنجليزية.
final categoriesProvider = Provider<List<CategoryInfo>>((ref) {
  final channels = ref.watch(visibleChannelsProvider);
  final arabicFirst = ref.watch(languageCodeProvider) == 'ar';

  final counts = <String, int>{};
  for (final c in channels) {
    final k = categoryKeyOf(c);
    counts[k] = (counts[k] ?? 0) + 1;
  }

  final list = counts.entries
      .map((e) => CategoryInfo(
            key: e.key,
            name: e.key == AppConstants.uncategorizedKey ? '' : e.key,
            count: e.value,
          ))
      .toList();

  int rank(CategoryInfo c) {
    if (c.isUncategorized) return 2;
    return hasArabic(c.name) == arabicFirst ? 0 : 1;
  }

  list.sort((a, b) {
    final r = rank(a).compareTo(rank(b));
    if (r != 0) return r;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return list;
});

class SelectedCategoryNotifier extends Notifier<String> {
  @override
  String build() => AppConstants.allCategoryKey;

  void set(String key) => state = key;
}

final selectedCategoryProvider =
    NotifierProvider<SelectedCategoryNotifier, String>(SelectedCategoryNotifier.new);

class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String q) => state = q;
}

final searchQueryProvider =
    NotifierProvider<SearchQueryNotifier, String>(SearchQueryNotifier.new);

/// هل التصنيف المحدد مقفل ولم يُفتح بعد؟
final selectedCategoryLockedProvider = Provider<bool>((ref) {
  final key = ref.watch(selectedCategoryProvider);
  if (key == AppConstants.allCategoryKey || key == AppConstants.recentCategoryKey) {
    return false;
  }
  final locked = ref.watch(lockedCategoriesProvider);
  final unlocked = ref.watch(unlockedCategoriesProvider);
  return locked.contains(key) && !unlocked.contains(key);
});

/// القائمة المعروضة فعلياً: حسب التصنيف والبحث والقفل الأبوي.
final displayedChannelsProvider = Provider<List<Channel>>((ref) {
  final selected = ref.watch(selectedCategoryProvider);
  final query = normalizeSearch(ref.watch(searchQueryProvider));
  final locked = ref.watch(lockedCategoriesProvider);
  final unlocked = ref.watch(unlockedCategoriesProvider);
  final hidden = ref.watch(hiddenIdsProvider);

  List<Channel> base;
  if (selected == AppConstants.recentCategoryKey) {
    base = ref.watch(recentsProvider).where((c) => !hidden.contains(c.id)).toList();
  } else {
    final visible = ref.watch(visibleChannelsProvider);
    base = selected == AppConstants.allCategoryKey
        ? visible
        : visible.where((c) => categoryKeyOf(c) == selected).toList();
  }

  // القنوات في تصنيفات مقفلة لا تظهر إلا بعد إدخال الرمز.
  if (locked.isNotEmpty) {
    base = base.where((c) {
      final k = categoryKeyOf(c);
      return !locked.contains(k) || unlocked.contains(k);
    }).toList();
  }

  if (query.isEmpty) return base;

  final index = ref.watch(searchIndexProvider);
  return base.where((c) => (index[c.id] ?? '').contains(query)).toList();
});
