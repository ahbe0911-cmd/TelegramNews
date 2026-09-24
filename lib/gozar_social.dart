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

  @override
  Widget build(BuildContext context) {
    final current = gozarSocialSites[selected];
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(children: [
        Container(
          key: const ValueKey('gozar-social-header'),
          margin: const EdgeInsets.fromLTRB(10, 5, 10, 6),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          decoration: BoxDecoration(
            color: GozarPalette.daylightCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xffc9dff1)),
          ),
          child: Column(children: [
            Row(children: [
              const Icon(Icons.hub_outlined,
                color: GozarPalette.daylightAccent, size: 22),
              const SizedBox(width: 8),
              const Expanded(child: Text('شبکه‌های اجتماعی',
                style: TextStyle(color: GozarPalette.daylightInk,
                  fontSize: 16, fontWeight: FontWeight.w800))),
              IconButton(
                key: const ValueKey('gozar-social-refresh'),
                tooltip: 'بارگذاری مجدد',
                onPressed: _reload,
                icon: const Icon(Icons.refresh_rounded,
                  color: GozarPalette.daylightAccent)),
              IconButton(
                key: const ValueKey('gozar-social-open-browser'),
                tooltip: 'باز کردن در مرورگر گوشی',
                onPressed: _externalBrowser,
                icon: const Icon(Icons.open_in_browser_rounded,
                  color: GozarPalette.daylightAccent)),
            ]),
            const SizedBox(height: 5),
            Row(children: [
              for (var index = 0; index < gozarSocialSites.length; index++)
                Expanded(child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: InkWell(
                    key: ValueKey('gozar-social-select-' + index.toString()),
                    onTap: () => _select(index),
                    borderRadius: BorderRadius.circular(13),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(13),
                        color: index == selected
                            ? gozarSocialSites[index].accent
                            : const Color(0xffeaf3fd)),
                      child: Column(children: [
                        Icon(gozarSocialSites[index].icon, size: 21,
                          color: index == selected ? Colors.white
                              : gozarSocialSites[index].accent),
                        const SizedBox(height: 4),
                        Text(gozarSocialSites[index].name,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: index == selected ? Colors.white
                                : GozarPalette.daylightInk)),
                      ]),
                    ),
                  ),
                )),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.swipe_rounded, size: 15,
                color: GozarPalette.daylightMuted),
              const SizedBox(width: 5),
              const Expanded(child: Text(
                'با کشیدن صفحه به چپ، به پیام‌رسان بعدی بروید.',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: GozarPalette.daylightMuted,
                  fontSize: 10))),
              if (loadMilliseconds.containsKey(selected))
                Text(loadMilliseconds[selected].toString() + ' ms',
                  key: const ValueKey('gozar-social-load-kpi'),
                  style: const TextStyle(
                    fontSize: 10, color: GozarPalette.daylightAccent)),
            ]),
          ]),
        ),
        Expanded(child: Container(
          key: const ValueKey('gozar-social-content'),
          margin: const EdgeInsets.symmetric(horizontal: 7),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xffc9dff1)),
          ),
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
                    bottom: 10, right: 10, left: 10,
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
        const SizedBox(height: 4),
        Text(current.name + ' · ' + current.domain + ' · ' +
          (selected + 1).toString() + ' از ' +
          gozarSocialSites.length.toString(),
          key: const ValueKey('gozar-social-current'),
          style: const TextStyle(
            color: GozarPalette.daylightMuted, fontSize: 10)),
        const SizedBox(height: 3),
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
