import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReaderBackendException implements Exception {
  final String message;
  final int statusCode;
  const ReaderBackendException(this.message, [this.statusCode = -1]);

  @override
  String toString() => message;
}

/// HTTPS client for the public Telegram Reader backend.
class ReaderBackend {
  static const baseUrl = 'https://reader.duckpsycho.dev';
  static const _cookieKey = 'reader_duck_account_id';

  final SharedPreferences prefs;
  final Duration timeout;

  ReaderBackend(this.prefs, {this.timeout = const Duration(seconds: 15)});

  String? get accountId => prefs.getString(_cookieKey);

  Uri absoluteUri(String value) {
    final raw = value.trim();
    final parsed = Uri.tryParse(raw);
    if (parsed != null && parsed.hasScheme) return parsed;
    if (raw.startsWith('//')) return Uri.parse('https:' + raw);
    if (raw.startsWith('/')) return Uri.parse(baseUrl + raw);
    return Uri.parse(baseUrl + '/' + raw);
  }

  Future<Map<String, dynamic>?> ensureAccount() async {
    Map<String, dynamic>? account = await getAccount();
    if (account != null) return account;
    try {
      await _request('GET', '/', acceptJson: false);
    } catch (_) {}
    account = await getAccount();
    return account;
  }

  Future<Map<String, dynamic>?> getAccount() async {
    final response = await _request('GET', '/api/account');
    if (response.body.trim().isEmpty) return null;
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) return null;
    final root = Map<String, dynamic>.from(decoded);
    final account = root['account'];
    return account is Map ? Map<String, dynamic>.from(account) : null;
  }

  Future<List<Map<String, dynamic>>> getSubscriptions() async {
    final response = await _request('GET', '/api/subscriptions');
    final decoded = jsonDecode(response.body);
    if (decoded is! List) return const [];
    return decoded.whereType<Map>().map(Map<String, dynamic>.from).toList();
  }

  Future<Map<String, dynamic>?> subscribe(String username) async {
    final response = await _request(
      'POST',
      '/api/subscriptions',
      jsonBody: {'channelUsername': username},
    );
    if (response.body.trim().isEmpty) return null;
    final decoded = jsonDecode(response.body);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  }

  Future<void> unsubscribe(String username) async {
    await _request(
      'DELETE',
      '/api/subscriptions/' + Uri.encodeComponent(username),
    );
  }

  Future<Map<String, dynamic>> getPosts(String username, {int? before}) async {
    var path = '/api/channels/' + Uri.encodeComponent(username) + '/posts';
    if (before != null) path += '?before=' + before.toString();
    final response = await _request('GET', path);
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const ReaderBackendException('پاسخ سرویس خبر معتبر نیست.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  Future<String> downloadMedia(
    String value, {
    required String cacheKey,
    String? suggestedName,
  }) async {
    final uri = absoluteUri(value);
    if (uri.scheme != 'https' && uri.scheme != 'http') {
      throw const ReaderBackendException('نشانی فایل معتبر نیست.');
    }

    final client = HttpClient()
      ..connectionTimeout = timeout
      ..idleTimeout = timeout
      ..userAgent = 'NabzKhabar-Cafenet/2.0 Android';
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, '*/*');
      _attachCookie(request, uri);
      final response = await request.close().timeout(timeout);
      _captureCookie(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.drain<void>();
        throw ReaderBackendException(
          'دریافت فایل با خطای ' + response.statusCode.toString() + ' روبه‌رو شد.',
          response.statusCode,
        );
      }

      final directory = Directory(
        (await getTemporaryDirectory()).path + '/reader_media',
      )..createSync(recursive: true);
      final extension = _extensionFor(
        suggestedName ?? (uri.pathSegments.isEmpty ? '' : uri.pathSegments.last),
        response.headers.contentType?.mimeType,
      );
      final safeKey = cacheKey.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final target = File(directory.path + '/' + safeKey + extension);
      final temp = File(target.path + '.part');
      final sink = temp.openWrite();
      try {
        await response.pipe(sink).timeout(const Duration(minutes: 5));
      } finally {
        await sink.close();
      }
      if (target.existsSync()) target.deleteSync();
      await temp.rename(target.path);
      return target.path;
    } finally {
      client.close(force: true);
    }
  }

  Future<_ReaderResponse> _request(
    String method,
    String path, {
    Map<String, dynamic>? jsonBody,
    bool acceptJson = true,
  }) async {
    final uri = Uri.parse(baseUrl + path);
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..idleTimeout = timeout
      ..userAgent = 'NabzKhabar-Cafenet/2.0 Android';
    try {
      final request = await client.openUrl(method, uri).timeout(timeout);
      request.headers.set(
        HttpHeaders.acceptHeader,
        acceptJson ? 'application/json' : 'text/html,*/*',
      );
      request.headers.set(HttpHeaders.acceptLanguageHeader, 'fa,en;q=0.7');
      _attachCookie(request, uri);
      if (jsonBody != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(jsonBody));
      }

      final response = await request.close().timeout(timeout);
      _captureCookie(response);
      final body = await utf8.decoder.bind(response).join().timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        String message = 'خطای ارتباط با سرویس خبر';
        try {
          final decoded = jsonDecode(body);
          if (decoded is Map && decoded['message'] != null) {
            message = decoded['message'].toString();
          }
        } catch (_) {}
        throw ReaderBackendException(message, response.statusCode);
      }
      return _ReaderResponse(response.statusCode, body);
    } on ReaderBackendException {
      rethrow;
    } on TimeoutException {
      throw const ReaderBackendException('پاسخ سرویس خبر با تأخیر روبه‌رو شد.');
    } on SocketException {
      throw const ReaderBackendException('ارتباط اینترنت با سرویس خبر برقرار نشد.');
    } finally {
      client.close(force: true);
    }
  }

  void _attachCookie(HttpClientRequest request, Uri uri) {
    final id = accountId;
    if (id == null || id.isEmpty || uri.host != 'reader.duckpsycho.dev') return;
    request.cookies.add(Cookie('account_id', id)
      ..domain = 'reader.duckpsycho.dev'
      ..path = '/'
      ..secure = true);
  }

  void _captureCookie(HttpClientResponse response) {
    for (final cookie in response.cookies) {
      if (cookie.name == 'account_id' && cookie.value.isNotEmpty) {
        unawaited(prefs.setString(_cookieKey, cookie.value));
      }
    }
  }

  static String _extensionFor(String name, String? mime) {
    final lower = name.toLowerCase();
    final dot = lower.lastIndexOf('.');
    if (dot >= 0 && dot < lower.length - 1) {
      final ext = lower.substring(dot);
      if (ext.length <= 8 && RegExp(r'^\.[a-z0-9]+$').hasMatch(ext)) {
        return ext;
      }
    }
    return switch (mime?.toLowerCase()) {
      'image/jpeg' || 'image/jpg' => '.jpg',
      'image/png' => '.png',
      'image/webp' => '.webp',
      'image/gif' => '.gif',
      'video/mp4' => '.mp4',
      'video/webm' => '.webm',
      'application/pdf' => '.pdf',
      'application/zip' => '.zip',
      'application/vnd.android.package-archive' => '.apk',
      'audio/mpeg' => '.mp3',
      'audio/mp4' => '.m4a',
      'audio/ogg' => '.ogg',
      _ => '',
    };
  }
}

class _ReaderResponse {
  final int statusCode;
  final String body;
  const _ReaderResponse(this.statusCode, this.body);
}
