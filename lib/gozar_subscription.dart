import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'td_system_vpn.dart';

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

List<GozarSubscriptionNode> parseGozarSubscription(String payload) {
  String source = payload.trim();
  if (source.isEmpty) {
    throw const FormatException('پاسخ اشتراک خالی است.');
  }

  bool hasLinks(String value) => RegExp(
    r'(?:vmess|vless|trojan)://', caseSensitive: false,
  ).hasMatch(value);

  if (!hasLinks(source)) {
    try {
      final compact = source.replaceAll(RegExp(r'\s+'), '');
      final normalized = base64.normalize(compact.replaceAll('-', '+')
          .replaceAll('_', '/'));
      final decoded = utf8.decode(base64.decode(normalized));
      if (hasLinks(decoded)) source = decoded;
    } catch (_) {
      // The plain-text validation below produces the user-facing error.
    }
  }

  final matches = RegExp(
    r'(?:vmess|vless|trojan)://[^\s]+', caseSensitive: false,
  ).allMatches(source);
  final nodes = <GozarSubscriptionNode>[];
  final seen = <String>{};
  for (final match in matches) {
    final link = match.group(0)!.trim();
    if (!seen.add(link)) continue;
    try {
      buildFullDeviceXrayConfig(link);
      final uri = Uri.tryParse(link);
      final fragment = uri == null ? '' : Uri.decodeComponent(uri.fragment);
      final label = fragment.trim().isNotEmpty
          ? fragment.trim()
          : 'سرور اشتراک ' + (nodes.length + 1).toString();
      nodes.add(GozarSubscriptionNode(label, link));
    } on FormatException {
      // A subscription may contain protocols/transports this build cannot run.
    }
  }
  if (nodes.isEmpty) {
    throw const FormatException(
      'هیچ لینک معتبر VMess، VLESS یا Trojan در اشتراک پیدا نشد.',
    );
  }
  return nodes;
}

Future<List<GozarSubscriptionNode>> fetchGozarSubscription(
  String input, {
  Duration timeout = const Duration(seconds: 12),
  int maxBytes = 2 * 1024 * 1024,
}) async {
  final uri = Uri.tryParse(input.trim());
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
    throw const FormatException('لینک اشتراک باید یک نشانی HTTPS معتبر باشد.');
  }
  final client = HttpClient()
    ..connectionTimeout = timeout
    ..userAgent = 'Gozar/1.3 Android';
  try {
    final request = await client.getUrl(uri).timeout(timeout);
    final response = await request.close().timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Subscription HTTP ' +
          response.statusCode.toString(), uri: uri);
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
    return parseGozarSubscription(utf8.decode(bytes.takeBytes()));
  } finally {
    client.close(force: true);
  }
}

({String host, int port}) gozarEndpoint(String link) {
  final config = jsonDecode(buildFullDeviceXrayConfig(link))
      as Map<String, dynamic>;
  final outbound = (config['outbounds'] as List).first as Map;
  final settings = outbound['settings'] as Map;
  final endpoint = (settings['vnext'] as List?)?.first ??
      (settings['servers'] as List?)?.first;
  if (endpoint is! Map || endpoint['address'] is! String ||
      endpoint['port'] is! int) {
    throw const FormatException('نشانی سرور برای آزمایش در دسترس نیست.');
  }
  return (host: endpoint['address'] as String, port: endpoint['port'] as int);
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
      final socket = await Socket.connect(endpoint.host, endpoint.port,
          timeout: timeout);
      timer.stop();
      socket.destroy();
      samples.add(timer.elapsedMilliseconds);
      if (attempt == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 80));
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
  int concurrency = 6,
  Future<int?> Function(String link)? probe,
}) async {
  if (links.isEmpty) return null;
  final measure = probe ?? probeGozarNode;
  final limit = links.length < maxCandidates ? links.length : maxCandidates;
  GozarProbeResult? best;
  for (var offset = 0; offset < limit; offset += concurrency) {
    final end = (offset + concurrency < limit)
        ? offset + concurrency : limit;
    final batch = <Future<GozarProbeResult?>>[];
    for (var i = offset; i < end; i++) {
      batch.add(measure(links[i]).then((latency) =>
          latency == null ? null : GozarProbeResult(i, latency)));
    }
    for (final result in await Future.wait(batch)) {
      if (result != null &&
          (best == null || result.latencyMs < best.latencyMs)) {
        best = result;
      }
    }
  }
  return best;
}
