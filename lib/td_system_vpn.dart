import 'dart:convert';

import 'package:flutter/services.dart';

/// A device VPN needs both a native VpnService and a real TUN-capable core.
/// This bridge reports only Android/core state, not remote server reachability.
class SystemVpnBridge {
  static const MethodChannel channel =
      MethodChannel('ir.channel.telegram_tdnews/system_vpn');

  static Future<Map<String, dynamic>> status() async {
    final result = await channel.invokeMapMethod<String, dynamic>('status');
    return result ?? {'stage': 'off', 'detail': 'VPN خاموش است.'};
  }

  static Future<void> start(String xrayConfig) async {
    await channel.invokeMethod<String>('start', {'config': xrayConfig});
  }

  static Future<void> stop() async {
    await channel.invokeMethod<void>('stop');
  }
}

/// VMess share links used by V2Ray clients are UTF-8 JSON encoded as base64.
/// Decode the common vmess://<base64 JSON> format without exposing credentials
/// to logs, the URL parser, or any remote service.
Map<String, dynamic> _vmessShareOutbound(String link) {
  final encoded = link.substring('vmess://'.length)
      .split('#').first.split('?').first.trim();
  if (encoded.isEmpty || encoded.length > 65536) {
    throw const FormatException('لینک VMess خالی یا بیش از حد طولانی است.');
  }
  Map<String, dynamic> profile;
  try {
    final b64 = base64.normalize(encoded.replaceAll('-', '+')
        .replaceAll('_', '/').replaceAll(RegExp(r'\s'), ''));
    final decoded = jsonDecode(utf8.decode(base64.decode(b64)));
    if (decoded is! Map) throw const FormatException();
    profile = Map<String, dynamic>.from(decoded);
  } catch (_) {
    throw const FormatException(
        'لینک VMess معتبر نیست؛ لینک اشتراک‌گذاری کامل vmess:// را وارد کنید.');
  }

  String field(String key) => profile[key]?.toString().trim() ?? '';
  final address = field('add');
  final port = int.tryParse(field('port'));
  final userId = field('id');
  final alterId = int.tryParse(field('aid').isEmpty ? '0' : field('aid'));
  if (address.isEmpty || address.length > 255 ||
      port == null || port < 1 || port > 65535 ||
      !RegExp(r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}
String buildFullDeviceXrayConfig(String supplied) {
  final input = supplied.trim();
  if (input.isEmpty) {
    throw const FormatException('لینک یا کانفیگ خالی است.');
  }
  Map<String, dynamic> primary;
  if (input.toLowerCase().startsWith('vmess://')) {
    primary = _vmessShareOutbound(input);
  } else if (input.startsWith('{')) {
    final parsed = jsonDecode(input);
    if (parsed is! Map || parsed['outbounds'] is! List) {
      throw const FormatException('کانفیگ Xray باید دارای outbounds باشد.');
    }
    final candidates = parsed['outbounds'] as List;
    final selected = candidates.whereType<Map>().where((candidate) =>
        !const ['freedom', 'blackhole', 'dns'].contains(candidate['protocol']));
    if (selected.isEmpty) {
      throw const FormatException('در کانفیگ یک سرور پروکسی پیدا نشد.');
    }
    primary = Map<String, dynamic>.from(selected.first);
  } else {
    final uri = Uri.tryParse(input);
    if (uri == null || uri.host.isEmpty || !uri.hasPort ||
        uri.port < 1 || uri.port > 65535) {
      throw const FormatException('آدرس یا پورت کانفیگ معتبر نیست.');
    }
    final scheme = uri.scheme.toLowerCase();
    final id = Uri.decodeComponent(uri.userInfo);
    if (id.isEmpty) throw const FormatException('شناسه یا رمز سرور خالی است.');
    if (scheme == 'vless') {
      if (!RegExp(r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')
          .hasMatch(id)) {
        throw const FormatException('شناسه VLESS معتبر نیست.');
      }
      final params = uri.queryParameters;
      final security = (params['security'] ?? 'none').toLowerCase();
      final network = (params['type'] ?? 'tcp').toLowerCase();
      if (!const ['none', 'tls', 'reality'].contains(security)) {
        throw const FormatException('نوع امنیت کانفیگ پشتیبانی نمی‌شود.');
      }
      if (!const ['tcp', 'ws', 'grpc', 'httpupgrade'].contains(network)) {
        throw const FormatException('نوع انتقال این لینک پشتیبانی نمی‌شود.');
      }
      if (params['encryption'] != null && params['encryption'] != 'none') {
        throw const FormatException('رمزگذاری VLESS پشتیبانی نمی‌شود.');
      }
      if (security == 'reality' && (params['pbk'] ?? '').isEmpty) {
        throw const FormatException('کلید عمومی REALITY در لینک وجود ندارد.');
      }
      final user = <String, dynamic>{'id': id, 'encryption': 'none'};
      if ((params['flow'] ?? '').isNotEmpty) user['flow'] = params['flow'];
      final stream = <String, dynamic>{
        'network': network, 'security': security,
      };
      if (security == 'tls') {
        stream['tlsSettings'] = {
          if ((params['sni'] ?? '').isNotEmpty) 'serverName': params['sni'],
          if ((params['fp'] ?? '').isNotEmpty) 'fingerprint': params['fp'],
          if ((params['alpn'] ?? '').isNotEmpty)
            'alpn': params['alpn']!.split(','),
          'allowInsecure': false,
        };
      }
      if (security == 'reality') {
        stream['realitySettings'] = {
          'serverName': params['sni'] ?? uri.host,
          'fingerprint': params['fp'] ?? 'chrome',
          'publicKey': params['pbk'],
          'shortId': params['sid'] ?? '',
          'spiderX': params['spx'] ?? '/',
        };
      }
      if (network == 'ws' || network == 'httpupgrade') {
        stream[network == 'ws' ? 'wsSettings' : 'httpupgradeSettings'] = {
          'path': params['path'] ?? '/',
          if ((params['host'] ?? '').isNotEmpty)
            'host': params['host'],
          if (network == 'ws' && (params['host'] ?? '').isNotEmpty)
            'headers': {'Host': params['host']},
        };
      } else if (network == 'grpc') {
        stream['grpcSettings'] = {'serviceName': params['serviceName'] ?? ''};
      }
      primary = {
        'protocol': 'vless',
        'settings': {'vnext': [{
          'address': uri.host, 'port': uri.port, 'users': [user],
        }]},
        'streamSettings': stream,
      };
    } else if (scheme == 'trojan') {
      final params = uri.queryParameters;
      final security = (params['security'] ?? 'tls').toLowerCase();
      if (security != 'tls') {
        throw const FormatException('این نسخه Trojan با TLS را می‌پذیرد.');
      }
      final network = (params['type'] ?? 'tcp').toLowerCase();
      if (!const ['tcp', 'ws'].contains(network)) {
        throw const FormatException('این انتقال Trojan پشتیبانی نمی‌شود.');
      }
      primary = {
        'protocol': 'trojan',
        'settings': {'servers': [{
          'address': uri.host, 'port': uri.port, 'password': id,
        }]},
        'streamSettings': {
          'security': 'tls', 'network': network,
          'tlsSettings': {
            'serverName': params['sni'] ?? uri.host,
            'allowInsecure': false,
            if ((params['fp'] ?? '').isNotEmpty) 'fingerprint': params['fp'],
          },
          if (network == 'ws') 'wsSettings': {
            'path': params['path'] ?? '/',
            if ((params['host'] ?? '').isNotEmpty)
              'headers': {'Host': params['host']},
          },
        },
      };
    } else {
      throw const FormatException(
        'لینک VMess، VLESS، Trojan یا کانفیگ کامل JSON پشتیبانی می‌شود.');
    }
  }
  primary['tag'] = 'proxy';
  // An Android VpnService fd is connected to this real Xray TUN inbound.
  // SOCKS loopback additionally routes Telegram of the VPN-owning app, whose
  // package must bypass the Android VPN to prevent the core's socket loops.
  return jsonEncode({
    'log': {'loglevel': 'warning'},
    'inbounds': [
      {'tag': 'vpn', 'protocol': 'tun',
       'settings': {'name': 'xray0', 'MTU': 1500}},
      {'tag': 'local-socks', 'listen': '127.0.0.1', 'port': 10808,
       'protocol': 'socks', 'settings': {'auth': 'noauth', 'udp': true}},
    ],
    'outbounds': [primary],
    'routing': {'domainStrategy': 'AsIs', 'rules': [
      {'type': 'field', 'inboundTag': ['vpn', 'local-socks'],
       'outboundTag': 'proxy'},
    ]},
  });
}
)
          .hasMatch(userId) ||
      alterId == null || alterId < 0 || alterId > 65535) {
    throw const FormatException('آدرس، پورت یا شناسه حساب VMess معتبر نیست.');
  }
  final cipher = field('scy').isEmpty ? 'auto' : field('scy').toLowerCase();
  if (!const ['auto', 'aes-128-gcm', 'chacha20-poly1305', 'none',
              'zero'].contains(cipher)) {
    throw const FormatException('روش رمزگذاری این لینک VMess پشتیبانی نمی‌شود.');
  }
  final net = field('net').isEmpty ? 'tcp' : field('net').toLowerCase();
  if (!const ['tcp', 'ws', 'grpc', 'h2', 'http', 'httpupgrade'].contains(net)) {
    throw const FormatException('نوع انتقال این لینک VMess پشتیبانی نمی‌شود.');
  }
  final tls = field('tls').toLowerCase();
  if (!const ['', 'none', 'tls'].contains(tls)) {
    throw const FormatException('نوع امنیت این لینک VMess پشتیبانی نمی‌شود.');
  }
  final stream = <String, dynamic>{
    'network': net == 'h2' ? 'http' : net,
    'security': tls == 'tls' ? 'tls' : 'none',
  };
  final host = field('host');
  final path = field('path');
  if (tls == 'tls') {
    final sni = field('sni').isNotEmpty ? field('sni')
        : host.split(',').first.trim().isNotEmpty
            ? host.split(',').first.trim()
            : address;
    stream['tlsSettings'] = <String, dynamic>{
      'serverName': sni,
      'allowInsecure': false,
      if (field('fp').isNotEmpty) 'fingerprint': field('fp'),
      if (field('alpn').isNotEmpty) 'alpn':
          field('alpn').split(',').map((e) => e.trim())
              .where((e) => e.isNotEmpty).toList(),
    };
  }
  if (net == 'ws') {
    stream['wsSettings'] = <String, dynamic>{
      'path': path.isEmpty ? '/' : path,
      if (host.isNotEmpty) 'headers': {'Host': host},
    };
  } else if (net == 'grpc') {
    stream['grpcSettings'] = {'serviceName': path};
  } else if (net == 'h2' || net == 'http') {
    stream['httpSettings'] = <String, dynamic>{
      'path': path.isEmpty ? '/' : path,
      if (host.isNotEmpty) 'host':
          host.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty)
              .toList(),
    };
  } else if (net == 'httpupgrade') {
    stream['httpupgradeSettings'] = <String, dynamic>{
      'path': path.isEmpty ? '/' : path,
      if (host.isNotEmpty) 'host': host,
    };
  } else if (net == 'tcp' && field('type').toLowerCase() == 'http') {
    stream['tcpSettings'] = {
      'header': {
        'type': 'http',
        'request': {
          'path': [path.isEmpty ? '/' : path],
          if (host.isNotEmpty) 'headers': {
            'Host': host.split(',').map((e) => e.trim()).toList(),
          },
        },
      },
    };
  }
  return {
    'protocol': 'vmess',
    'settings': {
      'vnext': [{
        'address': address, 'port': port,
        'users': [{'id': userId, 'alterId': alterId, 'security': cipher}],
      }],
    },
    'streamSettings': stream,
  };
}

/// Supported: VMess share links, VLESS, Trojan, and an Xray JSON outbound.
/// Reject unsupported links rather than pretend that they are connected.
String buildFullDeviceXrayConfig(String supplied) {
  final input = supplied.trim();
  if (input.isEmpty) {
    throw const FormatException('لینک یا کانفیگ خالی است.');
  }
  Map<String, dynamic> primary;
  if (input.startsWith('{')) {
    final parsed = jsonDecode(input);
    if (parsed is! Map || parsed['outbounds'] is! List) {
      throw const FormatException('کانفیگ Xray باید دارای outbounds باشد.');
    }
    final candidates = parsed['outbounds'] as List;
    final selected = candidates.whereType<Map>().where((candidate) =>
        !const ['freedom', 'blackhole', 'dns'].contains(candidate['protocol']));
    if (selected.isEmpty) {
      throw const FormatException('در کانفیگ یک سرور پروکسی پیدا نشد.');
    }
    primary = Map<String, dynamic>.from(selected.first);
  } else {
    final uri = Uri.tryParse(input);
    if (uri == null || uri.host.isEmpty || !uri.hasPort ||
        uri.port < 1 || uri.port > 65535) {
      throw const FormatException('آدرس یا پورت کانفیگ معتبر نیست.');
    }
    final scheme = uri.scheme.toLowerCase();
    final id = Uri.decodeComponent(uri.userInfo);
    if (id.isEmpty) throw const FormatException('شناسه یا رمز سرور خالی است.');
    if (scheme == 'vless') {
      if (!RegExp(r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')
          .hasMatch(id)) {
        throw const FormatException('شناسه VLESS معتبر نیست.');
      }
      final params = uri.queryParameters;
      final security = (params['security'] ?? 'none').toLowerCase();
      final network = (params['type'] ?? 'tcp').toLowerCase();
      if (!const ['none', 'tls', 'reality'].contains(security)) {
        throw const FormatException('نوع امنیت کانفیگ پشتیبانی نمی‌شود.');
      }
      if (!const ['tcp', 'ws', 'grpc', 'httpupgrade'].contains(network)) {
        throw const FormatException('نوع انتقال این لینک پشتیبانی نمی‌شود.');
      }
      if (params['encryption'] != null && params['encryption'] != 'none') {
        throw const FormatException('رمزگذاری VLESS پشتیبانی نمی‌شود.');
      }
      if (security == 'reality' && (params['pbk'] ?? '').isEmpty) {
        throw const FormatException('کلید عمومی REALITY در لینک وجود ندارد.');
      }
      final user = <String, dynamic>{'id': id, 'encryption': 'none'};
      if ((params['flow'] ?? '').isNotEmpty) user['flow'] = params['flow'];
      final stream = <String, dynamic>{
        'network': network, 'security': security,
      };
      if (security == 'tls') {
        stream['tlsSettings'] = {
          if ((params['sni'] ?? '').isNotEmpty) 'serverName': params['sni'],
          if ((params['fp'] ?? '').isNotEmpty) 'fingerprint': params['fp'],
          if ((params['alpn'] ?? '').isNotEmpty)
            'alpn': params['alpn']!.split(','),
          'allowInsecure': false,
        };
      }
      if (security == 'reality') {
        stream['realitySettings'] = {
          'serverName': params['sni'] ?? uri.host,
          'fingerprint': params['fp'] ?? 'chrome',
          'publicKey': params['pbk'],
          'shortId': params['sid'] ?? '',
          'spiderX': params['spx'] ?? '/',
        };
      }
      if (network == 'ws' || network == 'httpupgrade') {
        stream[network == 'ws' ? 'wsSettings' : 'httpupgradeSettings'] = {
          'path': params['path'] ?? '/',
          if ((params['host'] ?? '').isNotEmpty)
            'host': params['host'],
          if (network == 'ws' && (params['host'] ?? '').isNotEmpty)
            'headers': {'Host': params['host']},
        };
      } else if (network == 'grpc') {
        stream['grpcSettings'] = {'serviceName': params['serviceName'] ?? ''};
      }
      primary = {
        'protocol': 'vless',
        'settings': {'vnext': [{
          'address': uri.host, 'port': uri.port, 'users': [user],
        }]},
        'streamSettings': stream,
      };
    } else if (scheme == 'trojan') {
      final params = uri.queryParameters;
      final security = (params['security'] ?? 'tls').toLowerCase();
      if (security != 'tls') {
        throw const FormatException('این نسخه Trojan با TLS را می‌پذیرد.');
      }
      final network = (params['type'] ?? 'tcp').toLowerCase();
      if (!const ['tcp', 'ws'].contains(network)) {
        throw const FormatException('این انتقال Trojan پشتیبانی نمی‌شود.');
      }
      primary = {
        'protocol': 'trojan',
        'settings': {'servers': [{
          'address': uri.host, 'port': uri.port, 'password': id,
        }]},
        'streamSettings': {
          'security': 'tls', 'network': network,
          'tlsSettings': {
            'serverName': params['sni'] ?? uri.host,
            'allowInsecure': false,
            if ((params['fp'] ?? '').isNotEmpty) 'fingerprint': params['fp'],
          },
          if (network == 'ws') 'wsSettings': {
            'path': params['path'] ?? '/',
            if ((params['host'] ?? '').isNotEmpty)
              'headers': {'Host': params['host']},
          },
        },
      };
    } else {
      throw const FormatException(
        'فعلاً لینک VLESS، Trojan یا کانفیگ کامل JSON پشتیبانی می‌شود.');
    }
  }
  primary['tag'] = 'proxy';
  // An Android VpnService fd is connected to this real Xray TUN inbound.
  // SOCKS loopback additionally routes Telegram of the VPN-owning app, whose
  // package must bypass the Android VPN to prevent the core's socket loops.
  return jsonEncode({
    'log': {'loglevel': 'warning'},
    'inbounds': [
      {'tag': 'vpn', 'protocol': 'tun',
       'settings': {'name': 'xray0', 'MTU': 1500}},
      {'tag': 'local-socks', 'listen': '127.0.0.1', 'port': 10808,
       'protocol': 'socks', 'settings': {'auth': 'noauth', 'udp': true}},
    ],
    'outbounds': [primary],
    'routing': {'domainStrategy': 'AsIs', 'rules': [
      {'type': 'field', 'inboundTag': ['vpn', 'local-socks'],
       'outboundTag': 'proxy'},
    ]},
  });
}
