import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'td_news_engine.dart';

/// TG WS Proxy's native service belongs to its own Android app.
/// The service is private, so only its UI may start it. This adapter does
/// not claim to start an unexported service from another application.
class TdWsProxyController extends ChangeNotifier {
  static const int port = 1080;
  static const MethodChannel _launcher =
      MethodChannel('ir.channel.telegram_tdnews/tgws');
  final TdNewsController news;
  bool connected = false;
  bool busy = false;
  String status = 'اتصال مستقیم تلگرام؛ پراکسی اختیاری است.';
  bool disposed = false;
  TdWsProxyController(this.news);

  void _notify() { if (!disposed) notifyListeners(); }

  /// Probe a SOCKS5 handshake rather than confusing an unrelated open port
  /// with a usable local proxy.
  Future<bool> _ready() async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        InternetAddress.loopbackIPv4, port,
        timeout: const Duration(milliseconds: 450),
      );
      socket.add([5, 1, 0]);
      final reply = await socket.first.timeout(const Duration(milliseconds: 600));
      return reply.length >= 2 && reply[0] == 5 && reply[1] == 0;
    } catch (_) {
      return false;
    } finally {
      socket?.destroy();
    }
  }

  Future<void> connectOrOpen() async {
    if (busy) return;
    busy = true;
    _notify();
    try {
      if (news.state != 'authorizationStateReady') {
        status = 'ابتدا وارد حساب تلگرام شوید.';
        return;
      }
      if (await _ready()) {
        await news.enableLocalProxy(port: port);
        connected = true;
        status = 'متصل به TG WS Proxy؛ اخبار را تازه‌سازی کنید.';
        return;
      }
      // A separately installed TG WS Proxy has an unexported service. Android
      // does not permit another application to start it without user action.
      connected = false;
      status = 'TG WS Proxy را باز کنید و Start را بزنید؛ سپس به نبض خبر برگردید.';
      try {
        await _launcher.invokeMethod<void>('open');
      } on PlatformException {
        status = 'برنامه TG WS Proxy روی گوشی نصب نیست یا نسخه متفاوتی دارد.';
      } on MissingPluginException {
        status = 'نسخه فعلی اندروید امکان بازکردن TG WS Proxy را ندارد.';
      }
    } catch (_) {
      connected = false;
      status = 'اتصال برقرار نشد؛ تنظیمات پراکسی را بررسی کنید.';
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
      await news.disableLocalProxy();
      connected = false;
      status = 'اتصال مستقیم تلگرام فعال شد.';
    } catch (_) {
      status = 'قطع پراکسی انجام نشد؛ دوباره تلاش کنید.';
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
