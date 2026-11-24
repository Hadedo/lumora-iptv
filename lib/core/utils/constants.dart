/// ثوابت لُمورا: أسماء التخزين، المفاتيح، الإعدادات الافتراضية، المهلات.
/// ملف مستقل بلا أي اعتماد على ملفات أخرى.
class AppConstants {
  AppConstants._();

  // ───────── التطبيق ─────────
  static const String appName = 'Lumora';
  static const String appVersion = '1.0.0';

  // بعض الخوادم ترفض الوكلاء المجهولين، لذا نستخدم وكيلاً شائعاً للبث.
  static const String streamUserAgent = 'VLC/3.0.20 LibVLC/3.0.20';
  static const String apiUserAgent = 'Lumora/1.0 (Android)';

  // ───────── صناديق Hive ─────────
  static const String boxSettings = 'settings';
  static const String boxPlaylists = 'playlists';
  static const String boxChannels = 'channels';
  static const String boxFavorites = 'favorites';
  static const String boxRecents = 'recents';
  static const String boxHidden = 'hidden';
  static const String boxEpg = 'epg';

  // ───────── مفاتيح الإعدادات ─────────
  static const String keyLanguage = 'language'; // system | ar | en
  static const String keyTheme = 'theme'; // system | dark | light
  static const String keyBuffer = 'buffer'; // small | medium | large
  static const String keyHardwareDecoding = 'hw_decoding';
  static const String keyAutoReconnect = 'auto_reconnect';
  static const String keyKeepScreenOn = 'keep_screen_on';
  static const String keyAspect = 'aspect'; // fit | fill | stretch
  static const String keyPinHash = 'pin_hash';
  static const String keyLockedCategories = 'locked_categories';
  static const String keyActivePlaylist = 'active_playlist';
  static const String keyLastChannel = 'last_channel';

  // ───────── القيم الافتراضية ─────────
  static const String defaultLanguage = 'system';
  static const String defaultTheme = 'dark';
  static const String defaultBuffer = 'medium';
  static const String defaultAspect = 'fit';
  static const bool defaultHardwareDecoding = true;
  static const bool defaultAutoReconnect = true;
  static const bool defaultKeepScreenOn = true;

  // ───────── الشبكة ─────────
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 60);
  static const Duration playlistDownloadTimeout = Duration(minutes: 3);
  static const int networkRetries = 3;
  static const Duration retryBaseDelay = Duration(milliseconds: 700);

  // ───────── المشغّل ─────────
  static const int maxReconnectAttempts = 6;
  static const Duration reconnectBaseDelay = Duration(seconds: 2);
  static const Duration reconnectMaxDelay = Duration(seconds: 15);
  static const Duration controlsAutoHide = Duration(seconds: 4);
  static const Duration bufferingTimeout = Duration(seconds: 20);
  static const double gestureSensitivity = 1.4;

  // ───────── القنوات والقوائم ─────────
  static const int maxRecents = 30;
  static const int pinLength = 4;
  static const String allCategoryKey = '__all__';
  static const String recentCategoryKey = '__recent__';
  static const String uncategorizedKey = '__none__';

  // ───────── الواجهة ─────────
  static const Duration animFast = Duration(milliseconds: 160);
  static const Duration animNormal = Duration(milliseconds: 260);
  static const double logoSize = 52;
  static const int logoCacheWidth = 160;
  static const double pagePadding = 16;

  // ───────── M3U ─────────
  static const String attrId = 'tvg-id';
  static const String attrName = 'tvg-name';
  static const String attrLogo = 'tvg-logo';
  static const String attrGroup = 'group-title';
  static const String attrEpg = 'x-tvg-url';

  // ───────── Xtream Codes ─────────
  static const String xtreamApiPath = 'player_api.php';
  static const String xtreamPlaylistPath = 'get.php';
  static const String xtreamEpgPath = 'xmltv.php';
}

/// خيارات حجم التخزين المؤقت للمشغّل.
enum BufferPreset {
  small('small', 8 * 1024 * 1024, 5),
  medium('medium', 32 * 1024 * 1024, 15),
  large('large', 96 * 1024 * 1024, 40);

  const BufferPreset(this.key, this.bytes, this.seconds);

  /// المفتاح المحفوظ في الإعدادات.
  final String key;

  /// حجم الذاكرة المؤقتة بالبايت.
  final int bytes;

  /// مدة التخزين المسبق بالثواني.
  final int seconds;

  static BufferPreset fromKey(String? key) {
    for (final p in BufferPreset.values) {
      if (p.key == key) return p;
    }
    return BufferPreset.medium;
  }
}

/// أبعاد عرض الفيديو.
enum AspectMode {
  fit('fit'),
  fill('fill'),
  stretch('stretch');

  const AspectMode(this.key);
  final String key;

  static AspectMode fromKey(String? key) {
    for (final m in AspectMode.values) {
      if (m.key == key) return m;
    }
    return AspectMode.fit;
  }

  AspectMode get next => AspectMode.values[(index + 1) % AspectMode.values.length];
}
