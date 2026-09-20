/// A Telegram MTProto proxy link. The secret is never put in status messages.
class MtprotoProxyConfig {
  final String server;
  final int port;
  final String secret;
  const MtprotoProxyConfig(this.server, this.port, this.secret);
}

/// Accepts tg://proxy and official t.me/proxy deep links only.
/// SOCKS links must not be sent to TDLib as MTProto credentials.
MtprotoProxyConfig parseMtprotoProxyLink(String text) {
  final input = text.trim();
  final uri = Uri.tryParse(input);
  if (uri == null) {
    throw const FormatException('لینک پروکسی معتبر نیست.');
  }
  final isTg = uri.scheme.toLowerCase() == 'tg' &&
      (uri.host.toLowerCase() == 'proxy' || uri.path.toLowerCase() == 'proxy');
  final isWeb = (uri.scheme == 'https' || uri.scheme == 'http') &&
      const ['t.me', 'www.t.me', 'telegram.me', 'www.telegram.me']
          .contains(uri.host.toLowerCase()) &&
      uri.path.toLowerCase() == '/proxy';
  if (!isTg && !isWeb) {
    throw const FormatException('فقط لینک MTProto از نوع tg://proxy یا t.me/proxy پذیرفته می‌شود.');
  }
  final server = (uri.queryParameters['server'] ?? '').trim();
  final portText = uri.queryParameters['port'] ?? '';
  final secret = (uri.queryParameters['secret'] ?? '').trim();
  final port = int.tryParse(portText);
  if (server.isEmpty || server.length > 253 ||
      !RegExp(r'^[a-zA-Z0-9.:-]+$').hasMatch(server) ||
      server.contains('..') || server.startsWith('-') || server.endsWith('-') ||
      port == null || port < 1 || port > 65535 ||
      !RegExp(r'^(?:[0-9a-fA-F]{32}|dd[0-9a-fA-F]{32}|ee[0-9a-fA-F]{34,512})$',
          caseSensitive: false).hasMatch(secret) ||
      (secret.toLowerCase().startsWith('ee') && secret.length.isOdd)) {
    throw const FormatException('آدرس، پورت یا رمز پروکسی MTProto معتبر نیست.');
  }
  return MtprotoProxyConfig(server, port, secret);
}
