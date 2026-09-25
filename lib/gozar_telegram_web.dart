import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'gozar_visuals.dart';

/// Official Telegram Web K runs in the retained Android WebView. MTProto
/// proxy setup is delegated to an installed Telegram app, not the website.
class GozarTelegramWeb extends StatefulWidget {
  final bool active;

  /// Test-only substitute: avoids creating an Android platform view in CI.
  @visibleForTesting
  final Widget? testWebPage;

  const GozarTelegramWeb({
    super.key,
    required this.active,
    this.testWebPage,
  });

  @override
  State<GozarTelegramWeb> createState() => _GozarTelegramWebState();
}

class _GozarTelegramWebState extends State<GozarTelegramWeb> {
  static const controls =
      MethodChannel('ir.channel.telegram_tdnews/gozar_telegram_controls');
  static const events =
      MethodChannel('ir.channel.telegram_tdnews/gozar_telegram_events');

  bool loadFailed = false;
  int? loadMs;
  bool useAppFont = true;

  @override
  void initState() {
    super.initState();
    events.setMethodCallHandler(_onNativeEvent);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _setActive();
    });
  }

  Future<void> _onNativeEvent(MethodCall event) async {
    if (!mounted) return;
    if (event.method == 'loaded') {
      final data = event.arguments;
      setState(() {
        loadFailed = false;
        if (data is Map && data['durationMs'] is num) {
          loadMs = (data['durationMs'] as num).toInt();
        }
      });
    } else if (event.method == 'error') {
      setState(() => loadFailed = true);
    } else if (event.method == 'downloadStarted' ||
        event.method == 'downloadSaved' ||
        event.method == 'downloadError') {
      if (!widget.active) return;
      final gallery = event.arguments is Map &&
          (event.arguments as Map)['gallery'] == true;
      final message = event.method == 'downloadStarted'
          ? 'دانلود فایل شروع شد…'
          : event.method == 'downloadSaved'
              ? gallery ? 'عکس یا ویدئو در گالری ذخیره شد.'
                  : 'فایل در پوشه دانلودها ذخیره شد.'
              : 'ذخیره فایل ممکن نشد؛ مرورگر گوشی را امتحان کنید.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message),
          duration: const Duration(seconds: 3)));
    }
  }

  void _setActive({bool? override}) {
    unawaited(controls.invokeMethod<void>(
      'setActive', {'active': override ?? widget.active},
    ).catchError((Object _) {
      // Unit tests have no Android host.
    }));
  }

  @override
  void didUpdateWidget(covariant GozarTelegramWeb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _setActive();
  }

  @override
  void dispose() {
    _setActive(override: false);
    events.setMethodCallHandler(null);
    super.dispose();
  }

  void _reload() {
    setState(() {
      loadFailed = false;
      loadMs = null;
    });
    unawaited(controls.invokeMethod<void>('reload')
      .catchError((Object _) {}));
  }

  void _openInBrowser() {
    unawaited(controls.invokeMethod<void>('openExternal')
      .catchError((Object _) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('مرورگر گوشی در دسترس نیست.')));
        }
      }));
  }


  void _toggleAppFont() {
    setState(() { useAppFont = !useAppFont; });
    unawaited(controls.invokeMethod<void>('setFontEnabled', {
      'enabled': useAppFont,
    }).catchError((Object _) {}));
  }

  Future<void> _configureMtproto() async {
    final server = TextEditingController();
    final port = TextEditingController(text: '443');
    final secret = TextEditingController();
    final form = GlobalKey<FormState>();
    try {
      final selected = await showDialog<Map<String, Object>>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('پروکسی MTProto'),
          content: SingleChildScrollView(child: Form(
            key: form,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text(
                'این پروکسی در برنامه تلگرام نصب‌شده روی گوشی باز می‌شود؛ '
                'پروکسی MTProto مستقیماً روی تلگرام وب یا VPN گذر اعمال نمی‌شود.',
                style: TextStyle(fontSize: 11)),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('gozar-mtproto-server'),
                controller: server,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'آدرس سرور'),
                validator: (value) => !RegExp(r'^[a-zA-Z0-9.-]{1,253}
    textDirection: TextDirection.rtl,
    child: Column(children: [
      // Keep the web client almost full screen, like the user's reference
      // layout. The shell inherits Gozar's Vazirmatn font from ThemeData.
      Container(
        key: const ValueKey('gozar-telegram-header'),
        height: 45,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: const BoxDecoration(
          color: Color(0xfff9fcff),
          border: Border(bottom: BorderSide(color: Color(0xffc3dbed))),
        ),
        child: Row(children: [
          const Icon(Icons.send_rounded, size: 18,
            color: GozarPalette.daylightAccent),
          const SizedBox(width: 7),
          const Expanded(child: Text('تلگرام · نسخهٔ رسمی وب',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: GozarPalette.daylightInk,
              fontSize: 12, fontWeight: FontWeight.w700))),
          const Text('web.telegram.org',
            style: TextStyle(color: GozarPalette.daylightMuted,
              fontSize: 10)),
          PopupMenuButton<String>(
            key: const ValueKey('gozar-telegram-options'),
            padding: EdgeInsets.zero,
            tooltip: 'گزینه‌های تلگرام وب',
            icon: const Icon(Icons.more_vert_rounded,
              color: GozarPalette.daylightAccent, size: 22),
            onSelected: (action) {
              if (action == 'reload') _reload();
              if (action == 'browser') _openInBrowser();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'reload',
                child: Text('بارگذاری مجدد')),
              const PopupMenuItem(value: 'browser',
                child: Text('باز کردن در مرورگر گوشی')),
              if (loadMs != null)
                PopupMenuItem(enabled: false,
                  child: Text('زمان بارگذاری: ' + loadMs.toString() + ' ms')),
            ],
          ),
        ]),
      ),
      Expanded(child: Stack(children: [
        Positioned.fill(child: widget.testWebPage ??
            (defaultTargetPlatform == TargetPlatform.android && !kIsWeb
                ? const AndroidView(
                    key: ValueKey('gozar-telegram-native-web'),
                    viewType: 'ir.channel.telegram_news/gozar_telegram_web')
                : const Center(child: Text(
                    'تلگرام وب در نسخه اندروید گذر نمایش داده می‌شود.')))),
        if (loadFailed)
          Positioned(
            bottom: 12, left: 9, right: 9,
            child: Material(
              borderRadius: BorderRadius.circular(12),
              color: const Color(0xfffceff0),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('صفحهٔ رسمی تلگرام بارگذاری نشد. '
                    'اتصال اینترنت را بررسی کنید.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xff92384b))),
                  TextButton(
                    onPressed: _openInBrowser,
                    child: const Text('باز کردن در مرورگر گوشی')),
                ]),
              ),
            ),
          ),
      ])),
    ]),
  );
}
)
                    .hasMatch((value ?? '').trim())
                    ? 'آدرس معتبر وارد کنید.' : null),
              const SizedBox(height: 9),
              TextFormField(
                key: const ValueKey('gozar-mtproto-port'),
                controller: port,
                textDirection: TextDirection.ltr,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'پورت'),
                validator: (value) {
                  final number = int.tryParse((value ?? '').trim());
                  return number == null || number < 1 || number > 65535
                      ? 'پورت باید بین ۱ و ۶۵۵۳۵ باشد.' : null;
                }),
              const SizedBox(height: 9),
              TextFormField(
                key: const ValueKey('gozar-mtproto-secret'),
                controller: secret,
                textDirection: TextDirection.ltr,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Secret پروکسی'),
                validator: (value) => !RegExp(r'^[a-fA-F0-9]{32,512}
    textDirection: TextDirection.rtl,
    child: Column(children: [
      // Keep the web client almost full screen, like the user's reference
      // layout. The shell inherits Gozar's Vazirmatn font from ThemeData.
      Container(
        key: const ValueKey('gozar-telegram-header'),
        height: 45,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: const BoxDecoration(
          color: Color(0xfff9fcff),
          border: Border(bottom: BorderSide(color: Color(0xffc3dbed))),
        ),
        child: Row(children: [
          const Icon(Icons.send_rounded, size: 18,
            color: GozarPalette.daylightAccent),
          const SizedBox(width: 7),
          const Expanded(child: Text('تلگرام · نسخهٔ رسمی وب',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: GozarPalette.daylightInk,
              fontSize: 12, fontWeight: FontWeight.w700))),
          const Text('web.telegram.org',
            style: TextStyle(color: GozarPalette.daylightMuted,
              fontSize: 10)),
          PopupMenuButton<String>(
            key: const ValueKey('gozar-telegram-options'),
            padding: EdgeInsets.zero,
            tooltip: 'گزینه‌های تلگرام وب',
            icon: const Icon(Icons.more_vert_rounded,
              color: GozarPalette.daylightAccent, size: 22),
            onSelected: (action) {
              if (action == 'reload') _reload();
              if (action == 'browser') _openInBrowser();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'reload',
                child: Text('بارگذاری مجدد')),
              const PopupMenuItem(value: 'browser',
                child: Text('باز کردن در مرورگر گوشی')),
              if (loadMs != null)
                PopupMenuItem(enabled: false,
                  child: Text('زمان بارگذاری: ' + loadMs.toString() + ' ms')),
            ],
          ),
        ]),
      ),
      Expanded(child: Stack(children: [
        Positioned.fill(child: widget.testWebPage ??
            (defaultTargetPlatform == TargetPlatform.android && !kIsWeb
                ? const AndroidView(
                    key: ValueKey('gozar-telegram-native-web'),
                    viewType: 'ir.channel.telegram_news/gozar_telegram_web')
                : const Center(child: Text(
                    'تلگرام وب در نسخه اندروید گذر نمایش داده می‌شود.')))),
        if (loadFailed)
          Positioned(
            bottom: 12, left: 9, right: 9,
            child: Material(
              borderRadius: BorderRadius.circular(12),
              color: const Color(0xfffceff0),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('صفحهٔ رسمی تلگرام بارگذاری نشد. '
                    'اتصال اینترنت را بررسی کنید.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xff92384b))),
                  TextButton(
                    onPressed: _openInBrowser,
                    child: const Text('باز کردن در مرورگر گوشی')),
                ]),
              ),
            ),
          ),
      ])),
    ]),
  );
}
)
                    .hasMatch((value ?? '').trim())
                    ? 'Secret معتبر هگزادسیمال وارد کنید.' : null),
            ]),
          )),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('انصراف')),
            FilledButton(
              key: const ValueKey('gozar-mtproto-confirm'),
              onPressed: () {
                if (form.currentState?.validate() != true) return;
                Navigator.pop(dialog, <String, Object>{
                  'server': server.text.trim(),
                  'port': int.parse(port.text.trim()),
                  'secret': secret.text.trim(),
                });
              },
              child: const Text('باز کردن در برنامه تلگرام')),
          ],
        ),
      );
      if (selected == null || !mounted) return;
      try {
        await controls.invokeMethod<void>(
          'openMtprotoInTelegram', selected);
      } on PlatformException {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('برای افزودن MTProto، برنامه تلگرام را '
              'روی گوشی نصب کنید. این پروکسی روی تلگرام وب فعال نمی‌شود.')));
      }
    } finally {
      server.dispose();
      port.dispose();
      secret.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Column(children: [
      // Keep the web client almost full screen, like the user's reference
      // layout. The shell inherits Gozar's Vazirmatn font from ThemeData.
      Container(
        key: const ValueKey('gozar-telegram-header'),
        height: 45,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: const BoxDecoration(
          color: Color(0xfff9fcff),
          border: Border(bottom: BorderSide(color: Color(0xffc3dbed))),
        ),
        child: Row(children: [
          const Icon(Icons.send_rounded, size: 18,
            color: GozarPalette.daylightAccent),
          const SizedBox(width: 7),
          const Expanded(child: Text('تلگرام · نسخهٔ رسمی وب',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: GozarPalette.daylightInk,
              fontSize: 12, fontWeight: FontWeight.w700))),
          const Text('web.telegram.org',
            style: TextStyle(color: GozarPalette.daylightMuted,
              fontSize: 10)),
          PopupMenuButton<String>(
            key: const ValueKey('gozar-telegram-options'),
            padding: EdgeInsets.zero,
            tooltip: 'گزینه‌های تلگرام وب',
            icon: const Icon(Icons.more_vert_rounded,
              color: GozarPalette.daylightAccent, size: 22),
            onSelected: (action) {
              if (action == 'reload') _reload();
              if (action == 'browser') _openInBrowser();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'reload',
                child: Text('بارگذاری مجدد')),
              const PopupMenuItem(value: 'browser',
                child: Text('باز کردن در مرورگر گوشی')),
              if (loadMs != null)
                PopupMenuItem(enabled: false,
                  child: Text('زمان بارگذاری: ' + loadMs.toString() + ' ms')),
            ],
          ),
        ]),
      ),
      Expanded(child: Stack(children: [
        Positioned.fill(child: widget.testWebPage ??
            (defaultTargetPlatform == TargetPlatform.android && !kIsWeb
                ? const AndroidView(
                    key: ValueKey('gozar-telegram-native-web'),
                    viewType: 'ir.channel.telegram_news/gozar_telegram_web')
                : const Center(child: Text(
                    'تلگرام وب در نسخه اندروید گذر نمایش داده می‌شود.')))),
        if (loadFailed)
          Positioned(
            bottom: 12, left: 9, right: 9,
            child: Material(
              borderRadius: BorderRadius.circular(12),
              color: const Color(0xfffceff0),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('صفحهٔ رسمی تلگرام بارگذاری نشد. '
                    'اتصال اینترنت را بررسی کنید.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xff92384b))),
                  TextButton(
                    onPressed: _openInBrowser,
                    child: const Text('باز کردن در مرورگر گوشی')),
                ]),
              ),
            ),
          ),
      ])),
    ]),
  );
}
