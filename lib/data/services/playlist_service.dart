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
enum PlaylistError { network, invalidUrl, invalidPlaylist, loginFailed, fileRead }

class PlaylistException implements Exception {
  final PlaylistError error;
  final String? details;
  const PlaylistException(this.error, [this.details]);

  @override
  String toString() => 'PlaylistException(${error.name}${details != null ? ': $details' : ''})';
}

/// يضيف القوائم ويحدّثها ويحذفها: تنزيل، تحليل، ثم حفظ في التخزين المحلي.
/// إن فشل التحديث تبقى القنوات القديمة كما هي.
class PlaylistService {
  final StorageService _storage;
  final Dio _dio;

  PlaylistService(this._storage, {Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: AppConstants.connectTimeout,
              receiveTimeout: AppConstants.playlistDownloadTimeout,
              followRedirects: true,
              maxRedirects: 5,
              headers: {'User-Agent': AppConstants.streamUserAgent},
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
    final normalized = Playlist.normalizeServer(server);
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
        return _decode(bytes);
      } catch (e) {
        throw PlaylistException(PlaylistError.fileRead, e.toString());
      }
    }
    return _download(p.downloadUrl);
  }

  /// تنزيل مع إعادة محاولة بتأخير متصاعد. أخطاء 4xx لا تُعاد لأنها لن تنجح.
  Future<String> _download(String url) async {
    Object? last;
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
        return _decode(data);
      } on DioException catch (e) {
        last = e;
        final code = e.response?.statusCode;
        if (code != null && code >= 400 && code < 500) break;
        if (attempt < AppConstants.networkRetries) {
          await Future<void>.delayed(AppConstants.retryBaseDelay * (attempt + 1));
        }
      }
    }
    throw PlaylistException(PlaylistError.network, last?.toString());
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
          receiveTimeout: AppConstants.receiveTimeout,
        ),
      );
      final body = res.data ?? '';
      final json = jsonDecode(body);
      final info = json is Map ? json['user_info'] : null;
      final auth = info is Map ? info['auth'] : null;
      if (auth == 1 || auth == '1' || auth == true) return;
      throw const PlaylistException(PlaylistError.loginFailed);
    } on PlaylistException {
      rethrow;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) {
        throw const PlaylistException(PlaylistError.loginFailed);
      }
      throw PlaylistException(PlaylistError.network, e.toString());
    } on FormatException {
      throw const PlaylistException(PlaylistError.loginFailed);
    }
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
