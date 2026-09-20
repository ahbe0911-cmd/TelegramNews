import 'package:flutter/services.dart';

/// Local MTProto relay hosted in the same APK and process as the news reader.
/// Starting the listener alone does not prove that any remote route is reachable.
class EmbeddedTelegramProxy {
  static const MethodChannel channel =
      MethodChannel('ir.channel.telegram_tdnews/embedded_proxy');

  static Future<({String host, int port, String secret})> start() async {
    final response = await channel.invokeMapMethod<String, dynamic>('start');
    if (response == null || response['running'] != true ||
        response['host'] is! String || response['port'] is! int ||
        response['secret'] is! String) {
      throw StateError('Local MTProto proxy could not start');
    }
    return (host: response['host'] as String, port: response['port'] as int,
        secret: response['secret'] as String);
  }

  static Future<void> stop() async {
    await channel.invokeMethod<void>('stop');
  }
}
