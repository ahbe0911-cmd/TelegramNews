import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'gozar_visuals.dart';

/// Independent official HTTPS web destinations, without a Telegram native SDK.
class GozarSocialSite {
  final String name;
  final String domain;
  final IconData icon;
  final Color accent;
  const GozarSocialSite(this.name, this.domain, this.icon, this.accent);
}

const gozarSocialSites = <GozarSocialSite>[
  GozarSocialSite('تلگرام', 'web.telegram.org',
    Icons.send_rounded, Color(0xff258ec7)),
  GozarSocialSite('بله', 'web.bale.ai',
    Icons.chat_bubble_rounded, Color(0xff24a486)),
  GozarSocialSite('روبیکا', 'web.rubika.ir',
    Icons.groups_rounded, Color(0xff785cb5)),
  GozarSocialSite('ایتا', 'web.eitaa.com',
    Icons.forum_rounded, Color(0xffd3a336)),
];

/// PageView and the native browser each retain visited pages. Only the
/// selected WebView is resumed, so hidden apps do not consume active CPU.
class GozarSocialTab extends StatefulWidget {
  final bool active;
  @visibleForTesting
  final Widget Function(int index)? pageBuilder;
  const GozarSocialTab({
    super.key, required this.active, this.pageBuilder,
  });

  @override
  State<GozarSocialTab> createState() => _GozarSocialTabState();
}

class _GozarSocialTabState extends State<GozarSocialTab> {
  static const _controls =
      MethodChannel('ir.channel.telegram_tdnews/gozar_social_controls');
  static const _events =
      MethodChannel('ir.channel.telegram_tdnews/gozar_social_events');
  final PageController controller = PageController();
  final Set<int> visited = {0};
  final Map<int, int> loadMilliseconds = {};
  final Set<int> loadErrors = {};
  int selected = 0;

  @override
  void initState() {
    super.initState();
    _events.setMethodCallHandler(_handleEvent);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _setActive();
    });
  }

  Future<void> _handleEvent(MethodCall call) async {
    if (!mounted || call.arguments is! Map) return;
    final data = call.arguments as Map;
    final index = data['index'];
    if (index is! int || index < 0 || index >= gozarSocialSites.length) {
      return;
    }
    if (call.method == 'pageFinished') {
      final elapsed = data['loadMs'];
      setState(() {
        loadErrors.remove(index);
        if (elapsed is num && elapsed >= 0) {
          loadMilliseconds[index] = elapsed.toInt();
        }
      });
    } else if (call.method == 'pageError') {
      setState(() { loadErrors.add(index); });
    }
  }

  void _setActive({int? overrideIndex}) {
    unawaited(_controls.invokeMethod<void>('setActive', {
      'index': overrideIndex ?? (widget.active ? selected : -1),
    }).catchError((Object _) {
      // No Android platform view in widget tests and desktop previews.
    }));
  }

  @override
  void didUpdateWidget(covariant GozarSocialTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _setActive();
  }

  @override
  void dispose() {
    _setActive(overrideIndex: -1);
    _events.setMethodCallHandler(null);
    controller.dispose();
    super.dispose();
  }

  void _select(int index) {
    if (index < 0 || index >= gozarSocialSites.length ||
        index == selected || !controller.hasClients) return;
    controller.animateToPage(index,
      duration: const Duration(milliseconds: 190),
      curve: Curves.easeOutCubic);
  }

  void _reload() {
    setState(() {
      loadErrors.remove(selected);
      loadMilliseconds.remove(selected);
    });
    unawaited(_controls.invokeMethod<void>(
      'reload', {'index': selected},
    ).catchError((Object _) {}));
  }

  void _externalBrowser() {
    unawaited(_controls.invokeMethod<void>(
      'openExternal', {'index': selected},
    ).catchError((Object _) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('مرورگر گوشی پیدا نشد.')));
      }
    }));
  }

  /// The site selector takes a single compact row at the very TOP of this
  /// tab. No app-global toolbar, explanatory banner, footer or inset card is
  /// placed around the webpage: Android WebView gets all the remaining space.
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(children: [
        Container(
          key: const ValueKey('gozar-social-header'),
          height: 53,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: const BoxDecoration(
            color: Color(0xfff9fcff),
            border: Border(bottom: BorderSide(
              color: Color(0xffc7dff1))),
          ),
          child: Row(children: [
            for (var index = 0; index < gozarSocialSites.length; index++)
              Expanded(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: InkWell(
                  key: ValueKey('gozar-social-select-' + index.toString()),
                  onTap: () => _select(index),
                  borderRadius: BorderRadius.circular(9),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(9),
                      color: index == selected
                          ? gozarSocialSites[index].accent
                          : const Color(0xffeaf3fd)),
                    child: Text(gozarSocialSites[index].name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: index == selected ? Colors.white
                            : GozarPalette.daylightInk)),
                  ),
                ),
              )),
            PopupMenuButton<String>(
              key: const ValueKey('gozar-social-options'),
              tooltip: 'گزینه‌های صفحه وب',
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.more_vert_rounded,
                size: 20, color: GozarPalette.daylightAccent),
              onSelected: (value) {
                if (value == 'reload') _reload();
                if (value == 'external') _externalBrowser();
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'reload',
                  child: Text('بارگذاری مجدد')),
                const PopupMenuItem(value: 'external',
                  child: Text('باز کردن در مرورگر گوشی')),
                if (loadMilliseconds.containsKey(selected))
                  PopupMenuItem(
                    enabled: false,
                    child: Text('زمان بارگذاری: ' +
                      loadMilliseconds[selected].toString() + ' ms',
                      key: const ValueKey('gozar-social-load-kpi')),
                  ),
              ],
            ),
          ]),
        ),
        Expanded(child: SizedBox.expand(
          key: const ValueKey('gozar-social-content'),
          child: PageView.builder(
            key: const ValueKey('gozar-social-pages'),
            controller: controller,
            itemCount: gozarSocialSites.length,
            onPageChanged: (index) {
              setState(() {
                selected = index;
                visited.add(index);
              });
              _setActive(overrideIndex: widget.active ? index : -1);
            },
            itemBuilder: (context, index) {
              if (!visited.contains(index)) {
                return Center(
                  key: ValueKey(
                    'gozar-social-not-loaded-' + index.toString()),
                  child: Text('برای باز کردن ' +
                    gozarSocialSites[index].name + ' به این صفحه بروید.',
                    style: const TextStyle(
                      color: GozarPalette.daylightMuted)),
                );
              }
              return Stack(children: [
                Positioned.fill(child: widget.pageBuilder?.call(index) ??
                  _SocialNativeWebPage(
                    key: ValueKey('gozar-social-web-' + index.toString()),
                    index: index)),
                if (loadErrors.contains(index))
                  Positioned(
                    bottom: 12, right: 10, left: 10,
                    child: Material(
                      borderRadius: BorderRadius.circular(11),
                      color: const Color(0xfff6eff0),
                      child: Padding(
                        padding: const EdgeInsets.all(11),
                        child: Text('بارگذاری ' +
                          gozarSocialSites[index].name +
                          ' انجام نشد. اینترنت را بررسی و صفحه را تازه‌سازی کنید.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xff91364a), fontSize: 11)),
                      ),
                    ),
                  ),
              ]);
            },
          ),
        )),
      ]),
    );
  }
}

/// Keep each visited WebView and its cookie-backed login/session alive.
class _SocialNativeWebPage extends StatefulWidget {
  final int index;
  const _SocialNativeWebPage({super.key, required this.index});
  @override
  State<_SocialNativeWebPage> createState() => _SocialNativeWebPageState();
}

class _SocialNativeWebPageState extends State<_SocialNativeWebPage>
    with AutomaticKeepAliveClientMixin<_SocialNativeWebPage> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return AndroidView(
      key: ValueKey('gozar-social-native-' + widget.index.toString()),
      viewType: 'ir.channel.telegram_news/gozar_social_web',
      creationParams: {'index': widget.index},
      creationParamsCodec: const StandardMessageCodec(),
      // The Flutter pager owns horizontal swipes; the native WebView keeps
      // taps and vertical scroll gestures for messenger interactions.
      gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
        Factory<OneSequenceGestureRecognizer>(
            () => VerticalDragGestureRecognizer()),
        Factory<OneSequenceGestureRecognizer>(
            () => TapGestureRecognizer()),
      },
    );
  }
}
