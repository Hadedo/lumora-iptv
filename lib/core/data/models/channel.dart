/// نموذج القناة. كائن بسيط بلا اعتماد على أي مكتبة، وآمن للاستخدام داخل الخيوط المنفصلة (isolates).
/// يُخزَّن كخرائط بمفاتيح قصيرة لتصغير حجم القوائم الضخمة وتسريع قراءتها.
class Channel {
  /// معرّف ثابت مشتق من القائمة + الرابط + الاسم، فلا يتغير عند تحديث القائمة.
  final String id;
  final String playlistId;
  final String name;
  final String url;
  final String logo;
  final String group;
  final String tvgId;

  /// ترويسات اختيارية يقرؤها المحلل من وسوم EXTVLCOPT.
  final String userAgent;
  final String referrer;

  const Channel({
    required this.id,
    required this.playlistId,
    required this.name,
    required this.url,
    this.logo = '',
    this.group = '',
    this.tvgId = '',
    this.userAgent = '',
    this.referrer = '',
  });

  /// ينشئ قناة ويولّد لها معرّفاً ثابتاً.
  factory Channel.create({
    required String playlistId,
    required String name,
    required String url,
    String logo = '',
    String group = '',
    String tvgId = '',
    String userAgent = '',
    String referrer = '',
  }) {
    return Channel(
      id: makeId(playlistId, url, name),
      playlistId: playlistId,
      name: name,
      url: url,
      logo: logo,
      group: group,
      tvgId: tvgId,
      userAgent: userAgent,
      referrer: referrer,
    );
  }

  /// FNV-1a بطول 64 بت، سريع وكافٍ لمعرّف محلي.
  static String makeId(String playlistId, String url, String name) {
    const int prime = 0x100000001b3;
    int hash = 0xcbf29ce484222325;
    final input = '$playlistId|$url|$name';
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * prime) & 0x7FFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(36);
  }

  bool get hasLogo => logo.isNotEmpty;
  bool get hasGroup => group.trim().isNotEmpty;
  bool get hasHeaders => userAgent.isNotEmpty || referrer.isNotEmpty;

  /// أول حرفين للعرض عند غياب الشعار.
  String get initials {
    final clean = name.trim();
    if (clean.isEmpty) return '?';
    final parts = clean.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      final it = parts.first.runes.take(2).toList();
      return String.fromCharCodes(it).toUpperCase();
    }
    final a = String.fromCharCodes(parts[0].runes.take(1));
    final b = String.fromCharCodes(parts[1].runes.take(1));
    return (a + b).toUpperCase();
  }

  /// ترويسات HTTP للمشغّل.
  Map<String, String> headers(String defaultUserAgent) {
    return {
      'User-Agent': userAgent.isNotEmpty ? userAgent : defaultUserAgent,
      if (referrer.isNotEmpty) 'Referer': referrer,
    };
  }

  Channel copyWith({
    String? name,
    String? url,
    String? logo,
    String? group,
    String? tvgId,
    String? userAgent,
    String? referrer,
  }) {
    return Channel(
      id: id,
      playlistId: playlistId,
      name: name ?? this.name,
      url: url ?? this.url,
      logo: logo ?? this.logo,
      group: group ?? this.group,
      tvgId: tvgId ?? this.tvgId,
      userAgent: userAgent ?? this.userAgent,
      referrer: referrer ?? this.referrer,
    );
  }

  /// مفاتيح قصيرة لتقليل حجم التخزين؛ الحقول الفارغة لا تُكتب.
  Map<String, dynamic> toMap() {
    return {
      'i': id,
      'p': playlistId,
      'n': name,
      'u': url,
      if (logo.isNotEmpty) 'l': logo,
      if (group.isNotEmpty) 'g': group,
      if (tvgId.isNotEmpty) 't': tvgId,
      if (userAgent.isNotEmpty) 'a': userAgent,
      if (referrer.isNotEmpty) 'r': referrer,
    };
  }

  factory Channel.fromMap(Map<dynamic, dynamic> m) {
    return Channel(
      id: (m['i'] ?? '') as String,
      playlistId: (m['p'] ?? '') as String,
      name: (m['n'] ?? '') as String,
      url: (m['u'] ?? '') as String,
      logo: (m['l'] ?? '') as String,
      group: (m['g'] ?? '') as String,
      tvgId: (m['t'] ?? '') as String,
      userAgent: (m['a'] ?? '') as String,
      referrer: (m['r'] ?? '') as String,
    );
  }

  @override
  bool operator ==(Object other) => other is Channel && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Channel($name)';
}
