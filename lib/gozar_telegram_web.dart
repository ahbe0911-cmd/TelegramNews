import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'gozar_visuals.dart';

/// Checks official MTProto proxy links from channels before the Android handoff.
/// The Android host validates these fields again before opening Telegram.
bool gozarValidMtprotoLink(String input) {
  final uri = Uri.tryParse(input.trim());
  if (uri == null) return false;
  final tg = uri.scheme.toLowerCase() == 'tg' &&
      uri.host.toLowerCase() == 'proxy';
  final web = uri.scheme.toLowerCase() == 'https' &&
      const {'t.me', 'telegram.me'}.contains(uri.host.toLowerCase()) &&
      uri.path.replaceFirst(RegExp(r'/+$'), '') == '/proxy';
  if (!tg && !web) return false;
  final server = uri.queryParameters['server']?.trim() ?? '';
  final port = int.tryParse(uri.queryParameters['port'] ?? '');
  final secret = uri.queryParameters['secret']?.trim() ?? '';
  return RegExp(r'^[A-Za-z0-9.-]{1,253}$').hasMatch(server) &&
      port != null && port >= 1 && port <= 65535 &&
      RegExp(r'^[a-fA-F0-9]{32,512}$').hasMatch(secret);
}

/// Telegram Web K runs in a retained Android WebView. An optional MTProto
/// handoff opens an installed Telegram client: it cannot proxy the website.
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
    } else if (event.method == 'proxyLinkError' && widget.active) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('لینک MTProto معتبر نیست یا تلگرام روی گوشی نصب نیست.')));
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

  Future<void> _configureMtprotoLink() async {
    var link = '';
    final form = GlobalKey<FormState>();
    final selected = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('افزودن پروکسی از لینک کانال'),
        content: SingleChildScrollView(child: Form(
          key: form,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('لینک tg://proxy یا https://t.me/proxy را وارد کنید. '
              'پروکسی در تلگرام نصب‌شده روی گوشی فعال می‌شود، نه وب‌ویو گذر.',
              style: TextStyle(fontSize: 12)),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('gozar-mtproto-link'),
              onChanged: (value) => link = value,
              textDirection: TextDirection.ltr,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'لینک پروکسی کانال'),
              validator: (value) => gozarValidMtprotoLink(value ?? '')
                  ? null : 'لینک MTProto معتبر وارد کنید.'),
          ]),
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog),
            child: const Text('انصراف')),
          FilledButton(
            key: const ValueKey('gozar-mtproto-link-confirm'),
            onPressed: () {
              if (form.currentState?.validate() != true) return;
              Navigator.pop(dialog, link.trim());
            },
            child: const Text('افزودن در برنامه تلگرام')),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    try {
      await controls.invokeMethod<void>('openMtprotoLink', {'url': selected});
    } on PlatformException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('برای افزودن پروکسی، تلگرام را روی گوشی نصب کنید. '
          'این پروکسی روی تلگرام وب فعال نمی‌شود.')));
    }
  }

  Future<void> _showConnectionOptions() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('اتصال تلگرام وب'),
        content: const Text(
          'حالت عادی: وب‌ویو از اینترنت مجاز برای خود برنامه استفاده می‌کند. '
          'اگر VPN دیگری روی گوشی فعال باشد و گذر را پوشش دهد، '
          'اندروید مسیر اتصال را خودکار انتخاب می‌کند.\n\n'
          'VPN داخلی گذر، به دلیل جلوگیری از حلقهٔ اتصال، '
          'خود برنامه را از تونل خارج می‌کند. برای استفاده از VPN گذر '
          'در تلگرام وب، سایت را در مرورگر گوشی باز کنید '
          '(مرورگر باید در برنامه‌های تحت پوشش VPN باشد).\n\n'
          'MTProto فقط برای برنامه تلگرام نصب‌شده روی گوشی است.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog),
            child: const Text('بستن')),
          TextButton(onPressed: () => Navigator.pop(dialog, 'settings'),
            child: const Text('تنظیمات VPN گوشی')),
          FilledButton(onPressed: () => Navigator.pop(dialog, 'browser'),
            child: const Text('باز کردن در مرورگر با VPN')),
        ],
      ),
    );
    if (!mounted) return;
    if (selected == 'browser') _openInBrowser();
    if (selected == 'settings') {
      try {
        await const MethodChannel('ir.channel.telegram_tdnews/system_vpn')
            .invokeMethod<void>('openVpnSettings');
      } on PlatformException {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('باز کردن تنظیمات VPN گوشی ممکن نشد.')));
      }
    }
  }

  Future<void> _configureMtproto() async {
    var server = '';
    var port = '443';
    var secret = '';
    final form = GlobalKey<FormState>();
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
                initialValue: server,
                onChanged: (value) { server = value; },
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'آدرس سرور'),
                validator: (value) => !RegExp(r'^[a-zA-Z0-9.-]{1,253}$')
                    .hasMatch((value ?? '').trim())
                    ? 'آدرس معتبر وارد کنید.' : null),
              const SizedBox(height: 9),
              TextFormField(
                key: const ValueKey('gozar-mtproto-port'),
                initialValue: port,
                onChanged: (value) { port = value; },
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
                initialValue: secret,
                onChanged: (value) { secret = value; },
                textDirection: TextDirection.ltr,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Secret پروکسی'),
                validator: (value) => !RegExp(r'^[a-fA-F0-9]{32,512}$')
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
                  'server': server.trim(),
                  'port': int.parse(port.trim()),
                  'secret': secret.trim(),
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
              if (action == 'font') _toggleAppFont();
              if (action == 'mtproto') unawaited(_configureMtproto());
              if (action == 'mtproto_link') unawaited(_configureMtprotoLink());
              if (action == 'connection') unawaited(_showConnectionOptions());
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'reload',
                child: Text('بارگذاری مجدد')),
              const PopupMenuItem(value: 'browser',
                child: Text('باز کردن در مرورگر گوشی')),
              PopupMenuItem(value: 'font',
                child: Text(useAppFont
                    ? 'استفاده از فونت اصلی سایت'
                    : 'استفاده از فونت فارسی گذر')),
              const PopupMenuItem(value: 'connection',
                child: Text('اتصال خودکار و VPN گوشی')),
              const PopupMenuItem(value: 'mtproto_link',
                child: Text('افزودن MTProto از لینک کانال')),
              const PopupMenuItem(value: 'mtproto',
                child: Text('افزودن MTProto در برنامه تلگرام')),
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
