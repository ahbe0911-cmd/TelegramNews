import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'gozar_launcher.dart';
import 'gozar_notes_screen.dart';
import 'gozar_notes_store.dart';
import 'gozar_platform_bridge.dart';
import 'gozar_shortcuts.dart';
import 'gozar_subscription.dart';
import 'gozar_visuals.dart';
import 'gozar_vpn.dart';

class GozarVpnProfile {
  final String name;
  final String link;
  final String? subscription;

  const GozarVpnProfile(
    this.name,
    this.link, {
    this.subscription,
  });

  factory GozarVpnProfile.fromJson(Map<String, dynamic> input) =>
      GozarVpnProfile(
        input['name']?.toString() ?? 'سرور',
        input['link']?.toString() ?? '',
        subscription: input['subscription']?.toString(),
      );

  Map<String, String> toJson() => {
    'name': name,
    'link': link,
    if (subscription != null) 'subscription': subscription!,
  };
}

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
  static const _vault = FlutterSecureStorage();
  static const _profilesKey = 'gozar_xray_profiles_v4';
  static const _subscriptionsKey = 'gozar_xray_subscriptions_v2';
  static const _engineVersion = 'Xray-core 26.9.9';
  static const _motivationalQuotes = <String>[
    'امروز لازم نیست بی‌نقص باشی؛ کافی است یک قدم بهتر از دیروز برداری.',
    'کارهای بزرگ از تصمیم‌های کوچک و پیوسته ساخته می‌شوند.',
    'آرام پیش برو، اما از چیزی که برایت مهم است دست نکش.',
    'توان تو بیشتر از چیزی است که یک روز سخت نشان می‌دهد.',
    'هر شروع تازه، فرصتی است برای ساختن نسخه بهتر خودت.',
    'تمرکز روی قدم بعدی، مسیرهای بلند را کوتاه می‌کند.',
    'پیشرفت واقعی آرام است؛ مهم این است که متوقف نشوی.',
    'به جای منتظر ماندن برای زمان مناسب، همین لحظه را بهتر کن.',
    'انرژی‌ات را روی چیزهایی بگذار که می‌توانی تغییرشان بدهی.',
    'موفقیت، جمع همان کارهای کوچکی است که هر روز ادامه می‌دهی.',
    'اگر مسیر سخت شده، شاید دقیقاً در حال رشد کردن هستی.',
    'امروز یک فرصت تازه است؛ آن را با هدف شروع کن.',
  ];

  int currentPage = 0;
  late final GozarLauncher launcherPage;
  late final GozarNotesScreen notesPage;
  late final String homeQuote;

  List<GozarVpnProfile> vpnProfiles = [];
  List<String> vpnSubscriptions = [];
  int selectedVpnProfile = -1;
  String vpnStage = 'off';
  String vpnDetail = 'VPN خاموش است.';
  bool vpnBusy = false;
  bool vpnImporting = false;
  int? vpnLatencyMs;
  Timer? vpnTimer;

  @override
  void initState() {
    super.initState();
    final previousQuote =
        widget.preferences.getInt('gozar_home_quote_index_v1') ?? -1;
    final nextQuote =
        (previousQuote + 1) % _motivationalQuotes.length;
    homeQuote = _motivationalQuotes[nextQuote];
    unawaited(widget.preferences.setInt(
      'gozar_home_quote_index_v1',
      nextQuote,
    ));

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
      } catch (_) {}
    });

    unawaited(_loadVpnData());
    unawaited(_refreshVpnStatus());
    vpnTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_refreshVpnStatus()),
    );
  }

  @override
  void dispose() {
    vpnTimer?.cancel();
    GozarReminderBridge.channel.setMethodCallHandler(null);
    super.dispose();
  }

  void notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _loadVpnData() async {
    try {
      final rawProfiles = await _vault.read(key: _profilesKey);
      final rawSubscriptions = await _vault.read(key: _subscriptionsKey);
      final profiles = <GozarVpnProfile>[];
      if (rawProfiles != null) {
        final parsed = jsonDecode(rawProfiles);
        if (parsed is List) {
          for (final item in parsed) {
            if (item is Map) {
              final profile = GozarVpnProfile.fromJson(
                Map<String, dynamic>.from(item),
              );
              if (profile.link.isNotEmpty) {
                try {
                  buildGozarXrayConfig(profile.link);
                  profiles.add(profile);
                } on FormatException {}
              }
            }
          }
        }
      }

      final subscriptions = <String>[];
      if (rawSubscriptions != null) {
        final parsed = jsonDecode(rawSubscriptions);
        if (parsed is List) {
          for (final value in parsed) {
            final text = value?.toString().trim() ?? '';
            if (text.isEmpty) continue;
            try {
              final normalized =
                  normalizeGozarSubscriptionUrl(text);
              if (!subscriptions.contains(normalized)) {
                subscriptions.add(normalized);
              }
            } on FormatException {}
          }
        }
      }

      if (!mounted) return;
      final savedIndex =
          widget.preferences.getInt('gozar_xray_profile_index') ?? 0;
      setState(() {
        vpnProfiles = profiles;
        vpnSubscriptions = subscriptions;
        selectedVpnProfile = profiles.isEmpty
            ? -1
            : savedIndex.clamp(0, profiles.length - 1);
      });
    } catch (_) {}
  }

  Future<void> _persistVpnData() async {
    await _vault.write(
      key: _profilesKey,
      value: jsonEncode(vpnProfiles.map((item) => item.toJson()).toList()),
    );
    await _vault.write(
      key: _subscriptionsKey,
      value: jsonEncode(vpnSubscriptions),
    );
    await widget.preferences.setInt(
      'gozar_xray_profile_index',
      selectedVpnProfile < 0 ? 0 : selectedVpnProfile,
    );
  }

  Future<void> _refreshVpnStatus() async {
    try {
      final status = await GozarVpnBridge.status();
      if (!mounted) return;
      final nextStage = status['stage']?.toString() ?? 'off';
      final nextDetail =
          status['detail']?.toString() ?? 'VPN خاموش است.';
      if (nextStage != vpnStage || nextDetail != vpnDetail) {
        setState(() {
          vpnStage = nextStage;
          vpnDetail = nextDetail;
          if (nextStage != 'running') {
            vpnLatencyMs = null;
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _toggleVpn() async {
    if (vpnBusy || vpnStage == 'stopping') return;

    if (vpnStage == 'running' ||
        vpnStage == 'starting' ||
        vpnStage == 'consent') {
      setState(() {
        vpnBusy = true;
        vpnLatencyMs = null;
      });
      try {
        await GozarVpnBridge.stop();
        await Future<void>.delayed(
          const Duration(milliseconds: 350),
        );
        await _refreshVpnStatus();
      } catch (_) {
        notice('قطع VPN انجام نشد؛ دوباره امتحان کنید.');
      } finally {
        if (mounted) setState(() { vpnBusy = false; });
      }
      return;
    }

    if (vpnProfiles.isEmpty) {
      notice('ابتدا یک اکانت یا ساب VPN اضافه کنید.');
      return;
    }

    final index = selectedVpnProfile >= 0 &&
            selectedVpnProfile < vpnProfiles.length
        ? selectedVpnProfile
        : 0;

    setState(() {
      vpnBusy = true;
      selectedVpnProfile = index;
      vpnLatencyMs = null;
    });

    try {
      final config =
          buildGozarXrayConfig(vpnProfiles[index].link);
      await widget.preferences.setInt(
        'gozar_xray_profile_index',
        index,
      );
      await GozarVpnBridge.start(config);
      await _refreshVpnStatus();
    } on FormatException catch (error) {
      notice(error.message.toString());
    } catch (_) {
      notice(
        'اتصال برقرار نشد؛ کانفیگ و مجوز VPN اندروید را بررسی کنید.',
      );
      await _refreshVpnStatus();
    } finally {
      if (mounted) setState(() { vpnBusy = false; });
    }
  }

  Future<void> _testVpnConnection() async {
    if (vpnStage != 'running' || vpnBusy) return;
    setState(() {
      vpnBusy = true;
      vpnLatencyMs = null;
    });
    try {
      final latency = await GozarVpnBridge.measureConnection();
      if (!mounted) return;
      setState(() { vpnLatencyMs = latency; });
      if (latency == null) {
        notice(
          'آزمون پاسخ نگرفت؛ این نتیجه به‌تنهایی به معنی قطع بودن VPN نیست.',
        );
      }
    } catch (_) {
      notice('آزمون اتصال انجام نشد.');
    } finally {
      if (mounted) setState(() { vpnBusy = false; });
    }
  }

  Future<void> _addVpnAccount() async {
    final name = TextEditingController();
    final link = TextEditingController();
    try {
      final approved = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('افزودن اکانت VPN'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    maxLength: 50,
                    decoration: const InputDecoration(
                      labelText: 'نام اکانت',
                      hintText: 'مثلاً سرور شخصی',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const ValueKey('gozar-vpn-account-input'),
                    controller: link,
                    minLines: 4,
                    maxLines: 9,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.left,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'لینک یا کانفیگ',
                      hintText:
                          'vless://  vmess://  trojan://  یا Xray JSON',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialog).pop(false),
              child: const Text('انصراف'),
            ),
            FilledButton(
              key: const ValueKey('gozar-vpn-save-account'),
              onPressed: () {
                try {
                  buildGozarXrayConfig(link.text);
                  Navigator.of(dialog).pop(true);
                } on FormatException catch (error) {
                  ScaffoldMessenger.of(dialog).showSnackBar(
                    SnackBar(content: Text(error.message.toString())),
                  );
                }
              },
              child: const Text('ذخیره'),
            ),
          ],
        ),
      );
      if (approved != true || !mounted) return;

      final raw = link.text.trim();
      buildGozarXrayConfig(raw);
      final label = name.text.trim().isEmpty
          ? '${gozarProtocolLabel(raw)} ${vpnProfiles.length + 1}'
          : name.text.trim();

      final updated = List<GozarVpnProfile>.from(vpnProfiles);
      final existing =
          updated.indexWhere((item) => item.link == raw);
      if (existing >= 0) {
        updated[existing] = GozarVpnProfile(label, raw);
      } else {
        updated.add(GozarVpnProfile(label, raw));
      }
      final index =
          existing >= 0 ? existing : updated.length - 1;

      setState(() {
        vpnProfiles = updated;
        selectedVpnProfile = index;
      });
      await _persistVpnData();
      notice('اکانت VPN ذخیره شد.');
    } finally {
      name.dispose();
      link.dispose();
    }
  }

  Future<void> _addVpnSubscription() async {
    final input = TextEditingController();
    try {
      final url = await showDialog<String>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('افزودن ساب VPN'),
          content: TextField(
            key: const ValueKey('gozar-vpn-subscription-input'),
            controller: input,
            minLines: 2,
            maxLines: 4,
            keyboardType: TextInputType.url,
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.left,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'لینک Subscription',
              hintText: 'https://...  یا  sub://...',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialog).pop(),
              child: const Text('انصراف'),
            ),
            FilledButton(
              key: const ValueKey('gozar-vpn-save-subscription'),
              onPressed: () {
                try {
                  final value =
                      normalizeGozarSubscriptionUrl(input.text);
                  Navigator.of(dialog).pop(value);
                } on FormatException catch (error) {
                  ScaffoldMessenger.of(dialog).showSnackBar(
                    SnackBar(
                      content: Text(error.message.toString()),
                    ),
                  );
                }
              },
              child: const Text('دریافت و ذخیره'),
            ),
          ],
        ),
      );
      if (url == null || !mounted) return;
      await _importSubscription(url);
    } finally {
      input.dispose();
    }
  }

  Future<void> _importSubscription(
    String url, {
    bool quiet = false,
  }) async {
    if (vpnImporting) return;
    final sourceUrl = normalizeGozarSubscriptionUrl(url);
    setState(() { vpnImporting = true; });
    try {
      final nodes = await fetchGozarSubscription(sourceUrl);
      final direct = vpnProfiles
          .where((item) => item.subscription != sourceUrl)
          .toList();
      final imported = [
        for (final node in nodes)
          GozarVpnProfile(
            node.name,
            node.link,
            subscription: sourceUrl,
          ),
      ];
      final merged = <GozarVpnProfile>[];
      final seen = <String>{};
      for (final item in [...direct, ...imported]) {
        if (seen.add(item.link)) merged.add(item);
      }
      final subscriptions =
          List<String>.from(vpnSubscriptions);
      if (!subscriptions.contains(sourceUrl)) {
        subscriptions.add(sourceUrl);
      }

      final preferredLink =
          selectedVpnProfile >= 0 &&
                  selectedVpnProfile < vpnProfiles.length
              ? vpnProfiles[selectedVpnProfile].link
              : null;
      var nextIndex = preferredLink == null
          ? -1
          : merged.indexWhere(
              (item) => item.link == preferredLink,
            );
      if (nextIndex < 0 && imported.isNotEmpty) {
        nextIndex = merged.indexWhere(
          (item) => item.link == imported.first.link,
        );
      }
      if (nextIndex < 0 && merged.isNotEmpty) nextIndex = 0;

      if (!mounted) return;
      setState(() {
        vpnProfiles = merged;
        vpnSubscriptions = subscriptions;
        selectedVpnProfile = nextIndex;
      });
      await _persistVpnData();
      if (!quiet) {
        notice(
          '${nodes.length} سرور از ساب اضافه شد.',
        );
      }
    } on FormatException catch (error) {
      if (!quiet) notice(error.message.toString());
    } catch (_) {
      if (!quiet) {
        notice(
          'دریافت ساب انجام نشد؛ اینترنت یا لینک اشتراک را بررسی کنید.',
        );
      }
    } finally {
      if (mounted) setState(() { vpnImporting = false; });
    }
  }

  Future<void> _refreshAllSubscriptions() async {
    if (vpnSubscriptions.isEmpty || vpnImporting) return;
    final sources = List<String>.from(vpnSubscriptions);
    var ok = 0;
    setState(() { vpnImporting = true; });
    try {
      var current = List<GozarVpnProfile>.from(vpnProfiles);
      for (final url in sources) {
        try {
          final nodes = await fetchGozarSubscription(url);
          current = current
              .where((item) => item.subscription != url)
              .toList();
          current.addAll([
            for (final node in nodes)
              GozarVpnProfile(
                node.name,
                node.link,
                subscription: url,
              ),
          ]);
          ok++;
        } catch (_) {}
      }

      final unique = <GozarVpnProfile>[];
      final seen = <String>{};
      for (final item in current) {
        if (seen.add(item.link)) unique.add(item);
      }

      final previousLink =
          selectedVpnProfile >= 0 &&
                  selectedVpnProfile < vpnProfiles.length
              ? vpnProfiles[selectedVpnProfile].link
              : null;
      var nextIndex = previousLink == null
          ? -1
          : unique.indexWhere(
              (item) => item.link == previousLink,
            );
      if (nextIndex < 0 && unique.isNotEmpty) nextIndex = 0;

      if (!mounted) return;
      setState(() {
        vpnProfiles = unique;
        selectedVpnProfile = nextIndex;
      });
      await _persistVpnData();
      notice(
        ok == sources.length
            ? 'همه ساب‌ها به‌روزرسانی شدند.'
            : '$ok از ${sources.length} ساب به‌روزرسانی شد.',
      );
    } finally {
      if (mounted) setState(() { vpnImporting = false; });
    }
  }

  Future<void> _deleteVpnProfile(int index) async {
    if (vpnStage == 'running' ||
        vpnStage == 'starting' ||
        vpnStage == 'consent') {
      notice('برای حذف اکانت، ابتدا VPN را قطع کنید.');
      return;
    }
    if (index < 0 || index >= vpnProfiles.length) return;

    final updated = List<GozarVpnProfile>.from(vpnProfiles)
      ..removeAt(index);
    var next = selectedVpnProfile;
    if (updated.isEmpty) {
      next = -1;
    } else if (selectedVpnProfile == index) {
      next = 0;
    } else if (selectedVpnProfile > index) {
      next--;
    }

    setState(() {
      vpnProfiles = updated;
      selectedVpnProfile = next;
    });
    await _persistVpnData();
  }

  Future<void> _manageVpnProfiles() async {
    if (vpnProfiles.isEmpty) {
      notice('هنوز اکانت VPN ذخیره نشده است.');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, update) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(sheet).height * .68,
            child: Column(children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 2, 16, 10),
                child: Text(
                  'مدیریت اکانت‌های VPN',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Expanded(child: ListView.separated(
                padding:
                    const EdgeInsets.fromLTRB(12, 0, 12, 18),
                itemCount: vpnProfiles.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1),
                itemBuilder: (_, index) {
                  final item = vpnProfiles[index];
                  final selected =
                      selectedVpnProfile == index;
                  return ListTile(
                    key: ValueKey(
                        'gozar-vpn-profile-$index'),
                    leading: Icon(
                      selected
                          ? Icons.check_circle_rounded
                          : Icons.circle_outlined,
                      color: selected
                          ? GozarPalette.cyan
                          : GozarPalette.muted,
                    ),
                    title: Text(item.name),
                    subtitle: Text(
                      item.subscription == null
                          ? gozarProtocolLabel(item.link)
                          : '${gozarProtocolLabel(item.link)} • ساب',
                    ),
                    onTap: () async {
                      setState(() {
                        selectedVpnProfile = index;
                      });
                      await _persistVpnData();
                      if (sheet.mounted) Navigator.of(sheet).pop();
                    },
                    trailing: IconButton(
                      tooltip: 'حذف',
                      onPressed: vpnStage == 'running'
                          ? null
                          : () async {
                              await _deleteVpnProfile(index);
                              if (sheet.mounted) update(() {});
                            },
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                      ),
                    ),
                  );
                },
              )),
            ]),
          ),
        ),
      ),
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

  Widget _pageHeader(
    IconData icon,
    String title,
    String subtitle,
  ) => Container(
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

  Widget _homeTab() => Column(children: [
    Container(
      key: const ValueKey('gozar-home-motivation'),
      margin: const EdgeInsets.fromLTRB(12, 7, 12, 0),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: const Color(0xfff8fcff),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xffb9d8ee)),
      ),
      child: Row(children: [
        const Icon(
          Icons.auto_awesome_rounded,
          color: Color(0xffc58a14),
          size: 20,
        ),
        const SizedBox(width: 9),
        Expanded(child: Text(
          homeQuote,
          key: const ValueKey('gozar-home-motivation-text'),
          style: const TextStyle(
            color: GozarPalette.text,
            fontSize: 12.5,
            height: 1.55,
            fontWeight: FontWeight.w700,
          ),
        )),
      ]),
    ),
    const SizedBox(height: 2),
    Expanded(child: launcherPage),
  ]);

  Widget _notesTab() => Column(children: [
    _pageHeader(
      Icons.event_note_rounded,
      'یادداشت‌ها',
      'تقویم، یادداشت و یادآورهای محلی',
    ),
    Expanded(child: notesPage),
  ]);

  Widget _vpnSettingsCard() {
    final connected = vpnStage == 'running';
    final connecting =
        vpnStage == 'starting' || vpnStage == 'consent';
    final stopping = vpnStage == 'stopping';
    final selected = selectedVpnProfile >= 0 &&
            selectedVpnProfile < vpnProfiles.length
        ? vpnProfiles[selectedVpnProfile]
        : null;
    final statusColor = connected
        ? const Color(0xff159947)
        : (connecting || stopping)
            ? const Color(0xffd78a16)
            : const Color(0xffd63f3f);

    final buttonLabel = connected
        ? 'برای قطع لمس کنید'
        : connecting
            ? 'در حال اتصال…'
            : stopping
                ? 'در حال قطع…'
                : 'برای اتصال لمس کنید';

    return GozarPanel(
      key: const ValueKey('gozar-settings-vpn-card'),
      glow: statusColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(
              Icons.shield_outlined,
              color: statusColor,
              size: 22,
            ),
            const SizedBox(width: 8),
            const Expanded(child: Text(
              'VPN',
              style: TextStyle(
                color: GozarPalette.text,
                fontWeight: FontWeight.w800,
                fontSize: 17,
              ),
            )),
            Container(
              key: const ValueKey('gozar-vpn-status-dot'),
              width: 11,
              height: 11,
              margin: const EdgeInsets.only(left: 8),
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: const Color(0xffe8f4ff),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                _engineVersion,
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  color: GozarPalette.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Center(
            child: GestureDetector(
              key: const ValueKey('gozar-settings-vpn-power'),
              onTap: vpnBusy ? null : _toggleVpn,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: statusColor.withOpacity(.13),
                  border: Border.all(
                    color: statusColor,
                    width: 3,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: statusColor.withOpacity(.18),
                      blurRadius: 22,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.power_settings_new_rounded,
                  size: 48,
                  color: statusColor,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            buttonLabel,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: GozarPalette.text,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            vpnDetail,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: GozarPalette.muted,
              fontSize: 11,
            ),
          ),
          if (selected != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 9,
              ),
              decoration: BoxDecoration(
                color: const Color(0xfff5fbff),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xffbed9ed),
                ),
              ),
              child: Row(children: [
                const Icon(
                  Icons.dns_outlined,
                  size: 18,
                  color: GozarPalette.cyan,
                ),
                const SizedBox(width: 8),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selected.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: GozarPalette.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      gozarProtocolLabel(selected.link),
                      style: const TextStyle(
                        color: GozarPalette.muted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                )),
                TextButton(
                  onPressed: _manageVpnProfiles,
                  child: const Text('تغییر'),
                ),
              ]),
            ),
          ],
          if (vpnLatencyMs != null) ...[
            const SizedBox(height: 8),
            Text(
              'پاسخ موتور: $vpnLatencyMs ms',
              textAlign: TextAlign.center,
              textDirection: TextDirection.rtl,
              style: const TextStyle(
                color: GozarPalette.cyan,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              key: const ValueKey('gozar-vpn-add-account'),
              onPressed: vpnImporting ? null : _addVpnAccount,
              icon: const Icon(Icons.add_rounded),
              label: const Text('اکانت'),
            )),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(
              key: const ValueKey('gozar-vpn-add-subscription'),
              onPressed:
                  vpnImporting ? null : _addVpnSubscription,
              icon: const Icon(Icons.link_rounded),
              label: const Text('ساب'),
            )),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextButton.icon(
              key: const ValueKey('gozar-vpn-manage-profiles'),
              onPressed:
                  vpnProfiles.isEmpty ? null : _manageVpnProfiles,
              icon: const Icon(Icons.storage_outlined),
              label: Text(
                vpnProfiles.isEmpty
                    ? 'بدون اکانت'
                    : 'مدیریت ${vpnProfiles.length} اکانت',
              ),
            )),
            if (vpnSubscriptions.isNotEmpty) ...[
              const SizedBox(width: 6),
              TextButton.icon(
                key: const ValueKey('gozar-vpn-refresh-subscriptions'),
                onPressed: vpnImporting
                    ? null
                    : _refreshAllSubscriptions,
                icon: vpnImporting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.refresh_rounded),
                label: const Text('آپدیت ساب'),
              ),
            ],
          ]),
          if (connected) ...[
            const SizedBox(height: 6),
            OutlinedButton.icon(
              key: const ValueKey('gozar-vpn-test-connection'),
              onPressed:
                  vpnBusy ? null : _testVpnConnection,
              icon: const Icon(Icons.speed_rounded),
              label: const Text('آزمون اتصال'),
            ),
          ],
          const SizedBox(height: 5),
          const Text(
            'اکانت‌ها و لینک‌های ساب در فضای امن گوشی ذخیره می‌شوند. '
            'برنامه‌های بانکی، روبیکا، بله، ایتا و شاد به‌صورت خودکار '
            'از مسیر مستقیم استفاده می‌کنند و سایت‌های .ir نیز مستقیم '
            'مسیریابی می‌شوند.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: GozarPalette.muted,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingsTab() => Column(children: [
    _pageHeader(
      Icons.settings_rounded,
      'تنظیمات',
      'لانچر، VPN و یادآورها',
    ),
    Expanded(child: ListView(
      key: const ValueKey('gozar-settings-page'),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 22),
      children: [
        _vpnSettingsCard(),
        const SizedBox(height: 12),
        GozarPanel(
          glow: GozarPalette.cyan,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(children: [
                Icon(
                  Icons.home_rounded,
                  color: GozarPalette.cyan,
                  size: 21,
                ),
                SizedBox(width: 8),
                Text(
                  'خانه و لانچر',
                  style: TextStyle(
                    color: GozarPalette.text,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
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
                onPressed: () =>
                    setState(() { currentPage = 0; }),
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
                Icon(
                  Icons.notifications_active_outlined,
                  color: GozarPalette.purple,
                  size: 21,
                ),
                SizedBox(width: 8),
                Text(
                  'یادآورها',
                  style: TextStyle(
                    color: GozarPalette.text,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
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
                key: const ValueKey(
                    'gozar-settings-exact-alarm'),
                onPressed: () async {
                  try {
                    await GozarReminderBridge
                        .openExactAlarmSettings();
                  } catch (_) {
                    notice(
                      'صفحه مجوز یادآورهای دقیق در گوشی پیدا نشد.',
                    );
                  }
                },
                icon: const Icon(Icons.alarm_on_rounded),
                label:
                    const Text('تنظیم مجوز یادآور دقیق'),
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
                Icon(
                  Icons.privacy_tip_outlined,
                  color: GozarPalette.cyan,
                  size: 21,
                ),
                SizedBox(width: 8),
                Text(
                  'حریم خصوصی',
                  style: TextStyle(
                    color: GozarPalette.text,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ]),
              SizedBox(height: 8),
              Text(
                'فهرست بخش‌های خانه و یادداشت‌ها محلی است. '
                'اطلاعات اکانت VPN و لینک‌های ساب در Secure Storage '
                'گوشی نگهداری می‌شوند.',
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
          _homeTab(),
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
      labelBehavior:
          NavigationDestinationLabelBehavior.alwaysShow,
      selectedIndex: currentPage,
      onDestinationSelected: (index) {
        setState(() { currentPage = index; });
      },
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(
            Icons.home_rounded,
            color: GozarPalette.cyan,
          ),
          label: 'خانه',
        ),
        NavigationDestination(
          icon: Icon(Icons.event_note_outlined),
          selectedIcon: Icon(
            Icons.event_note_rounded,
            color: GozarPalette.cyan,
          ),
          label: 'یادداشت',
        ),
        NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(
            Icons.settings_rounded,
            color: GozarPalette.cyan,
          ),
          label: 'تنظیمات',
        ),
      ],
    ),
  );
}
