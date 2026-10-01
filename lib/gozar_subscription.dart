import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'gozar_vpn.dart';

class GozarSubscriptionNode {
  final String name;
  final String link;
  const GozarSubscriptionNode(this.name, this.link);
}

class GozarProbeResult {
  final int index;
  final int latencyMs;
  const GozarProbeResult(this.index, this.latencyMs);
}

String _decodeFlexibleBase64(String value) {
  var normalized = value.trim().replaceAll(RegExp(r'\s+'), '')
      .replaceAll('-', '+').replaceAll('_', '/');
  while (normalized.length % 4 != 0) {
    normalized += '=';
  }
  return utf8.decode(base64.decode(normalized), allowMalformed: false);
}

String normalizeGozarSubscriptionUrl(String input) {
  var value = input.trim();
  if (value.toLowerCase().startsWith('sub://')) {
    value = value.substring(6).trim();
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      try {
        value = _decodeFlexibleBase64(Uri.decodeComponent(value)).trim();
      } catch (_) {
        throw const FormatException('لینک sub:// قابل خواندن نیست.');
      }
    }
  }

  final uri = Uri.tryParse(value);
  if (uri == null ||
      !const ['http', 'https'].contains(uri.scheme.toLowerCase()) ||
      uri.host.isEmpty) {
    throw const FormatException(
      'لینک ساب باید http://، https:// یا sub:// معتبر باشد.',
    );
  }
  return uri.toString();
}

void _collectJsonStrings(dynamic value, List<String> output) {
  if (value is String) {
    output.add(value);
  } else if (value is List) {
    for (final item in value) {
      _collectJsonStrings(item, output);
    }
  } else if (value is Map) {
    for (final item in value.values) {
      _collectJsonStrings(item, output);
    }
  }
}

String _expandSubscriptionPayload(String payload) {
  var source = payload.trim();
  if (source.isEmpty) {
    throw const FormatException('پاسخ اشتراک خالی است.');
  }

  bool hasLinks(String value) => RegExp(
    r'(?:vmess|vless|trojan|ss)://',
    caseSensitive: false,
  ).hasMatch(value);

  for (var round = 0; round < 3 && !hasLinks(source); round++) {
    if (source.contains('%3A%2F%2F') ||
        source.contains('%3a%2f%2f')) {
      try {
        final decoded = Uri.decodeComponent(source);
        if (decoded != source) {
          source = decoded;
          continue;
        }
      } catch (_) {}
    }

    try {
      final parsed = jsonDecode(source);
      final strings = <String>[];
      _collectJsonStrings(parsed, strings);
      final joined = strings.join('\n');
      if (hasLinks(joined)) {
        source = joined;
        break;
      }
    } catch (_) {}

    try {
      final decoded = _decodeFlexibleBase64(source);
      if (decoded != source) {
        source = decoded.trim();
        continue;
      }
    } catch (_) {
      break;
    }
  }

  return source;
}

List<GozarSubscriptionNode> parseGozarSubscription(String payload) {
  final source = _expandSubscriptionPayload(payload);
  final matches = RegExp(
    r'''(?:vmess|vless|trojan|ss)://[^\s"'<>]+''',
    caseSensitive: false,
  ).allMatches(source);

  final nodes = <GozarSubscriptionNode>[];
  final seen = <String>{};

  for (final match in matches) {
    var link = match.group(0)!.trim();
    while (link.endsWith(',') ||
        link.endsWith(';') ||
        link.endsWith(']') ||
        link.endsWith('}')) {
      link = link.substring(0, link.length - 1);
    }
    if (!seen.add(link)) continue;

    try {
      buildGozarXrayConfig(link);
      final uri = Uri.tryParse(link);
      String fragment = '';
      try {
        fragment = uri == null
            ? ''
            : Uri.decodeComponent(uri.fragment).trim();
      } catch (_) {}
      final label = fragment.isNotEmpty
          ? fragment
          : 'سرور اشتراک ' + (nodes.length + 1).toString();
      nodes.add(GozarSubscriptionNode(label, link));
    } on FormatException {
      // Unsupported nodes inside a mixed subscription are skipped.
    }
  }

  if (nodes.isEmpty) {
    throw const FormatException(
      'هیچ سرور سازگار VMess، VLESS، Trojan یا Shadowsocks در ساب پیدا نشد.',
    );
  }
  return nodes;
}

Future<String> _downloadSubscription(
  Uri uri,
  String userAgent, {
  required Duration timeout,
  required int maxBytes,
}) async {
  final client = HttpClient()
    ..connectionTimeout = timeout
    ..userAgent = userAgent
    ..autoUncompress = true;

  try {
    final request = await client.getUrl(uri).timeout(timeout);
    request.followRedirects = true;
    request.maxRedirects = 8;
    request.headers.set(
      HttpHeaders.acceptHeader,
      'text/plain, application/octet-stream, application/json, */*',
    );
    request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    request.headers.set('pragma', 'no-cache');

    final response = await request.close().timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Subscription HTTP ' + response.statusCode.toString(),
        uri: uri,
      );
    }
    if (response.contentLength > maxBytes) {
      throw const FormatException('حجم اشتراک بیشتر از حد مجاز است.');
    }

    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(timeout)) {
      bytes.add(chunk);
      if (bytes.length > maxBytes) {
        throw const FormatException('حجم اشتراک بیشتر از حد مجاز است.');
      }
    }
    return utf8.decode(bytes.takeBytes(), allowMalformed: true);
  } finally {
    client.close(force: true);
  }
}

Future<List<GozarSubscriptionNode>> fetchGozarSubscription(
  String input, {
  Duration timeout = const Duration(seconds: 14),
  int maxBytes = 4 * 1024 * 1024,
}) async {
  final normalized = normalizeGozarSubscriptionUrl(input);
  final uri = Uri.parse(normalized);

  Object? lastError;
  const userAgents = [
    'v2rayNG/1.10 Android',
    'Gozar/1.5 Android',
  ];

  for (final userAgent in userAgents) {
    try {
      final payload = await _downloadSubscription(
        uri,
        userAgent,
        timeout: timeout,
        maxBytes: maxBytes,
      );
      return parseGozarSubscription(payload);
    } catch (error) {
      lastError = error;
    }
  }

  if (lastError is FormatException) throw lastError;
  if (lastError is HttpException) throw lastError;
  throw const FormatException(
    'ساب دریافت شد اما هیچ سرور سازگار در پاسخ آن پیدا نشد.',
  );
}

({String host, int port}) gozarEndpoint(String link) {
  final config = jsonDecode(buildGozarXrayConfig(link))
      as Map<String, dynamic>;
  final outbounds = config['outbounds'] as List;
  final outbound = outbounds.firstWhere(
    (item) => item is Map && item['tag'] == 'proxy',
  ) as Map;
  final settings = outbound['settings'] as Map;
  final endpoint = (settings['vnext'] as List?)?.first ??
      (settings['servers'] as List?)?.first;
  if (endpoint is Map &&
      endpoint['address'] is String &&
      endpoint['port'] is int) {
    return (
      host: endpoint['address'] as String,
      port: endpoint['port'] as int,
    );
  }
  if (settings['address'] is String && settings['port'] is int) {
    return (
      host: settings['address'] as String,
      port: settings['port'] as int,
    );
  }
  throw const FormatException(
    'نشانی سرور برای آزمایش در دسترس نیست.',
  );
}

Future<int?> probeGozarNode(
  String link, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  try {
    final endpoint = gozarEndpoint(link);
    final samples = <int>[];

    for (var attempt = 0; attempt < 2; attempt++) {
      final timer = Stopwatch()..start();
      final socket = await Socket.connect(
        endpoint.host,
        endpoint.port,
        timeout: timeout,
      );
      timer.stop();
      socket.destroy();
      samples.add(timer.elapsedMilliseconds);

      if (attempt == 0) {
        await Future<void>.delayed(
          const Duration(milliseconds: 80),
        );
      }
    }

    samples.sort();
    return samples.last;
  } catch (_) {
    return null;
  }
}

Future<GozarProbeResult?> chooseBestGozarNode(
  List<String> links, {
  int maxCandidates = 60,
  int concurrency = 8,
  Future<int?> Function(String link)? probe,
}) async {
  if (links.isEmpty) return null;
  final measure = probe ?? probeGozarNode;
  final limit =
      links.length < maxCandidates ? links.length : maxCandidates;
  GozarProbeResult? best;

  for (var offset = 0; offset < limit; offset += concurrency) {
    final end = (offset + concurrency < limit)
        ? offset + concurrency
        : limit;
    final batch = <Future<GozarProbeResult?>>[];

    for (var i = offset; i < end; i++) {
      batch.add(
        measure(links[i]).then(
          (latency) => latency == null
              ? null
              : GozarProbeResult(i, latency),
        ),
      );
    }

    for (final result in await Future.wait(batch)) {
      if (result != null &&
          (best == null ||
              result.latencyMs < best.latencyMs)) {
        best = result;
      }
    }
  }
  return best;
}
