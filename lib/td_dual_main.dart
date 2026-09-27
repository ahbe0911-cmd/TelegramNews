import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'td_news_engine.dart';
import 'td_news_main.dart' show TdHome;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  runApp(DualNewsApp(preferences: preferences));
}

class DualNewsApp extends StatefulWidget {
  final SharedPreferences preferences;
  const DualNewsApp({super.key, required this.preferences});

  @override
  State<DualNewsApp> createState() => _DualNewsAppState();
}

class _DualNewsAppState extends State<DualNewsApp> {
  late final TdNewsController news;
  late final TdNewsController cafenet;
  late final PageController pages;

  final Set<int> restoreAttempted = <int>{};
  late int activePage;
  late bool newsDark;
  late bool cafenetDark;

  @override
  void initState() {
    super.initState();
    activePage = (widget.preferences.getInt('dual_active_page') ?? 0).clamp(0, 1);
    newsDark = widget.preferences.getBool('dual_news_dark') ?? false;
    cafenetDark = widget.preferences.getBool('dual_cafenet_dark') ?? false;
    news = TdNewsController(
      widget.preferences,
      storagePrefix: 'news',
      downloadFolder: 'NabzKhabar',
    );
    cafenet = TdNewsController(
      widget.preferences,
      storagePrefix: 'cafenet',
      downloadFolder: 'Cafenet',
    );
    pages = PageController(initialPage: activePage);
    unawaited(_restore(activePage));
  }

  TdNewsController _controller(int index) => index == 0 ? news : cafenet;
  String _scope(int index) => index == 0 ? 'news' : 'cafenet';

  Future<void> _restore(int index) async {
    if (!restoreAttempted.add(index)) return;
    final controller = _controller(index);
    const vault = FlutterSecureStorage();
    try {
      final scope = _scope(index);
      final id = int.tryParse(
        await vault.read(key: scope + '_td_api_id') ?? '',
      );
      final hash = await vault.read(key: scope + '_td_api_hash');
      if (id == null || id <= 0 || hash == null || hash.isEmpty) return;
      final root = await getApplicationSupportDirectory();
      final directory = Directory(root.path + '/' + scope)
        ..createSync(recursive: true);
      await controller.start(id, hash, directory.path);
    } catch (_) {
      // The page stays on the normal setup screen and can be configured there.
    }
  }

  void _setPage(int index) {
    if (activePage == index) return;
    setState(() => activePage = index);
    unawaited(widget.preferences.setInt('dual_active_page', index));
    unawaited(_restore(index));
  }

  void _toggleNewsTheme() {
    setState(() => newsDark = !newsDark);
    unawaited(widget.preferences.setBool('dual_news_dark', newsDark));
  }

  void _toggleCafenetTheme() {
    setState(() => cafenetDark = !cafenetDark);
    unawaited(widget.preferences.setBool('dual_cafenet_dark', cafenetDark));
  }

  @override
  void dispose() {
    pages.dispose();
    news.dispose();
    cafenet.dispose();
    super.dispose();
  }

  ThemeData _lightTheme(Color seed) => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          primary: seed,
          surface: const Color(0xffffffff),
        ),
        fontFamily: 'CustomFont',
        scaffoldBackgroundColor: const Color(0xfff5f7fb),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xfff5f7fb),
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
      );

  ThemeData _darkTheme() => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff91baff),
          brightness: Brightness.dark,
        ),
        fontFamily: 'CustomFont',
        appBarTheme: const AppBarTheme(elevation: 0, scrolledUnderElevation: 0),
      );

  Widget _switcher() {
    final dark = activePage == 0 ? newsDark : cafenetDark;
    final accent = activePage == 0
        ? const Color(0xff0866dc)
        : const Color(0xff7043c6);
    final background = dark ? const Color(0xff111318) : const Color(0xfff5f7fb);
    final surface = dark ? const Color(0xff1c1f26) : Colors.white;
    final text = dark ? Colors.white : const Color(0xff1c2430);

    Widget item(int index, String title, IconData icon) {
      final selected = activePage == index;
      return Expanded(
        child: InkWell(
          key: ValueKey('dual-tab-' + index.toString()),
          borderRadius: BorderRadius.circular(15),
          onTap: () {
            pages.animateToPage(
              index,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
            );
          },
          child: AnimatedContainer(
            key: selected ? ValueKey('dual-active-' + index.toString()) : null,
            duration: const Duration(milliseconds: 170),
            margin: const EdgeInsets.all(4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? accent.withValues(alpha: dark ? .26 : .12) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: selected ? accent : text.withValues(alpha: .58)),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? accent : text.withValues(alpha: .7),
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ColoredBox(
      color: background,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 5, 14, 4),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? .18 : .05),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                item(0, 'نبض خبر', Icons.newspaper_rounded),
                item(1, 'کافی‌نت', Icons.computer_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final newsTheme = newsDark
        ? _darkTheme()
        : _lightTheme(const Color(0xff0866dc));
    final cafenetTheme = cafenetDark
        ? _darkTheme()
        : _lightTheme(const Color(0xff7043c6));

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'نبض خبر و کافی‌نت',
      locale: const Locale('fa'),
      supportedLocales: const [Locale('fa')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(useMaterial3: true, fontFamily: 'CustomFont'),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                _switcher(),
                Expanded(
                  child: MediaQuery.removePadding(
                    context: context,
                    removeTop: true,
                    child: PageView(
                      key: const ValueKey('dual-page-view'),
                      controller: pages,
                      onPageChanged: _setPage,
                      physics: const PageScrollPhysics(),
                      children: [
                        _DualPane(
                          key: const ValueKey('dual-news-page'),
                          theme: newsTheme,
                          news: news,
                          dark: newsDark,
                          onToggleTheme: _toggleNewsTheme,
                        ),
                        _DualPane(
                          key: const ValueKey('dual-cafenet-page'),
                          theme: cafenetTheme,
                          news: cafenet,
                          dark: cafenetDark,
                          onToggleTheme: _toggleCafenetTheme,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DualPane extends StatefulWidget {
  final ThemeData theme;
  final TdNewsController news;
  final bool dark;
  final VoidCallback onToggleTheme;

  const _DualPane({
    super.key,
    required this.theme,
    required this.news,
    required this.dark,
    required this.onToggleTheme,
  });

  @override
  State<_DualPane> createState() => _DualPaneState();
}

class _DualPaneState extends State<_DualPane>
    with AutomaticKeepAliveClientMixin<_DualPane> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RepaintBoundary(
      child: Theme(
        data: widget.theme,
        child: TdHome(
          news: widget.news,
          onToggleTheme: widget.onToggleTheme,
          dark: widget.dark,
        ),
      ),
    );
  }
}
