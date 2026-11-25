import '../../core/utils/constants.dart';

/// نوع مصدر القائمة.
enum PlaylistType {
  url('url'),
  file('file'),
  xtream('xtream');

  const PlaylistType(this.key);
  final String key;

  static PlaylistType fromKey(String? key) {
    for (final t in PlaylistType.values) {
      if (t.key == key) return t;
    }
    return PlaylistType.url;
  }
}

/// نموذج قائمة التشغيل (M3U من رابط أو ملف، أو Xtream Codes).
class Playlist {
  final String id;
  final String name;
  final PlaylistType type;

  /// رابط M3U، أو مسار الملف المحلي، أو عنوان خادم Xtream.
  final String source;

  /// بيانات Xtream فقط.
  final String username;
  final String password;

  /// رابط دليل البرامج (XMLTV) اختياري.
  final String epgUrl;

  final int channelCount;

  /// وقت آخر تحديث بالميلي ثانية، و0 تعني لم تُحدَّث بعد.
  final int updatedAt;

  const Playlist({
    required this.id,
    required this.name,
    required this.type,
    required this.source,
    this.username = '',
    this.password = '',
    this.epgUrl = '',
    this.channelCount = 0,
    this.updatedAt = 0,
  });

  /// ينشئ قائمة جديدة بمعرّف فريد مبني على الوقت.
  factory Playlist.create({
    required String name,
    required PlaylistType type,
    required String source,
    String username = '',
    String password = '',
    String epgUrl = '',
  }) {
    final now = DateTime.now().microsecondsSinceEpoch;
    return Playlist(
      id: now.toRadixString(36),
      name: name.trim(),
      type: type,
      source: type == PlaylistType.xtream ? normalizeServer(source) : source.trim(),
      username: username.trim(),
      password: password.trim(),
      epgUrl: epgUrl.trim(),
    );
  }

  bool get isXtream => type == PlaylistType.xtream;
  bool get isFile => type == PlaylistType.file;
  bool get isUrl => type == PlaylistType.url;
  bool get hasBeenUpdated => updatedAt > 0;

  DateTime? get updatedDate =>
      updatedAt > 0 ? DateTime.fromMillisecondsSinceEpoch(updatedAt) : null;

  // ───────── روابط Xtream Codes ─────────

  /// يضيف http:// عند غيابه ويزيل الشرطة الأخيرة والمسارات الزائدة.
  static String normalizeServer(String input) {
    var s = input.trim();
    if (s.isEmpty) return s;
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      s = 'http://$s';
    }
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  Uri _xtreamUri(String path, [Map<String, String> extra = const {}]) {
    final base = Uri.parse(source);
    final basePath = base.path.endsWith('/') ? base.path : '${base.path}/';
    return base.replace(
      path: '$basePath$path',
      queryParameters: {
        'username': username,
        'password': password,
        ...extra,
      },
    );
  }

  /// رابط التحقق من الحساب.
  Uri get xtreamAuthUri => _xtreamUri(AppConstants.xtreamApiPath);

  /// رابط قائمة M3U الكاملة.
  Uri get xtreamPlaylistUri => _xtreamUri(
        AppConstants.xtreamPlaylistPath,
        {'type': 'm3u_plus', 'output': 'ts'},
      );

  /// رابط دليل البرامج: المخصص إن وُجد، وإلا الافتراضي لـ Xtream.
  String get effectiveEpgUrl {
    if (epgUrl.isNotEmpty) return epgUrl;
    if (isXtream) return _xtreamUri(AppConstants.xtreamEpgPath).toString();
    return '';
  }

  /// الرابط الذي تُحمَّل منه القائمة (للنوعين url وxtream).
  String get downloadUrl =>
      isXtream ? xtreamPlaylistUri.toString() : source;

  Playlist copyWith({
    String? name,
    String? source,
    String? username,
    String? password,
    String? epgUrl,
    int? channelCount,
    int? updatedAt,
  }) {
    return Playlist(
      id: id,
      name: name ?? this.name,
      type: type,
      source: source ?? this.source,
      username: username ?? this.username,
      password: password ?? this.password,
      epgUrl: epgUrl ?? this.epgUrl,
      channelCount: channelCount ?? this.channelCount,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type.key,
      'source': source,
      'username': username,
      'password': password,
      'epg': epgUrl,
      'count': channelCount,
      'updated': updatedAt,
    };
  }

  factory Playlist.fromMap(Map<dynamic, dynamic> m) {
    return Playlist(
      id: (m['id'] ?? '') as String,
      name: (m['name'] ?? '') as String,
      type: PlaylistType.fromKey(m['type'] as String?),
      source: (m['source'] ?? '') as String,
      username: (m['username'] ?? '') as String,
      password: (m['password'] ?? '') as String,
      epgUrl: (m['epg'] ?? '') as String,
      channelCount: (m['count'] ?? 0) as int,
      updatedAt: (m['updated'] ?? 0) as int,
    );
  }

  @override
  bool operator ==(Object other) => other is Playlist && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Playlist($name, ${type.key})';
}
