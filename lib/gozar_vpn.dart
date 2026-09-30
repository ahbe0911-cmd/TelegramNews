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

/// Converts a VMess/VLESS/Trojan share link (or Xray JSON config) into the
/// Android TUN configuration consumed by Xray-core.
String buildGozarXrayConfig(String supplied) {
  final input = supplied.trim();
  if (input.isEmpty) {
    throw const FormatException('لینک یا کانفیگ خالی است.');
  }

  Map<String, dynamic> primary;
  if (input.toLowerCase().startsWith('vmess://')) {
    primary = parseVmessShareLink(input);
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
          'لینک VMess، VLESS، Trojan یا JSON معتبر وارد کنید.');
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
      },
    ],
    'outbounds': [primary],
    'routing': {
      'domainStrategy': 'AsIs',
      'rules': [
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
  if (input.startsWith('{')) return 'Xray JSON';
  return 'Xray';
}
