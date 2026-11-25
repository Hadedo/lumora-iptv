import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:path_provider/path_provider.dart';

import '../../core/utils/constants.dart';
import '../models/playlist.dart';
import '../parsers/m3u_parser.dart';
import 'storage_service.dart';

/// أنواع الأخطاء، والواجهة تحوّلها إلى رسائل مترجمة.
/// network: لا يوجد إنترنت فعلاً في الجهاز.
/// timeout: انتهت مهلة الاتصال بالخادم.
/// unreachable: الإنترنت يعمل لكن الخادم لا يمكن الوصول إليه.
/// serverError: الخادم ردّ برفض أو استجابة غير صالحة.
enum PlaylistError {
  network,
  timeout,
  unreachable,
  serverError,
  invalidUrl,
  invalidPlaylist,
  loginFailed,
  fileRead,
}

class PlaylistException implements Exception {
  final PlaylistError error;
  final String? details;
  const PlaylistException(this.error, [this.details]);

  @override
  String toString() =>
      'PlaylistException(${error.name}${details != null ? ': $details' : ''})';
}

/// يضيف القوائم ويحدّثها ويحذفها: تنزيل، تحليل، ثم حفظ في التخزين المحلي.
/// إن فشل التحديث تبقى القنوات القديمة كما هي.
class PlaylistService {
  final StorageService _storage;
  final Dio _dio;

  PlaylistService(this._storage, {Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              sendTimeout: const Duration(seconds: 20),
              receiveTimeout: AppConstants.playlistDownloadTimeout,
              followRedirects: true,
              maxRedirects: 5,
              headers: {
                'User-Agent': AppConstants.streamUserAgent,
                'Accept': '*/*',
              },
              validateStatus: (s) => s != null && s < 400,
            ));

  // ═════════════ الإضافة ═════════════

  Future<Playlist> addFromUrl({
    required String name,
    required String url,
    String epgUrl = '',
  }) async {
    final clean = _normalizeUrl(url);
    final playlist = Playlist.create(
      name: _displayName(name, clean),
      type: PlaylistType.url,
      source: clean,
      epgUrl: epgUrl,
    );
    return _import(playlist);
  }

  Future<Playlist> addFromFile({
    required String name,
    required String filePath,
    String epgUrl = '',
  }) async {
    final src = File(filePath);
    if (!await src.exists()) {
      throw const PlaylistException(PlaylistError.fileRead);
    }

    final draft = Playlist.create(
      name: _displayName(name, filePath.split('/').last),
      type: PlaylistType.file,
      source: filePath,
      epgUrl: epgUrl,
    );

    // ننسخ الملف لمجلد التطبيق لأن مسار المحدد مؤقت وقد يُحذف.
    final dir = await getApplicationSupportDirectory();
    final folder = Directory('${dir.path}/playlists');
    if (!await folder.exists()) await folder.create(recursive: true);
    final dest = '${folder.path}/${draft.id}.m3u';

    try {
      await src.copy(dest);
    } catch (e) {
      throw PlaylistException(PlaylistError.fileRead, e.toString());
    }

    try {
      return await _import(draft.copyWith(source: dest));
    } catch (_) {
      await _deleteFile(dest);
      rethrow;
    }
  }

  Future<Playlist> addFromXtream({
    required String name,
    required String server,
    required String username,
    required String password,
    String epgUrl = '',
  }) async {
    final normalized = _cleanXtreamServer(server);
    final uri = Uri.tryParse(normalized);
    if (uri == null || uri.host.isEmpty) {
      throw const PlaylistException(PlaylistError.invalidUrl);
    }
    final playlist = Playlist.create(
      name: _displayName(name, uri.host),
      type: PlaylistType.xtream,
      source: normalized,
      username: username,
      password: password,
      epgUrl: epgUrl,
    );
    await _verifyXtream(playlist);
    return _import(playlist);
  }

  // ═════════════ التحديث والحذف ═════════════

  Future<Playlist> refresh(Playlist playlist) async {
    if (playlist.isXtream) await _verifyXtream(playlist);
    return _import(playlist);
  }

  /// يحدّث كل القوائم ويعيد عدد التي نجحت.
  Future<int> refreshAll() async {
    var ok = 0;
    for (final p in _storage.getPlaylists()) {
      try {
        await refresh(p);
        ok++;
      } catch (_) {
        // نكمل بقية القوائم.
      }
    }
    return ok;
  }

  Future<void> delete(Playlist playlist) async {
    await _storage.deletePlaylist(playlist.id);
    if (playlist.isFile) await _deleteFile(playlist.source);
  }

  void dispose() => _dio.close();

  // ═════════════ الداخل ═════════════

  Future<Playlist> _import(Playlist playlist) async {
    final content = await _load(playlist);
    final result = await M3uParser.parseAsync(content, playlist.id);
    if (result.isEmpty) {
      throw const PlaylistException(PlaylistError.invalidPlaylist);
    }

    await _storage.saveChannels(playlist.id, result.channels);

    final saved = playlist.copyWith(
      channelCount: result.channels.length,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      epgUrl: playlist.epgUrl.isNotEmpty ? playlist.epgUrl : result.epgUrl,
    );
    await _storage.savePlaylist(saved);

    // أول قائمة تُضاف تصبح هي النشطة تلقائياً.
    if (_storage.activePlaylistId == null) {
      await _storage.setActivePlaylistId(saved.id);
    }
    return saved;
  }

  Future<String> _load(Playlist p) async {
    if (p.isFile) {
      try {
        final bytes = await File(p.source).readAsBytes();
        return await _decode(bytes);
      } catch (e) {
        throw PlaylistException(PlaylistError.fileRead, e.toString());
      }
    }
    return _download(p.downloadUrl);
  }

  /// تنزيل مع إعادة محاولة بتأخير متصاعد. أخطاء 4xx لا تُعاد لأنها لن تنجح.
  Future<String> _download(String url) async {
    DioException? last;
    for (var attempt = 0; attempt <= AppConstants.networkRetries; attempt++) {
      try {
        final res = await _dio.get<List<int>>(
          url,
          options: Options(responseType: ResponseType.bytes),
        );
        final data = res.data;
        if (data == null || data.isEmpty) {
          throw const PlaylistException(PlaylistError.invalidPlaylist);
        }
        return await _decode(data);
      } on DioException catch (e) {
        last = e;
        final code = e.response?.statusCode;
        if (code != null && code >= 400 && code < 500) break;
        if (attempt < AppConstants.networkRetries) {
          await Future<void>.delayed(
            AppConstants.retryBaseDelay * (attempt + 1),
          );
        }
      }
    }
    final err = last;
    if (err == null) {
      throw const PlaylistException(PlaylistError.unreachable);
    }
    throw await _classify(err);
  }

  Future<String> _decode(List<int> bytes) {
    if (bytes.length > 1024 * 1024) {
      return compute(M3uParser.decodeBytes, bytes);
    }
    return Future.value(M3uParser.decodeBytes(bytes));
  }

  /// يتحقق من حساب Xtream قبل التنزيل.
  Future<void> _verifyXtream(Playlist p) async {
    try {
      final res = await _dio.getUri<String>(
        p.xtreamAuthUri,
        options: Options(
          responseType: ResponseType.plain,
          receiveTimeout: const Duration(seconds: 40),
        ),
      );

      final body = (res.data ?? '').replaceFirst('\uFEFF', '').trim();
      if (body.isEmpty || body == '[]' || body == '{}') {
        throw const PlaylistException(PlaylistError.loginFailed);
      }

      dynamic json;
      try {
        json = jsonDecode(body);
      } on FormatException {
        // الخادم ردّ بصفحة غير JSON (حظر أو خطأ)، وليس خطأ في الحساب.
        throw const PlaylistException(
          PlaylistError.serverError,
          'Invalid response',
        );
      }

      final info = json is Map ? json['user_info'] : null;
      if (info is! Map) {
        throw const PlaylistException(PlaylistError.loginFailed);
      }
      final auth = info['auth'];
      if (auth == 1 || auth == '1' || auth == true) return;
      throw const PlaylistException(PlaylistError.loginFailed);
    } on PlaylistException {
      rethrow;
    } on DioException catch (e) {
      throw await _classify(e, forLogin: true);
    }
  }

  /// يحوّل خطأ Dio إلى سبب دقيق بدل رسالة «لا يوجد إنترنت» لكل شيء.
  Future<PlaylistException> _classify(
    DioException e, {
    bool forLogin = false,
  }) async {
    final code = e.response?.statusCode;

    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const PlaylistException(PlaylistError.timeout);

      case DioExceptionType.badCertificate:
        return const PlaylistException(PlaylistError.unreachable, 'SSL');

      case DioExceptionType.badResponse:
        if (forLogin && (code == 401 || code == 403)) {
          return const PlaylistException(PlaylistError.loginFailed);
        }
        return PlaylistException(
          PlaylistError.serverError,
          code == null ? null : 'HTTP $code',
        );

      case DioExceptionType.cancel:
        return const PlaylistException(PlaylistError.unreachable, 'cancelled');

      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        {
          // نفرّق بين انقطاع الإنترنت فعلاً وتعذّر الوصول إلى الخادم.
          final online = await _hasInternet();
          return PlaylistException(
            online ? PlaylistError.unreachable : PlaylistError.network,
            e.error?.toString(),
          );
        }
    }
  }

  /// فحص سريع: هل يستطيع الجهاز الوصول لأي موقع معروف؟
  Future<bool> _hasInternet() async {
    const hosts = ['one.one.one.one', 'google.com'];
    for (final h in hosts) {
      try {
        final r = await InternetAddress.lookup(h)
            .timeout(const Duration(seconds: 4));
        if (r.isNotEmpty && r.first.rawAddress.isNotEmpty) return true;
      } catch (_) {
        // نجرّب العنوان التالي.
      }
    }
    return false;
  }

  /// ينظّف عنوان خادم Xtream: يزيل المسافات والشرطة الأخيرة واسم الملف
  /// (player_api.php / get.php ...) والوسائط، ويضيف http:// عند غيابه.
  String _cleanXtreamServer(String input) {
    var s = input.replaceAll(RegExp(r'\s'), '');
    if (s.isEmpty) return s;
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      s = 'http://$s';
    }
    final u = Uri.tryParse(s);
    if (u == null || u.host.isEmpty) return s;

    final segments = u.path.split('/').where((e) => e.isNotEmpty).toList();
    if (segments.isNotEmpty && segments.last.toLowerCase().endsWith('.php')) {
      segments.removeLast();
    }
    final path = segments.isEmpty ? '' : '/${segments.join('/')}';
    final port = u.hasPort ? ':${u.port}' : '';
    return '${u.scheme}://${u.host}$port$path';
  }

  String _normalizeUrl(String input) {
    var s = input.trim();
    if (s.isEmpty) throw const PlaylistException(PlaylistError.invalidUrl);
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      s = 'http://$s';
    }
    final uri = Uri.tryParse(s);
    if (uri == null || uri.host.isEmpty) {
      throw const PlaylistException(PlaylistError.invalidUrl);
    }
    return s;
  }

  String _displayName(String name, String fallback) {
    final n = name.trim();
    if (n.isNotEmpty) return n;
    final host = Uri.tryParse(fallback)?.host ?? '';
    if (host.isNotEmpty) return host;
    return fallback.isNotEmpty ? fallback : 'Playlist';
  }

  Future<void> _deleteFile(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
