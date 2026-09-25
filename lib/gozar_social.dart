import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'gozar_visuals.dart';

class GozarSocialSite {
  final String name;
  final String domain;
  final Color accent;
  const GozarSocialSite(this.name, this.domain, this.accent);
}

const gozarSocialSites = <GozarSocialSite>[
  GozarSocialSite('روبیکا', 'web.rubika.ir', Color(0xff785cb5)),
  GozarSocialSite('شاد', 'my.shad.ir', Color(0xff2484bd)),
  GozarSocialSite('ایتا', 'web.eitaa.com', Color(0xffd3a336)),
];

/// Page switches never scroll or recreate a visited Android WebView.
class GozarSocialTab extends StatefulWidget {
  final bool active;
  @visibleForTesting
  final Widget Function(int index)? pageBuilder;
  const GozarSocialTab({super.key, required this.active, this.pageBuilder});
  @override
  State<GozarSocialTab> createState() => _GozarSocialTabState();
}

class _GozarSocialTabState extends State<GozarSocialTab> {
  static const _controls =
      MethodChannel('ir.channel.telegram_tdnews/gozar_social_controls');
  static const _events =
      MethodChannel('ir.channel.telegram_tdnews/gozar_social_events');
  final Set<int> visited = {0};
  final Set<int> loadErrors = {};
  final Set<int> crashedPages = {};
  final Map<int, int> viewGenerations = {};
  int selected = 0;

  @override
  void initState() {
    super.initState();
    _events.setMethodCallHandler(_onEvent);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _setActive();
    });
  }

  Future<void> _onEvent(MethodCall call) async {
    if (!mounted || call.arguments is! Map) return;
    final data = call.arguments as Map;
    final nativeIndex = data['index'];
    if (nativeIndex is! int ||
        nativeIndex < 0 || nativeIndex >= gozarSocialSites.length) return;
    final page = nativeIndex;
    if (call.method == 'rendererGone') {
      setState(() {
        crashedPages.add(page);
        loadErrors.add(page);
      });
    } else if (call.method == 'pageError') {
      setState(() => loadErrors.add(page));
    } else if (call.method == 'pageFinished') {
      if (loadErrors.contains(page)) {
        setState(() => loadErrors.remove(page));
      }
    } else if (widget.active && selected == page &&
        (call.method == 'downloadStarted' ||
         call.method == 'downloadSaved' ||
         call.method == 'downloadError')) {
      final message = call.method == 'downloadStarted'
          ? 'در حال ذخیرهٔ فایل…'
          : call.method == 'downloadError'
              ? 'ذخیرهٔ فایل انجام نشد؛ دوباره تلاش کنید.'
              : data['gallery'] == true
                  ? 'عکس یا ویدئو در گالری ذخیره شد.'
                  : 'فایل در پوشهٔ دانلودهای گوشی ذخیره شد.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message),
          duration: const Duration(seconds: 3)));
    }
  }

  void _setActive() {
    final nativeIndex = widget.active ? selected : -1;
    unawaited(_controls.invokeMethod<void>(
      'setActive', {'index': nativeIndex}).catchError((Object _) {}));
  }

  @override
  void didUpdateWidget(covariant GozarSocialTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _setActive();
  }

  @override
  void dispose() {
    unawaited(_controls.invokeMethod<void>(
      'setActive', {'index': -1}).catchError((Object _) {}));
    _events.setMethodCallHandler(null);
    super.dispose();
  }

  void _select(int index) {
    if (index == selected || index < 0 || index >= gozarSocialSites.length) {
      return;
    }
    setState(() {
      selected = index;
      visited.add(index);
    });
    _setActive();
  }

  void _reload() {
    final crashed = crashedPages.contains(selected);
    setState(() {
      loadErrors.remove(selected);
      if (crashed) {
        crashedPages.remove(selected);
        // A WebView whose renderer has died cannot be reloaded: replace only
        // this platform view, preserving the other tabs and their scroll.
        viewGenerations[selected] = (viewGenerations[selected] ?? 0) + 1;
      }
    });
    if (crashed) {
      _setActive();
      return;
    }
    unawaited(_controls.invokeMethod<void>(
      'reload', {'index': selected}).catchError((Object _) {}));
  }

  void _openBrowser() {
    unawaited(_controls.invokeMethod<void>(
      'openExternal', {'index': selected})
        .catchError((Object _) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('مرورگر گوشی در دسترس نیست.')));
      }
    }));
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Column(children: [
      Container(
        key: const ValueKey('gozar-social-header'),
        height: 53,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        decoration: const BoxDecoration(
          color: Color(0xfff9fcff),
          border: Border(bottom: BorderSide(color: Color(0xffd6e6f4))),
        ),
        child: Row(children: [
          Expanded(child: Row(
            key: const ValueKey('gozar-social-segments'),
            children: [
              for (var i = 0; i < gozarSocialSites.length; i++)
                Expanded(child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Semantics(
                    button: true, selected: i == selected,
                    child: InkWell(
                      key: ValueKey('gozar-social-select-' + i.toString()),
                      borderRadius: BorderRadius.circular(11),
                      onTap: () => _select(i),
                      child: Container(
                        height: 37, alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: i == selected
                              ? gozarSocialSites[i].accent
                              : const Color(0xffe9f1fb),
                          borderRadius: BorderRadius.circular(11)),
                        child: Text(gozarSocialSites[i].name,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: i == selected ? Colors.white
                                : GozarPalette.daylightInk)),
                      ),
                    ),
                  ),
                )),
            ],
          )),
          PopupMenuButton<String>(
            key: const ValueKey('gozar-social-options'),
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.more_vert_rounded,
              color: GozarPalette.daylightAccent, size: 22),
            onSelected: (action) {
              if (action == 'reload') _reload();
              if (action == 'browser') _openBrowser();
              if (action == 'alternateShad' && selected == 1) {
                unawaited(_controls.invokeMethod<void>(
                  'alternateShad', {'index': 1}).catchError((Object _) {}));
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'reload',
                child: Text('بارگذاری مجدد')),
              const PopupMenuItem(value: 'browser',
                child: Text('باز کردن در مرورگر گوشی')),
              if (selected == 1)
                const PopupMenuItem(value: 'alternateShad',
                  child: Text('آدرس جایگزین شاد')),
            ],
          ),
        ]),
      ),
      Expanded(child: SizedBox.expand(
        key: const ValueKey('gozar-social-content'),
        child: IndexedStack(
          key: const ValueKey('gozar-social-pages'),
          index: selected,
          children: [
            for (var i = 0; i < gozarSocialSites.length; i++)
              visited.contains(i)
                  ? Stack(children: [
                      Positioned.fill(child: widget.pageBuilder?.call(i) ??
                        _SocialNativeWebPage(
                          key: ValueKey('gozar-social-web-' + i.toString() +
                            '-' + (viewGenerations[i] ?? 0).toString()),
                          index: i)),
                      if (loadErrors.contains(i) && selected == i)
                        Positioned(bottom: 10, left: 10, right: 10,
                          child: Material(
                            color: const Color(0xfffceff0),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('بارگذاری ' + gozarSocialSites[i].name +
                                    ' انجام نشد.', textAlign: TextAlign.center),
                                  TextButton(onPressed: _reload,
                                    child: const Text('تلاش مجدد')),
                                ]),
                            ),
                          ),
                        ),
                    ])
                  : const SizedBox.shrink(),
          ],
        ),
      )),
    ]),
  );
}

class _SocialNativeWebPage extends StatelessWidget {
  final int index;
  const _SocialNativeWebPage({super.key, required this.index});
  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.android || kIsWeb) {
      return const Center(child: Text('وب‌اپ در نسخهٔ اندروید نمایش داده می‌شود.'));
    }
    return AndroidView(
      key: ValueKey('gozar-social-native-' + index.toString()),
      viewType: 'ir.channel.telegram_news/gozar_social_web',
      creationParams: {'index': index},
      creationParamsCodec: const StandardMessageCodec(),
    );
  }
}
