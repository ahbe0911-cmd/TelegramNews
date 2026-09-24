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
  GozarSocialSite('شاد', 'my.shad.ir',
    Icons.school_rounded, Color(0xff2484bd)),
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
  bool baleExpanded = false;

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
    } else if (call.method == 'downloadStarted' ||
        call.method == 'downloadSaved' || call.method == 'downloadError') {
      if (!widget.active) return;
      final message = call.method == 'downloadStarted'
          ? 'در حال ذخیره فایل…'
          : call.method == 'downloadSaved'
              ? (data['gallery'] == true
                  ? 'فایل در گالری ذخیره شد.'
                  : 'فایل در پوشه دانلودها ذخیره شد.')
              : 'ذخیره فایل ناموفق بود. از گزینه «مرورگر گوشی» استفاده کنید.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message), duration: const Duration(seconds: 3),
      ));
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
          height: selected == 1 && !baleExpanded ? 30 : 53,
          padding: EdgeInsets.fromLTRB(7,
              selected == 1 && !baleExpanded ? 2 : 5, 7,
              selected == 1 && !baleExpanded ? 2 : 5),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [Color(0xfffcfeff), Color(0xfff0f7ff)],
            ),
            border: Border(bottom: BorderSide(
              color: Color(0xffd6e6f4))),
          ),
          child: selected == 1 && !baleExpanded
              ? InkWell(
                  key: const ValueKey('gozar-bale-expand'),
                  onTap: () => setState(() { baleExpanded = true; }),
                  borderRadius: BorderRadius.circular(8),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.keyboard_arrow_down_rounded, size: 16,
                        color: Color(0xff486582)),
                      SizedBox(width: 4),
                      Text('نمایش پیام‌رسان‌ها',
                        style: TextStyle(fontSize: 11,
                          color: Color(0xff486582),
                          fontWeight: FontWeight.w600)),
                    ],
                  ),
                )
              : Row(children: [
            Expanded(child: Container(
              key: const ValueKey('gozar-social-segments'),
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: const Color(0xffe9f1fb),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: const Color(0xffd5e5f4)),
              ),
              child: Row(children: [
                for (var index = 0; index < gozarSocialSites.length; index++)
                  Expanded(child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: Semantics(
                      button: true,
                      selected: index == selected,
                      label: 'انتخاب ' + gozarSocialSites[index].name,
                      child: InkWell(
                        key: ValueKey('gozar-social-select-' + index.toString()),
                        onTap: () => _select(index),
                        borderRadius: BorderRadius.circular(12),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          height: 33,
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            gradient: index == selected ? LinearGradient(
                              begin: Alignment.topRight,
                              end: Alignment.bottomLeft,
                              colors: [
                                gozarSocialSites[index].accent,
                                Color.lerp(gozarSocialSites[index].accent,
                                    const Color(0xff173f70), .22)!,
                              ],
                            ) : null,
                            boxShadow: index == selected ? [
                              BoxShadow(
                                color: gozarSocialSites[index].accent
                                    .withOpacity(.2),
                                blurRadius: 5,
                                offset: const Offset(0, 2),
                              ),
                            ] : const [],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(gozarSocialSites[index].icon,
                                size: 13,
                                color: index == selected
                                    ? Colors.white
                                    : const Color(0xff607991)),
                              const SizedBox(width: 3),
                              Flexible(child: Text(gozarSocialSites[index].name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: index == selected ? Colors.white
                                      : GozarPalette.daylightInk))),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )),
              ]),
            )),
            const SizedBox(width: 6),
            Container(
              width: 35,
              height: 37,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xffd5e5f4)),
              ),
              child: PopupMenuButton<String>(
                key: const ValueKey('gozar-social-options'),
                tooltip: 'گزینه‌های صفحه وب',
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.more_horiz_rounded,
                  size: 22, color: GozarPalette.daylightAccent),
                onSelected: (value) {
                  if (value == 'reload') _reload();
                  if (value == 'external') _externalBrowser();
                  if (value == 'baleCompact') {
                    setState(() { baleExpanded = !baleExpanded; });
                  }
                  if (value == 'shadAlternate') {
                    unawaited(_controls.invokeMethod<void>(
                      'alternateShad', {'index': selected},
                    ).catchError((Object _) {}));
                  }
                },
                itemBuilder: (context) => [
                  if (selected == 1)
                    PopupMenuItem(value: 'baleCompact',
                      child: Text(baleExpanded
                          ? 'جمع‌کردن نوار برنامه در بله'
                          : 'نمایش نوار برنامه در بله')),
                  if (selected == 0)
                    const PopupMenuItem(value: 'shadAlternate',
                      child: Text('آدرس جایگزین شاد')),
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
                if (index == 1) baleExpanded = false;
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
