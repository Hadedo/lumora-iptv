import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/utils/constants.dart';
import '../models/channel.dart';
import '../models/playlist.dart';

/// طبقة التخزين المحلي (Hive). كل القيم خرائط وقوائم بسيطة، بلا مولّدات كود.
/// تُهيَّأ مرة واحدة في main.dart ثم تُمرَّر عبر Riverpod.
class StorageService {
  final Box<dynamic> _settings;
  final Box<dynamic> _playlists;
  final Box<dynamic> _channels;
  final Box<dynamic> _favorites;
  final Box<dynamic> _recents;
  final Box<dynamic> _hidden;
  final Box<dynamic> _epg;

  StorageService._(
    this._settings,
    this._playlists,
    this._channels,
    this._favorites,
    this._recents,
    this._hidden,
    this._epg,
  );

  /// يفتح كل الصناديق. إن تلف صندوق يُعاد إنشاؤه بدل أن يتعطل التطبيق.
  static Future<StorageService> init() async {
    await Hive.initFlutter();
    return StorageService._(
      await _open(AppConstants.boxSettings),
      await _open(AppConstants.boxPlaylists),
      await _open(AppConstants.boxChannels),
      await _open(AppConstants.boxFavorites),
      await _open(AppConstants.boxRecents),
      await _open(AppConstants.boxHidden),
      await _open(AppConstants.boxEpg),
    );
  }

  static Future<Box<dynamic>> _open(String name) async {
    try {
      return await Hive.openBox<dynamic>(name);
    } catch (_) {
      await Hive.deleteBoxFromDisk(name);
      return Hive.openBox<dynamic>(name);
    }
  }

  // ═════════════ الإعدادات ═════════════

  String get language =>
      _settings.get(AppConstants.keyLanguage, defaultValue: AppConstants.defaultLanguage) as String;
  Future<void> setLanguage(String v) => _settings.put(AppConstants.keyLanguage, v);

  String get theme =>
      _settings.get(AppConstants.keyTheme, defaultValue: AppConstants.defaultTheme) as String;
  Future<void> setTheme(String v) => _settings.put(AppConstants.keyTheme, v);

  String get buffer =>
      _settings.get(AppConstants.keyBuffer, defaultValue: AppConstants.defaultBuffer) as String;
  Future<void> setBuffer(String v) => _settings.put(AppConstants.keyBuffer, v);

  String get aspect =>
      _settings.get(AppConstants.keyAspect, defaultValue: AppConstants.defaultAspect) as String;
  Future<void> setAspect(String v) => _settings.put(AppConstants.keyAspect, v);

  bool get hardwareDecoding => _settings.get(
        AppConstants.keyHardwareDecoding,
        defaultValue: AppConstants.defaultHardwareDecoding,
      ) as bool;
  Future<void> setHardwareDecoding(bool v) =>
      _settings.put(AppConstants.keyHardwareDecoding, v);

  bool get autoReconnect => _settings.get(
        AppConstants.keyAutoReconnect,
        defaultValue: AppConstants.defaultAutoReconnect,
      ) as bool;
  Future<void> setAutoReconnect(bool v) =>
      _settings.put(AppConstants.keyAutoReconnect, v);

  bool get keepScreenOn => _settings.get(
        AppConstants.keyKeepScreenOn,
        defaultValue: AppConstants.defaultKeepScreenOn,
      ) as bool;
  Future<void> setKeepScreenOn(bool v) =>
      _settings.put(AppConstants.keyKeepScreenOn, v);

  String? get activePlaylistId =>
      _settings.get(AppConstants.keyActivePlaylist) as String?;
  Future<void> setActivePlaylistId(String? id) => id == null
      ? _settings.delete(AppConstants.keyActivePlaylist)
      : _settings.put(AppConstants.keyActivePlaylist, id);

  String? get lastChannelId =>
      _settings.get(AppConstants.keyLastChannel) as String?;
  Future<void> setLastChannelId(String id) =>
      _settings.put(AppConstants.keyLastChannel, id);

  // ═════════════ التحكم الأبوي ═════════════

  static String _hashPin(String pin) =>
      sha256.convert(utf8.encode('lumora|$pin')).toString();

  bool get hasPin => _settings.containsKey(AppConstants.keyPinHash);

  Future<void> setPin(String pin) =>
      _settings.put(AppConstants.keyPinHash, _hashPin(pin));

  bool verifyPin(String pin) =>
      _settings.get(AppConstants.keyPinHash) == _hashPin(pin);

  /// إزالة الرمز تزيل أيضاً قفل كل التصنيفات.
  Future<void> removePin() async {
    await _settings.delete(AppConstants.keyPinHash);
    await _settings.delete(AppConstants.keyLockedCategories);
  }

  Set<String> get lockedCategories {
    final raw = _settings.get(AppConstants.keyLockedCategories);
    if (raw is List) return raw.map((e) => e.toString()).toSet();
    return <String>{};
  }

  Future<void> setLockedCategories(Set<String> categories) =>
      _settings.put(AppConstants.keyLockedCategories, categories.toList());

  // ═════════════ قوائم التشغيل ═════════════

  List<Playlist> getPlaylists() {
    final list = <Playlist>[];
    for (final key in _playlists.keys) {
      final raw = _playlists.get(key);
      if (raw is Map) list.add(Playlist.fromMap(raw));
    }
    list.sort((a, b) => a.id.compareTo(b.id));
    return list;
  }

  Future<void> savePlaylist(Playlist p) => _playlists.put(p.id, p.toMap());

  /// يحذف القائمة وكل ما يخصها: القنوات والمفضلة والأخيرة والمخفية والدليل.
  Future<void> deletePlaylist(String playlistId) async {
    await _playlists.delete(playlistId);
    await _channels.delete(playlistId);
    await _epg.delete(playlistId);

    final favKeys = _favorites.keys.where((k) {
      final v = _favorites.get(k);
      return v is Map && v['p'] == playlistId;
    }).toList();
    await _favorites.deleteAll(favKeys);

    final hiddenKeys = _hidden.keys.where((k) {
      final v = _hidden.get(k);
      return v == playlistId;
    }).toList();
    await _hidden.deleteAll(hiddenKeys);

    final recents = getRecents().where((c) => c.playlistId != playlistId).toList();
    await _saveRecents(recents);

    if (activePlaylistId == playlistId) await setActivePlaylistId(null);
  }

  // ═════════════ القنوات ═════════════

  Future<void> saveChannels(String playlistId, List<Channel> channels) =>
      _channels.put(playlistId, channels.map((c) => c.toMap()).toList());

  List<Channel> getChannels(String playlistId) {
    final raw = _channels.get(playlistId);
    if (raw is! List) return <Channel>[];
    final out = <Channel>[];
    for (final item in raw) {
      if (item is Map) out.add(Channel.fromMap(item));
    }
    return out;
  }

  /// قنوات كل القوائم معاً.
  List<Channel> getAllChannels() {
    final out = <Channel>[];
    for (final key in _channels.keys) {
      out.addAll(getChannels(key as String));
    }
    return out;
  }

  // ═════════════ المفضلة ═════════════
  // نخزن القناة كاملة حتى تبقى المفضلة سليمة عند تحديث القائمة.

  bool isFavorite(String channelId) => _favorites.containsKey(channelId);

  Set<String> get favoriteIds => _favorites.keys.map((k) => k.toString()).toSet();

  List<Channel> getFavorites() {
    final out = <Channel>[];
    for (final key in _favorites.keys) {
      final raw = _favorites.get(key);
      if (raw is Map) out.add(Channel.fromMap(raw));
    }
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  /// يبدّل حالة المفضلة ويعيد true إن أصبحت القناة مفضلة.
  Future<bool> toggleFavorite(Channel c) async {
    if (_favorites.containsKey(c.id)) {
      await _favorites.delete(c.id);
      return false;
    }
    await _favorites.put(c.id, c.toMap());
    return true;
  }

  // ═════════════ آخر مشاهدة ═════════════

  List<Channel> getRecents() {
    final raw = _recents.get('list');
    if (raw is! List) return <Channel>[];
    final out = <Channel>[];
    for (final item in raw) {
      if (item is Map) out.add(Channel.fromMap(item));
    }
    return out;
  }

  Future<void> _saveRecents(List<Channel> list) =>
      _recents.put('list', list.map((c) => c.toMap()).toList());

  Future<void> addRecent(Channel c) async {
    final list = getRecents()..removeWhere((e) => e.id == c.id);
    list.insert(0, c);
    if (list.length > AppConstants.maxRecents) {
      list.removeRange(AppConstants.maxRecents, list.length);
    }
    await _saveRecents(list);
    await setLastChannelId(c.id);
  }

  Future<void> clearRecents() => _recents.delete('list');

  // ═════════════ القنوات المخفية ═════════════
  // القيمة المخزنة هي معرّف القائمة، ليسهل تنظيفها عند الحذف.

  Set<String> get hiddenIds => _hidden.keys.map((k) => k.toString()).toSet();

  Future<void> hideChannel(Channel c) => _hidden.put(c.id, c.playlistId);

  Future<void> unhideChannel(String channelId) => _hidden.delete(channelId);

  Future<void> unhideAll() => _hidden.clear();

  // ═════════════ دليل البرامج (نص خام مخزَّن مؤقتاً) ═════════════

  String? getEpgCache(String playlistId) => _epg.get(playlistId) as String?;

  Future<void> saveEpgCache(String playlistId, String json) =>
      _epg.put(playlistId, json);

  Future<void> clearEpgCache() => _epg.clear();
}
