import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'td_news_engine.dart';

/// All WebSocket and SOCKS5 networking happens in this app's own Android
/// process. No external proxy app, VPN permission or user-supplied server.
class TdWsProxyController extends ChangeNotifier {
  static const int port = 17881;
  static const MethodChannel _native =
      MethodChannel('ir.channel.telegram_tdnews/ws_internal');
  final TdNewsController news;
  bool connected = false;
  bool busy = false;
  bool disposed = false;
  String status = 'اتصال مستقیم؛ WebSocket در صورت نیاز فعال می‌شود.';

  TdWsProxyController(this.news);
  void _notify() { if (!disposed) notifyListeners(); }

  /// Check an actual SOCKS5 greeting, not just an open unrelated socket.
  Future<bool> _ready() async {
    Socket? socket;
    try {
      socket = await Socket.connect(
          InternetAddress.loopbackIPv4, port,
          timeout: const Duration(milliseconds: 350));
      socket.add([5, 1, 0]);
      final reply = await socket.first.timeout(const Duration(milliseconds: 450));
      return reply.length >= 2 && reply[0] == 5 && reply[1] == 0;
    } catch (_) {
      return false;
    } finally {
      socket?.destroy();
    }
  }

  /// The explicit button and the stored auto-connect preference share one path.
  Future<void> connectOrOpen({bool automatic = false}) async {
    if (busy || connected) return;
    busy = true;
    status = 'در حال آماده‌سازی WebSocket داخلی…';
    _notify();
    var nativeStarted = false;
    try {
      if (news.state != 'authorizationStateReady') {
        status = 'ابتدا وارد حساب تلگرام شوید.';
        return;
      }
      final started = await _native.invokeMethod<bool>('start');
      if (started != true) throw StateError('Embedded proxy unavailable');
      nativeStarted = true;
      var listening = false;
      for (var attempt = 0; attempt < 24; attempt++) {
        if (await _ready()) { listening = true; break; }
        await Future<void>.delayed(const Duration(milliseconds: 170));
      }
      if (!listening) throw StateError('SOCKS5 listener not ready');
      await news.enableLocalProxy(port: port);
      connected = true;
      await news.prefs.setBool('td_ws_auto', true);
      status = 'WebSocket داخلی فعال شد؛ تلگرام از مسیر محلی وصل می‌شود.';
    } catch (_) {
      // Do not strand TDLib behind a failed, restarted or unavailable proxy.
      try { await news.disableLocalProxy(); } catch (_) {}
      if (nativeStarted) {
        try { await _native.invokeMethod<void>('stop'); } catch (_) {}
      }
      connected = false;
      status = automatic
          ? 'WebSocket آماده نشد؛ اتصال مستقیم حفظ شد.'
          : 'اتصال داخلی برقرار نشد؛ دوباره تلاش کنید.';
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> disconnect() async {
    if (busy) return;
    busy = true;
    _notify();
    try {
      // Set the preference first: subsequent app launches must stay direct.
      await news.prefs.setBool('td_ws_auto', false);
      try { await news.disableLocalProxy(); } finally {
        await _native.invokeMethod<void>('stop');
      }
      connected = false;
      status = 'WebSocket غیرفعال شد؛ اتصال مستقیم تلگرام برقرار است.';
    } catch (_) {
      status = 'قطع خودکار انجام نشد؛ وضعیت اتصال را بررسی کنید.';
    } finally {
      busy = false;
      _notify();
    }
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}
