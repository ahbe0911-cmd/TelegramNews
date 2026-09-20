import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_v2ray/flutter_v2ray.dart';

import 'td_news_engine.dart';

/// The Xray daemon starts only after the user explicitly connects in Settings.
/// Only TDLib is routed through its localhost SOCKS5 inbound (not a device VPN).
class TdV2rayController extends ChangeNotifier {
  static const int socksPort = 17881;
  static const vault = FlutterSecureStorage();
  final TdNewsController news;
  late final FlutterV2ray _core = FlutterV2ray(
    onStatusChanged: (_) {
      // Avoid rebuilding the feed in response to noisy native traffic updates.
    },
  );
  bool connected = false;
  bool busy = false;
  String status = 'غیرفعال؛ اتصال مستقیم تلگرام';
  bool _initialized = false;
  bool _disposed = false;

  TdV2rayController(this.news);

  void _notify() { if (!_disposed) notifyListeners(); }

  /// Read a previously saved secret only when opening settings; never log it.
  Future<String?> readSavedLink() => vault.read(key: 'td_v2ray_link');

  Future<void> connect(String input) async {
    if (busy || connected) return;
    final link = input.trim();
    if (!RegExp(r'^(vless|vmess|trojan|ss)://', caseSensitive: false).hasMatch(link)) {
      throw FormatException('فقط لینک‌های vless، vmess، trojan یا ss قابل استفاده‌اند.');
    }
    busy = true;
    status = 'در حال فعال‌سازی اتصال داخلی…';
    _notify();
    var started = false;
    try {
      if (news.state != 'authorizationStateReady') {
        throw StateError('ابتدا به حساب تلگرام وارد شوید.');
      }
      // Avoid routing TDLib through an arbitrary daemon using our fixed port.
      if (await _portOpen()) {
        throw StateError('درگاه پراکسی داخلی مشغول است؛ اتصال دیگری را ببندید.');
      }
      final parser = FlutterV2ray.parseFromURL(link);
      parser.inbound['listen'] = '127.0.0.1';
      parser.inbound['port'] = socksPort;
      parser.log['loglevel'] = 'error';
      final config = Map<String, dynamic>.from(
          jsonDecode(parser.getFullConfiguration()) as Map);
      final outbound = config['outbounds'];
      if (outbound is List) {
        for (final candidate in outbound) {
          if (candidate is! Map) continue;
          final stream = candidate['streamSettings'];
          if (stream is! Map) continue;
          for (final name in ['tlsSettings', 'realitySettings']) {
            final security = stream[name];
            if (security is Map) {
              security['allowInsecure'] = false;
            }
          }
        }
      }
      if (!_initialized) {
        await _core.initializeV2Ray();
        _initialized = true;
      }
      await _core.startV2Ray(
        remark: 'نبض خبر',
        config: jsonEncode(config),
        proxyOnly: true,
      );
      started = true;
      // Native proxy startup is asynchronous. Do not apply TDLib proxy until
      // its actual local listener is ready.
      var ready = false;
      for (var attempt = 0; attempt < 35; attempt++) {
        if (await _portOpen()) { ready = true; break; }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      if (!ready) throw StateError('پراکسی داخلی راه‌اندازی نشد.');
      await news.enableLocalProxy(port: socksPort);
      connected = true;
      await vault.write(key: 'td_v2ray_link', value: link);
      status = 'متصل؛ فقط ارتباط تلگرام از پراکسی داخلی می‌گذرد.';
    } catch (_) {
      // Never include the connection URL, password, or raw exception in logs.
      if (started) {
        try { await news.disableLocalProxy(); } catch (_) {}
        try { await _core.stopV2Ray(); } catch (_) {}
      }
      connected = false;
      status = 'اتصال ناموفق بود؛ آدرس و دسترسی سرور را بررسی کنید.';
      rethrow;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<bool> _portOpen() async {
    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        socksPort,
        timeout: const Duration(milliseconds: 200),
      );
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> disconnect() async {
    if (busy || !connected) return;
    busy = true;
    status = 'در حال قطع اتصال داخلی…';
    _notify();
    try {
      await news.disableLocalProxy();
      await _core.stopV2Ray();
      connected = false;
      status = 'اتصال مستقیم تلگرام فعال شد.';
    } catch (_) {
      status = 'قطع اتصال انجام نشد؛ دوباره تلاش کنید.';
      rethrow;
    } finally {
      busy = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
