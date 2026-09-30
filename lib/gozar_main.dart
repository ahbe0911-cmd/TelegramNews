import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'gozar_launcher.dart';
import 'gozar_notes_screen.dart';
import 'gozar_notes_store.dart';
import 'gozar_platform_bridge.dart';
import 'gozar_shortcuts.dart';
import 'gozar_visuals.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  runApp(GozarApp(preferences: preferences));
}

class GozarApp extends StatelessWidget {
  final SharedPreferences preferences;
  const GozarApp({super.key, required this.preferences});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'گذر',
    debugShowCheckedModeBanner: false,
    locale: const Locale('fa'),
    supportedLocales: const [Locale('fa')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: GozarPalette.cyan,
        brightness: Brightness.light,
        surface: GozarPalette.navy,
      ),
      scaffoldBackgroundColor: GozarPalette.base,
      fontFamily: 'Vazirmatn',
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: Color(0xffe8f4ff),
        contentTextStyle: TextStyle(color: GozarPalette.text),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xffa4c5e0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: GozarPalette.cyan),
        ),
      ),
    ),
    home: GozarHome(preferences: preferences),
  );
}

class GozarHome extends StatefulWidget {
  final SharedPreferences preferences;
  const GozarHome({super.key, required this.preferences});

  @override
  State<GozarHome> createState() => _GozarHomeState();
}

class _GozarHomeState extends State<GozarHome> {
  int currentPage = 0;
  late final GozarLauncher launcherPage;
  late final GozarNotesScreen notesPage;

  @override
  void initState() {
    super.initState();
    launcherPage = GozarLauncher(
      preferences: widget.preferences,
      onOpenApp: _openShortcut,
    );
    notesPage = GozarNotesScreen(
      preferences: widget.preferences,
      onChanged: () {},
    );

    GozarReminderBridge.channel.setMethodCallHandler((call) async {
      if (call.method == 'openNotes' && mounted) {
        setState(() { currentPage = 1; });
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final opened = await GozarReminderBridge.channel
            .invokeMethod<bool>('takeOpenedReminder') ?? false;
        if (opened && mounted) {
          setState(() { currentPage = 1; });
        }
      } catch (_) {
        // Widget tests and unsupported hosts.
      }
    });
  }

  @override
  void dispose() {
    GozarReminderBridge.channel.setMethodCallHandler(null);
    super.dispose();
  }

  void notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _openShortcut(GozarShortcut shortcut) async {
    try {
      if (shortcut.kind == 'web') {
        final uri = GozarShortcut.validWebUrl(shortcut.target);
        if (uri == null) {
          notice('این نشانی معتبر نیست.');
          return;
        }
        await GozarPlatformBridge.openShortcutWeb(
          uri.toString(),
          shortcut.title,
        );
      } else {
        await GozarPlatformBridge.openShortcutApp(
          shortcut.target,
          component: shortcut.component,
        );
      }
    } catch (_) {
      notice(shortcut.kind == 'web'
          ? 'بازکردن این نشانی انجام نشد.'
          : 'بازکردن این برنامه انجام نشد.');
    }
  }

  Widget _pageHeader(IconData icon, String title, String subtitle) =>
      Container(
        margin: const EdgeInsets.fromLTRB(12, 7, 12, 7),
        padding: const EdgeInsets.fromLTRB(13, 10, 13, 10),
        decoration: BoxDecoration(
          color: const Color(0xfff8fcff),
          borderRadius: BorderRadius.circular(21),
          border: Border.all(color: const Color(0xffbfd9ee)),
        ),
        child: Row(children: [
          Icon(icon, color: GozarPalette.cyan, size: 24),
          const SizedBox(width: 9),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(
                color: GozarPalette.text,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              )),
              Text(subtitle, style: const TextStyle(
                color: GozarPalette.muted,
                fontSize: 11,
              )),
            ],
          )),
        ]),
      );

  Widget _notesTab() => Column(children: [
    _pageHeader(
      Icons.event_note_rounded,
      'یادداشت‌ها',
      'تقویم، یادداشت و یادآورهای محلی',
    ),
    Expanded(child: notesPage),
  ]);

  Widget _settingsTab() => Column(children: [
    _pageHeader(
      Icons.settings_rounded,
      'تنظیمات',
      'تنظیمات عمومی خانه و یادآورها',
    ),
    Expanded(child: ListView(
      key: const ValueKey('gozar-settings-page'),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 22),
      children: [
        GozarPanel(
          glow: GozarPalette.cyan,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(children: [
                Icon(Icons.home_rounded,
                  color: GozarPalette.cyan, size: 21),
                SizedBox(width: 8),
                Text('خانه و لانچر', style: TextStyle(
                  color: GozarPalette.text,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                )),
              ]),
              const SizedBox(height: 8),
              const Text(
                'ساخت بخش‌ها، انتخاب برنامه‌ها، اندازه آیکن‌ها و چینش '
                'مستقیماً از صفحه خانه انجام می‌شود.',
                style: TextStyle(
                  color: GozarPalette.muted,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                key: const ValueKey('gozar-settings-open-home'),
                onPressed: () => setState(() { currentPage = 0; }),
                icon: const Icon(Icons.home_outlined),
                label: const Text('رفتن به خانه'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        GozarPanel(
          glow: GozarPalette.purple,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(children: [
                Icon(Icons.notifications_active_outlined,
                  color: GozarPalette.purple, size: 21),
                SizedBox(width: 8),
                Text('یادآورها', style: TextStyle(
                  color: GozarPalette.text,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                )),
              ]),
              const SizedBox(height: 8),
              const Text(
                'یادداشت‌ها روی همین گوشی ذخیره می‌شوند. برای اجرای '
                'یادآور دقیق، مجوز مربوط به هشدارها باید در اندروید فعال باشد.',
                style: TextStyle(
                  color: GozarPalette.muted,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                key: const ValueKey('gozar-settings-exact-alarm'),
                onPressed: () async {
                  try {
                    await GozarReminderBridge.openExactAlarmSettings();
                  } catch (_) {
                    notice('صفحه مجوز یادآورهای دقیق در گوشی پیدا نشد.');
                  }
                },
                icon: const Icon(Icons.alarm_on_rounded),
                label: const Text('تنظیم مجوز یادآور دقیق'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const GozarPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Icon(Icons.privacy_tip_outlined,
                  color: GozarPalette.cyan, size: 21),
                SizedBox(width: 8),
                Text('حریم خصوصی', style: TextStyle(
                  color: GozarPalette.text,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                )),
              ]),
              SizedBox(height: 8),
              Text(
                'فهرست بخش‌های خانه و یادداشت‌ها به‌صورت محلی روی گوشی '
                'نگهداری می‌شوند. برنامه برای نمایش آیکن‌ها فقط برنامه‌های '
                'قابل اجرا روی همین دستگاه را می‌خواند.',
                style: TextStyle(
                  color: GozarPalette.muted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    )),
  ]);

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xffeaf6ff),
    body: SafeArea(
      child: IndexedStack(
        index: currentPage,
        children: [
          launcherPage,
          _notesTab(),
          _settingsTab(),
        ],
      ),
    ),
    bottomNavigationBar: NavigationBar(
      key: const ValueKey('gozar-bottom-navigation'),
      height: 68,
      backgroundColor: const Color(0xfffcfeff),
      indicatorColor: const Color(0xffd3edff),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      selectedIndex: currentPage,
      onDestinationSelected: (index) {
        setState(() { currentPage = index; });
      },
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home_rounded, color: GozarPalette.cyan),
          label: 'خانه',
        ),
        NavigationDestination(
          icon: Icon(Icons.event_note_outlined),
          selectedIcon:
              Icon(Icons.event_note_rounded, color: GozarPalette.cyan),
          label: 'یادداشت',
        ),
        NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon:
              Icon(Icons.settings_rounded, color: GozarPalette.cyan),
          label: 'تنظیمات',
        ),
      ],
    ),
  );
}
