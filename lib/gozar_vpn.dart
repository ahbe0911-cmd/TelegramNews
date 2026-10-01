import 'dart:convert';

import 'package:flutter/services.dart';

import 'td_vmess_parser.dart';

/// Minimal Xray-only native bridge used from Settings. There is deliberately
/// no WireGuard/OpenVPN surface and no main-navigation VPN page.
class GozarVpnBridge {
  static const MethodChannel channel =
      MethodChannel('ir.channel.telegram_tdnews/gozar_vpn');

  static Future<Map<String, dynamic>> status() async {
    final result =
        await channel.invokeMapMethod<String, dynamic>('status');
    return result ?? const {
      'stage': 'off',
      'detail': 'VPN خاموش است.',
    };
  }

  static Future<void> start(String xrayConfig) async {
    await channel.invokeMethod<String>('start', {'config': xrayConfig});
  }

  static Future<void> stop() =>
      channel.invokeMethod<void>('stop');

  static Future<int?> measureConnection() async {
    final result =
        await channel.invokeMapMethod<String, dynamic>('measureConnection');
    if (result?['ok'] != true) return null;
    final value = result?['latencyMs'];
    return value is num && value >= 0 ? value.toInt() : null;
  }
}

String _decodeShareBase64(String value) {
  var normalized = value.trim().replaceAll(RegExp(r'\\s+'), '')
      .replaceAll('-', '+').replaceAll('_', '/');
  while (normalized.length % 4 != 0) {
    normalized += '=';
  }
  return utf8.decode(base64.decode(normalized));
}

Map<String, dynamic> _parseShadowsocksShare(String input) {
  final uri = Uri.tryParse(input);
  if (uri == null || uri.scheme.toLowerCase() != 'ss') {
    throw const FormatException('لینک Shadowsocks معتبر نیست.');
  }
  if ((uri.queryParameters['plugin'] ?? '').isNotEmpty) {
    throw const FormatException(
        'Shadowsocks دارای plugin در این نسخه پشتیبانی نمی‌شود.');
  }

  String host = uri.host;
  int port = uri.hasPort ? uri.port : 0;
  String credentials = Uri.decodeComponent(uri.userInfo);

  if (host.isEmpty || port < 1) {
    final raw = input.substring(5).split('#').first.split('?').first;
    String decoded;
    try {
      decoded = _decodeShareBase64(Uri.decodeComponent(raw));
    } catch (_) {
      throw const FormatException('ساختار لینک Shadowsocks معتبر نیست.');
    }
    final expanded = Uri.tryParse('ss://$decoded');
    if (expanded == null || expanded.host.isEmpty || !expanded.hasPort) {
      throw const FormatException('آدرس Shadowsocks معتبر نیست.');
    }
    host = expanded.host;
    port = expanded.port;
    credentials = Uri.decodeComponent(expanded.userInfo);
  }

  if (!credentials.contains(':')) {
    try {
      credentials = _decodeShareBase64(credentials);
    } catch (_) {
      throw const FormatException('رمز Shadowsocks قابل خواندن نیست.');
    }
  }
  final separator = credentials.indexOf(':');
  if (separator <= 0 || separator == credentials.length - 1) {
    throw const FormatException('روش رمزگذاری یا رمز Shadowsocks ناقص است.');
  }
  final method = credentials.substring(0, separator);
  final password = credentials.substring(separator + 1);
  if (port < 1 || port > 65535) {
    throw const FormatException('پورت Shadowsocks معتبر نیست.');
  }
  return {
    'protocol': 'shadowsocks',
    'settings': {
      'address': host,
      'port': port,
      'method': method,
      'password': password,
    },
  };
}

/// Converts a VMess/VLESS/Trojan/Shadowsocks share link (or Xray JSON config)
/// into the Android TUN configuration consumed by Xray-core.
String buildGozarXrayConfig(String supplied) {
  final input = supplied.trim();
  if (input.isEmpty) {
    throw const FormatException('لینک یا کانفیگ خالی است.');
  }

  Map<String, dynamic> primary;
  if (input.toLowerCase().startsWith('vmess://')) {
    primary = parseVmessShareLink(input);
  } else if (input.toLowerCase().startsWith('ss://')) {
    primary = _parseShadowsocksShare(input);
  } else if (input.startsWith('{')) {
    final parsed = jsonDecode(input);
    if (parsed is! Map || parsed['outbounds'] is! List) {
      throw const FormatException(
          'کانفیگ Xray باید دارای outbounds باشد.');
    }
    final candidates = parsed['outbounds'] as List;
    final selected = candidates.whereType<Map>().where((candidate) =>
        !const ['freedom', 'blackhole', 'dns']
            .contains(candidate['protocol']));
    if (selected.isEmpty) {
      throw const FormatException(
          'در کانفیگ یک سرور پروکسی پیدا نشد.');
    }
    primary = Map<String, dynamic>.from(selected.first);
  } else {
    final uri = Uri.tryParse(input);
    if (uri == null ||
        uri.host.isEmpty ||
        !uri.hasPort ||
        uri.port < 1 ||
        uri.port > 65535) {
      throw const FormatException(
          'آدرس یا پورت کانفیگ معتبر نیست.');
    }
    final scheme = uri.scheme.toLowerCase();
    final id = Uri.decodeComponent(uri.userInfo);
    if (id.isEmpty) {
      throw const FormatException(
          'شناسه یا رمز سرور خالی است.');
    }

    if (scheme == 'vless') {
      if (!RegExp(
              r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')
          .hasMatch(id)) {
        throw const FormatException('شناسه VLESS معتبر نیست.');
      }
      final params = uri.queryParameters;
      final security =
          (params['security'] ?? 'none').toLowerCase();
      final network = (params['type'] ?? 'tcp').toLowerCase();

      if (!const ['none', 'tls', 'reality'].contains(security)) {
        throw const FormatException(
            'نوع امنیت کانفیگ پشتیبانی نمی‌شود.');
      }
      if (!const ['tcp', 'ws', 'grpc', 'httpupgrade', 'xhttp']
          .contains(network)) {
        throw const FormatException(
            'نوع انتقال این لینک پشتیبانی نمی‌شود.');
      }
      if (params['encryption'] != null &&
          params['encryption'] != 'none') {
        throw const FormatException(
            'رمزگذاری VLESS پشتیبانی نمی‌شود.');
      }
      if (security == 'reality' &&
          (params['pbk'] ?? '').isEmpty) {
        throw const FormatException(
            'کلید عمومی REALITY در لینک وجود ندارد.');
      }

      final user = <String, dynamic>{
        'id': id,
        'encryption': 'none',
      };
      if ((params['flow'] ?? '').isNotEmpty) {
        user['flow'] = params['flow'];
      }

      final stream = <String, dynamic>{
        'network': network,
        'security': security,
      };

      if (security == 'tls') {
        stream['tlsSettings'] = {
          if ((params['sni'] ?? '').isNotEmpty)
            'serverName': params['sni'],
          if ((params['fp'] ?? '').isNotEmpty)
            'fingerprint': params['fp'],
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
        stream[network == 'ws'
            ? 'wsSettings'
            : 'httpupgradeSettings'] = {
          'path': params['path'] ?? '/',
          if ((params['host'] ?? '').isNotEmpty)
            'host': params['host'],
          if (network == 'ws' &&
              (params['host'] ?? '').isNotEmpty)
            'headers': {'Host': params['host']},
        };
      } else if (network == 'grpc') {
        stream['grpcSettings'] = {
          'serviceName': params['serviceName'] ?? '',
        };
      } else if (network == 'xhttp') {
        final mode =
            (params['mode'] ?? 'auto').toLowerCase();
        if (!const [
          'auto',
          'packet-up',
          'stream-up',
          'stream-one',
        ].contains(mode)) {
          throw const FormatException(
              'حالت انتقال XHTTP معتبر نیست.');
        }
        stream['xhttpSettings'] = {
          'path': params['path'] ?? '/',
          'mode': mode,
          if ((params['host'] ?? '').isNotEmpty)
            'host': params['host'],
        };
      }

      primary = {
        'protocol': 'vless',
        'settings': {
          'vnext': [
            {
              'address': uri.host,
              'port': uri.port,
              'users': [user],
            }
          ],
        },
        'streamSettings': stream,
      };
    } else if (scheme == 'trojan') {
      final params = uri.queryParameters;
      final security =
          (params['security'] ?? 'tls').toLowerCase();
      final network = (params['type'] ?? 'tcp').toLowerCase();

      if (security != 'tls') {
        throw const FormatException(
            'Trojan بدون TLS در این نسخه پذیرفته نمی‌شود.');
      }
      if (!const ['tcp', 'ws', 'grpc', 'httpupgrade', 'xhttp']
          .contains(network)) {
        throw const FormatException(
            'نوع انتقال Trojan پشتیبانی نمی‌شود.');
      }

      final stream = <String, dynamic>{
        'security': 'tls',
        'network': network,
        'tlsSettings': {
          'serverName': params['sni'] ?? uri.host,
          'allowInsecure': false,
          if ((params['fp'] ?? '').isNotEmpty)
            'fingerprint': params['fp'],
          if ((params['alpn'] ?? '').isNotEmpty)
            'alpn': params['alpn']!.split(','),
        },
      };

      if (network == 'ws') {
        stream['wsSettings'] = {
          'path': params['path'] ?? '/',
          if ((params['host'] ?? '').isNotEmpty)
            'headers': {'Host': params['host']},
        };
      } else if (network == 'grpc') {
        stream['grpcSettings'] = {
          'serviceName': params['serviceName'] ?? '',
        };
      } else if (network == 'httpupgrade') {
        stream['httpupgradeSettings'] = {
          'path': params['path'] ?? '/',
          if ((params['host'] ?? '').isNotEmpty)
            'host': params['host'],
        };
      } else if (network == 'xhttp') {
        final mode =
            (params['mode'] ?? 'auto').toLowerCase();
        if (!const [
          'auto',
          'packet-up',
          'stream-up',
          'stream-one',
        ].contains(mode)) {
          throw const FormatException(
              'حالت انتقال XHTTP معتبر نیست.');
        }
        stream['xhttpSettings'] = {
          'path': params['path'] ?? '/',
          'mode': mode,
          if ((params['host'] ?? '').isNotEmpty)
            'host': params['host'],
        };
      }

      primary = {
        'protocol': 'trojan',
        'settings': {
          'servers': [
            {
              'address': uri.host,
              'port': uri.port,
              'password': id,
            }
          ],
        },
        'streamSettings': stream,
      };
    } else {
      throw const FormatException(
          'لینک VMess، VLESS، Trojan، Shadowsocks یا JSON معتبر وارد کنید.');
    }
  }

  primary['tag'] = 'proxy';
  return jsonEncode({
    'log': {'loglevel': 'warning'},
    'inbounds': [
      {
        'tag': 'vpn',
        'protocol': 'tun',
        'settings': {
          'name': 'xray0',
          'MTU': 1500,
        },
        'sniffing': {
          'enabled': true,
          'destOverride': ['http', 'tls', 'quic'],
          'routeOnly': true,
        },
      },
      {
        'tag': 'subscription-proxy',
        'listen': '127.0.0.1',
        'port': 17890,
        'protocol': 'http',
        'settings': <String, dynamic>{},
      },
    ],
    'outbounds': [
      primary,
      {
        'tag': 'direct',
        'protocol': 'freedom',
        'settings': <String, dynamic>{},
      },
    ],
    'routing': {
      'domainStrategy': 'IPIfNonMatch',
      'rules': [
        {
          'type': 'field',
          'inboundTag': ['subscription-proxy'],
          'outboundTag': 'proxy',
        },
        {
          'type': 'field',
          'domain': [
            'regexp:.*\\.ir\$',
            'domain:bale.ai',
            'domain:eitaa.com',
            'domain:aparat.com',
            'domain:digikala.com',
            'domain:torob.com',
            'domain:rubika.ir',
            'domain:shad.ir',
            'domain:shadmessenger.com',
          ],
          'outboundTag': 'direct',
        },
        {
          'type': 'field',
          'inboundTag': ['vpn'],
          'outboundTag': 'proxy',
        },
      ],
    },
  });
}

/// Returns a compact protocol label for display only.
String gozarProtocolLabel(String raw) {
  final input = raw.trim().toLowerCase();
  if (input.startsWith('vmess://')) return 'VMess';
  if (input.startsWith('vless://')) return 'VLESS';
  if (input.startsWith('trojan://')) return 'Trojan';
  if (input.startsWith('ss://')) return 'Shadowsocks';
  if (input.startsWith('{')) return 'Xray JSON';
  return 'Xray';
}
