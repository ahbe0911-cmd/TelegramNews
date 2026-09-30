import 'package:flutter/services.dart';

/// Native Android helpers used by Gozar's launcher and private HTTPS browser.
/// This bridge intentionally contains no VPN, proxy, tunnel, or network-routing API.
class GozarPlatformBridge {
  static const MethodChannel channel =
      MethodChannel('ir.channel.telegram_tdnews/gozar_platform');

  static Future<List<Map<String, String>>> installedApps() async {
    final response = await channel.invokeListMethod<dynamic>('installedApps');
    if (response == null) return [];
    return response.whereType<Map>().map((raw) => <String, String>{
      'package': raw['package']?.toString() ?? '',
      if ((raw['component']?.toString() ?? '').isNotEmpty)
        'component': raw['component'].toString(),
      'label': raw['label']?.toString() ?? '',
    }).where((app) =>
        app['package']!.isNotEmpty && app['label']!.isNotEmpty).toList();
  }

  static Future<void> openShortcutApp(String packageName,
      {String component = ''}) => channel.invokeMethod<void>(
      'openShortcutApp', {'package': packageName, 'component': component});

  static Future<void> openShortcutWeb(String url, String title) =>
      channel.invokeMethod<void>('openShortcutWeb', {
        'url': url,
        'title': title,
      });
}
