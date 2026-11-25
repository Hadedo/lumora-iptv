import 'dart:convert';

import 'package:flutter/foundation.dart' show compute;

import '../../core/utils/constants.dart';
import '../models/channel.dart';

/// نتيجة تحليل قائمة M3U.
class M3uResult {
  final List<Channel> channels;

  /// رابط دليل البرامج إن وُجد في ترويسة القائمة.
  final String epgUrl;

  const M3uResult(this.channels, this.epgUrl);

  bool get isEmpty => channels.isEmpty;
}

class _ParseJob {
  final String content;
  final String playlistId;
  const _ParseJob(this.content, this.playlistId);
}

M3uResult _runParse(_ParseJob job) =>
    M3uParser.parse(job.content, job.playlistId);

class _Info {
  final String name;
  final Map<String, String> attrs;
  const _Info(this.name, this.attrs);
}

/// محلل M3U / M3U8 سريع ومتسامح مع القوائم المشوهة.
/// يعمل في خيط منفصل عند القوائم الكبيرة حتى لا تتجمد الواجهة.
class M3uParser {
  M3uParser._();

  static final RegExp _attrRe = RegExp(
    r'''([A-Za-z0-9_\-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')''',
  );
  static final RegExp _schemeRe = RegExp(r'^[A-Za-z][A-Za-z0-9+.\-]*://');

  /// حد الحجم الذي نبدأ عنده التحليل في خيط منفصل.
  static const int _isolateThreshold = 20000;

  /// يحوّل بايتات الملف إلى نص مع تجاهل البايتات التالفة.
  static String decodeBytes(List<int> bytes) =>
      utf8.decode(bytes, allowMalformed: true);

  /// تحليل غير متزامن: خيط منفصل للقوائم الكبيرة، ومباشر للصغيرة.
  static Future<M3uResult> parseAsync(String content, String playlistId) async {
    if (content.length < _isolateThreshold) {
      return parse(content, playlistId);
    }
    return compute(_runParse, _ParseJob(content, playlistId));
  }

  /// تحليل متزامن.
  static M3uResult parse(String raw, String playlistId) {
    var content = raw;
    if (content.isNotEmpty && content.codeUnitAt(0) == 0xFEFF) {
      content = content.substring(1);
    }

    final channels = <Channel>[];
    final seen = <String>{};
    var epg = '';

    var hasInfo = false;
    var pName = '';
    var pLogo = '';
    var pGroup = '';
    var pTvg = '';
    var pUa = '';
    var pRef = '';

    void resetPending() {
      hasInfo = false;
      pName = '';
      pLogo = '';
      pGroup = '';
      pTvg = '';
      pUa = '';
      pRef = '';
    }

    for (final rawLine in content.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      if (line.startsWith('#')) {
        if (line.startsWith('#EXTINF')) {
          final info = _parseInfo(line);
          hasInfo = true;
          pName = _clean(info.name);
          pLogo = info.attrs[AppConstants.attrLogo] ?? '';
          pTvg = info.attrs[AppConstants.attrId] ?? '';
          pGroup = _clean(info.attrs[AppConstants.attrGroup] ?? '');
          if (pName.isEmpty) {
            pName = _clean(info.attrs[AppConstants.attrName] ?? '');
          }
        } else if (line.startsWith('#EXTM3U')) {
          final attrs = _parseAttrs(line);
          final candidate = attrs[AppConstants.attrEpg] ??
              attrs['url-tvg'] ??
              attrs['tvg-url'] ??
              '';
          if (candidate.isNotEmpty && epg.isEmpty) {
            epg = candidate.split(',').first.trim();
          }
        } else if (line.startsWith('#EXTGRP:')) {
          if (pGroup.isEmpty) {
            pGroup = _clean(line.substring(8));
          }
        } else if (line.startsWith('#EXTVLCOPT:')) {
          final opt = line.substring(11);
          final eq = opt.indexOf('=');
          if (eq > 0) {
            final key = opt.substring(0, eq).trim().toLowerCase();
            final value = opt.substring(eq + 1).trim();
            if (key == 'http-user-agent') pUa = value;
            if (key == 'http-referrer' || key == 'http-referer') pRef = value;
          }
        }
        continue;
      }

      // سطر رابط
      var url = line;
      var ua = pUa;
      var ref = pRef;

      // صيغة Kodi: الرابط|User-Agent=...&Referer=...
      final pipe = url.indexOf('|');
      if (pipe > 0) {
        final tail = url.substring(pipe + 1);
        if (tail.contains('=')) {
          url = url.substring(0, pipe).trim();
          for (final part in tail.split('&')) {
            final eq = part.indexOf('=');
            if (eq <= 0) continue;
            final key = part.substring(0, eq).trim().toLowerCase();
            final value = _decode(part.substring(eq + 1).trim());
            if (key == 'user-agent') ua = value;
            if (key == 'referer' || key == 'referrer') ref = value;
          }
        }
      }

      if (!_schemeRe.hasMatch(url)) {
        resetPending();
        continue;
      }

      var name = hasInfo ? pName : '';
      if (name.isEmpty) {
        final host = Uri.tryParse(url)?.host ?? '';
        name = host.isNotEmpty ? host : 'Channel ${channels.length + 1}';
      }

      final channel = Channel.create(
        playlistId: playlistId,
        name: name,
        url: url,
        logo: pLogo,
        group: pGroup,
        tvgId: pTvg,
        userAgent: ua,
        referrer: ref,
      );

      if (seen.add(channel.id)) {
        channels.add(channel);
      }
      resetPending();
    }

    return M3uResult(channels, epg);
  }

  // ───────── أدوات داخلية ─────────

  static _Info _parseInfo(String line) {
    final start = line.indexOf(':') + 1;
    var comma = -1;
    var inQuote = false;
    for (var i = start; i < line.length; i++) {
      final c = line[i];
      if (c == '"') {
        inQuote = !inQuote;
      } else if (c == ',' && !inQuote) {
        comma = i;
        break;
      }
    }
    final attrPart = comma >= 0 ? line.substring(0, comma) : line;
    final name = comma >= 0 ? line.substring(comma + 1).trim() : '';
    return _Info(name, _parseAttrs(attrPart));
  }

  static Map<String, String> _parseAttrs(String s) {
    final map = <String, String>{};
    for (final m in _attrRe.allMatches(s)) {
      final key = m.group(1)!.toLowerCase();
      final value = (m.group(2) ?? m.group(3) ?? '').trim();
      map.putIfAbsent(key, () => value);
    }
    return map;
  }

  static String _clean(String s) {
    var out = s.trim();
    if (out.contains('&')) {
      out = out
          .replaceAll('&amp;', '&')
          .replaceAll('&quot;', '"')
          .replaceAll('&apos;', "'")
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>');
    }
    return out;
  }

  static String _decode(String s) {
    try {
      return Uri.decodeComponent(s);
    } catch (_) {
      return s;
    }
  }
}
