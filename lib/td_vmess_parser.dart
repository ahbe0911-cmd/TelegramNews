import 'dart:convert';

/// Decodes the common vmess://base64(JSON) share format locally.
/// Credentials remain in the user's device settings and native Xray config.
Map<String, dynamic> parseVmessShareLink(String link) {
  final encoded = link.substring('vmess://'.length)
      .split('#').first.split('?').first.trim();
  if (encoded.isEmpty || encoded.length > 65536) {
    throw const FormatException('لینک VMess خالی یا بیش از حد طولانی است.');
  }
  Map<String, dynamic> profile;
  try {
    final normalized = base64.normalize(encoded.replaceAll('-', '+')
        .replaceAll('_', '/').replaceAll(RegExp(r'\s'), ''));
    final decoded = jsonDecode(utf8.decode(base64.decode(normalized)));
    if (decoded is! Map) throw const FormatException();
    profile = Map<String, dynamic>.from(decoded);
  } catch (_) {
    throw const FormatException(
        'فرمت لینک VMess معتبر نیست؛ لینک اشتراک‌گذاری کامل را وارد کنید.');
  }
  String value(String key) => profile[key]?.toString().trim() ?? '';
  final address = value('add');
  final port = int.tryParse(value('port'));
  final id = value('id');
  final aid = int.tryParse(value('aid').isEmpty ? '0' : value('aid'));
  final uuidPattern =
      RegExp(r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}');
  if (address.isEmpty || address.length > 255 ||
      port == null || port < 1 || port > 65535 ||
      id.length != 36 || !uuidPattern.hasMatch(id) ||
      aid == null || aid < 0 || aid > 65535) {
    throw const FormatException('آدرس، پورت یا شناسه حساب VMess معتبر نیست.');
  }
  final cipher = value('scy').isEmpty ? 'auto' : value('scy').toLowerCase();
  if (!const ['auto', 'aes-128-gcm', 'chacha20-poly1305', 'none', 'zero']
      .contains(cipher)) {
    throw const FormatException('رمزگذاری VMess پشتیبانی نمی‌شود.');
  }
  final network = value('net').isEmpty ? 'tcp' : value('net').toLowerCase();
  if (!const ['tcp', 'ws', 'grpc', 'h2', 'http', 'httpupgrade']
      .contains(network)) {
    throw const FormatException('نوع انتقال VMess پشتیبانی نمی‌شود.');
  }
  final tls = value('tls').toLowerCase();
  if (!const ['', 'none', 'tls'].contains(tls)) {
    throw const FormatException('تنظیمات TLS این حساب پشتیبانی نمی‌شود.');
  }
  final host = value('host');
  final path = value('path');
  final stream = <String, dynamic>{
    'network': network == 'h2' ? 'http' : network,
    'security': tls == 'tls' ? 'tls' : 'none',
  };
  if (tls == 'tls') {
    final serverName = value('sni').isNotEmpty ? value('sni')
        : host.isNotEmpty ? host.split(',').first.trim() : address;
    stream['tlsSettings'] = <String, dynamic>{
      'serverName': serverName,
      'allowInsecure': false,
      if (value('fp').isNotEmpty) 'fingerprint': value('fp'),
      if (value('alpn').isNotEmpty)
        'alpn': value('alpn').split(',')
            .map((part) => part.trim()).where((part) => part.isNotEmpty)
            .toList(),
    };
  }
  if (network == 'ws') {
    stream['wsSettings'] = {
      'path': path.isEmpty ? '/' : path,
      if (host.isNotEmpty) 'headers': {'Host': host},
    };
  } else if (network == 'grpc') {
    stream['grpcSettings'] = {'serviceName': path};
  } else if (network == 'h2' || network == 'http') {
    stream['httpSettings'] = {
      'path': path.isEmpty ? '/' : path,
      if (host.isNotEmpty) 'host': host.split(',')
          .map((part) => part.trim()).where((part) => part.isNotEmpty).toList(),
    };
  } else if (network == 'httpupgrade') {
    stream['httpupgradeSettings'] = {
      'path': path.isEmpty ? '/' : path,
      if (host.isNotEmpty) 'host': host,
    };
  } else if (network == 'tcp' && value('type').toLowerCase() == 'http') {
    stream['tcpSettings'] = {
      'header': {
        'type': 'http',
        'request': {
          'path': [path.isEmpty ? '/' : path],
          if (host.isNotEmpty) 'headers': {
            'Host': host.split(',').map((part) => part.trim()).toList(),
          },
        },
      },
    };
  }
  return {
    'protocol': 'vmess',
    'settings': {
      'vnext': [{
        'address': address,
        'port': port,
        'users': [{'id': id, 'alterId': aid, 'security': cipher}],
      }],
    },
    'streamSettings': stream,
  };
}
