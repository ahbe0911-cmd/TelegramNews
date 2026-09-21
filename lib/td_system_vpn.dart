import 'dart:convert';

import 'td_vmess_parser.dart';

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

  static Future<void> start(String xrayConfig,
      {String mode = 'all', List<String> packages = const []}) async {
    await channel.invokeMethod<String>('start', {
      'config': xrayConfig, 'mode': mode, 'packages': packages,
    });
  }

  /// Android 11+ exposes only launchable apps granted visibility in manifest.
  static Future<List<Map<String, String>>> installedApps() async {
    final response = await channel.invokeListMethod<dynamic>('installedApps');
    if (response == null) return [];
    return response.whereType<Map>().map((raw) => <String, String>{
      'package': raw['package']?.toString() ?? '',
      'label': raw['label']?.toString() ?? '',
    }).where((app) =>
        app['package']!.isNotEmpty && app['label']!.isNotEmpty).toList();
  }

  static Future<void> stop() async {
    await channel.invokeMethod<void>('stop');
  }

  /// Approximate device counters of Gozar's own Android UID, not total
  /// forwarded VPN traffic and not a measurement of remote server speed.
  static Future<Map<String, int>> networkCounters() async {
    final data = await channel.invokeMapMethod<String, dynamic>(
        'networkCounters');
    return {
      'rx': (data?['rx'] as num?)?.toInt() ?? -1,
      'tx': (data?['tx'] as num?)?.toInt() ?? -1,
    };
  }

  /// Opens Android's system VPN settings. Always-on and "Block connections
  /// without VPN" are user-controlled OS settings, not fake in-app toggles.
  static Future<void> openVpnSettings() =>
      channel.invokeMethod<void>('openVpnSettings');

  /// A separate Android process hosts SOCKS-only Xray. It has no TUN fd and
  /// cannot intercept its own outbound traffic; it reuses the selected server.
  static Future<void> startInternal(String config) async {
    await channel.invokeMethod<void>('startInternal', {'config': config});
  }

  static Future<void> stopInternal() async {
    await channel.invokeMethod<void>('stopInternal');
  }
}

/// Supported: VMess, VLESS, Trojan share links and Xray JSON.
/// Reject unsupported links rather than claim they are connected.
String buildFullDeviceXrayConfig(String supplied) {
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


/// Creates a second, SOCKS-only core config using the SAME proxy outbound
/// selected for Android's system-wide VPN, but no TUN or Android VPN service.
/// The remote Android process has its own Go runtime (unlike starting two
/// controllers in the main process, which would share the global TUN fd key).
String buildInternalTelegramXrayConfig(String fullDeviceConfig) {
  final parsed = jsonDecode(fullDeviceConfig);
  if (parsed is! Map || parsed['outbounds'] is! List ||
      (parsed['outbounds'] as List).isEmpty) {
    throw const FormatException('کانفیگ داخلی Xray ناقص است.');
  }
  final proxy = (parsed['outbounds'] as List).first;
  if (proxy is! Map || proxy['protocol'] is! String) {
    throw const FormatException('سرور Xray داخلی معتبر نیست.');
  }
  return jsonEncode({
    'log': {'loglevel': 'warning'},
    'inbounds': [
      {'tag': 'telegram-socks', 'listen': '127.0.0.1', 'port': 10809,
        'protocol': 'socks', 'settings': {'auth': 'noauth', 'udp': true}},
    ],
    'outbounds': parsed['outbounds'],
    'routing': {
      'domainStrategy': 'AsIs',
      'rules': [
        {'type': 'field', 'inboundTag': ['telegram-socks'],
         'outboundTag': proxy['tag'] ?? 'proxy'},
      ],
    },
  });
}
