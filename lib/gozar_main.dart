import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'td_system_vpn.dart';

/// «گذر» is a standalone VPN: no Telegram account, feed, or TDLib in this APK.
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
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff087E70)),
      scaffoldBackgroundColor: const Color(0xfff4f9f7),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
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

class _GozarHomeState extends State<GozarHome> with WidgetsBindingObserver {
  static const _vault = FlutterSecureStorage();
  final profile = TextEditingController();
  String stage = 'off';
  String detail = 'VPN خاموش است.';
  String mode = 'all';
  Set<String> packages = {};
  bool busy = false;
  bool hideProfile = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    mode = widget.preferences.getString('gozar_routing_mode') == 'selected'
        ? 'selected' : 'all';
    packages = (widget.preferences.getStringList('gozar_selected_packages')
        ?? const <String>[]).toSet();
    unawaited(_loadProfile());
    unawaited(refresh());
  }

  Future<void> _loadProfile() async {
    try {
      final value = await _vault.read(key: 'gozar_xray_profile');
      if (mounted && value != null && profile.text.isEmpty) {
        profile.text = value;
      }
    } catch (_) { /* VPN can still be configured manually. */ }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    profile.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    try {
      final native = await SystemVpnBridge.status();
      if (!mounted) return;
      final status = native['stage']?.toString() ?? 'off';
      setState(() {
        stage = status;
        detail = switch (status) {
          'running' => 'تونل VPN اندروید فعال است. برای اطمینان از اتصال '
              'سرور، اینترنت برنامه‌های انتخاب‌شده را آزمایش کنید.',
          'starting' => 'در حال راه‌اندازی موتور Xray و تونل اندروید…',
          'consent' => 'مجوز VPN را در پنجره سیستم تأیید کنید.',
          'error' => 'موتور VPN راه‌اندازی نشد؛ کانفیگ و مجوز اندروید را بررسی کنید.',
          _ => 'VPN خاموش است.',
        };
      });
    } catch (_) {
      if (mounted) setState(() { detail = 'سرویس VPN در دسترس نیست.'; });
    }
  }

  void notice(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> connect() async {
    if (busy) return;
    setState(() { busy = true; });
    try {
      if (mode == 'selected' && packages.isEmpty) {
        throw const FormatException(
          'حداقل یک برنامه را انتخاب کنید یا حالت «همه برنامه‌ها» را بزنید.');
      }
      final input = profile.text.trim();
      final config = buildFullDeviceXrayConfig(input);
      await _vault.write(key: 'gozar_xray_profile', value: input);
      await SystemVpnBridge.start(config, mode: mode,
          packages: packages.toList());
      await refresh();
      // Android's permission sheet is asynchronous; do not claim connectivity
      // until the native service reports that it started its TUN core.
      for (var i = 0; i < 18 && mounted; i++) {
        if (stage == 'running' || stage == 'error' || stage == 'off') break;
        await Future<void>.delayed(const Duration(milliseconds: 850));
        await refresh();
      }
    } on FormatException catch (error) {
      notice(error.message.toString());
    } catch (_) {
      notice('اتصال برقرار نشد؛ مجوز VPN و فرمت کانفیگ را بررسی کنید.');
      await refresh();
    } finally {
      if (mounted) setState(() { busy = false; });
    }
  }

  Future<void> disconnect() async {
    if (busy) return;
    setState(() { busy = true; });
    try {
      await SystemVpnBridge.stop();
      await refresh();
    } catch (_) {
      notice('قطع VPN انجام نشد؛ دوباره تلاش کنید.');
    } finally {
      if (mounted) setState(() { busy = false; });
    }
  }

  Future<void> chooseApps() async {
    List<Map<String, String>> installed;
    try {
      installed = await SystemVpnBridge.installedApps();
    } catch (_) {
      notice('فهرست برنامه‌های گوشی دریافت نشد.');
      return;
    }
    if (!mounted) return;
    var choice = mode;
    final picked = Set<String>.from(packages);
    var search = '';
    final searchController = TextEditingController();
    try {
      await showModalBottomSheet<void>(
        context: context, isScrollControlled: true, showDragHandle: true,
        builder: (sheet) => StatefulBuilder(builder: (sheet, updateSheet) {
          final visible = installed.where((app) =>
              (app['label'] ?? '').toLowerCase().contains(search) ||
              (app['package'] ?? '').toLowerCase().contains(search)).toList();
          return SafeArea(child: Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16,
                MediaQuery.viewInsetsOf(sheet).bottom + 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('کدام برنامه‌ها از گذر استفاده کنند؟',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 8),
                const Text('نبض خبر و کافی‌نت نیز مانند بقیه برنامه‌های گوشی '
                    'در این فهرست قرار می‌گیرند.',
                    style: TextStyle(fontSize: 12)),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'all', label: Text('همه برنامه‌ها')),
                    ButtonSegment(value: 'selected',
                        label: Text('فقط انتخاب‌شده‌ها')),
                  ],
                  selected: {choice},
                  onSelectionChanged: (next) {
                    updateSheet(() { choice = next.first; });
                  },
                ),
                if (choice == 'selected') ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: searchController,
                    onChanged: (value) =>
                        updateSheet(() { search = value.toLowerCase().trim(); }),
                    decoration: const InputDecoration(
                      hintText: 'جست‌وجوی نام برنامه',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(picked.length.toString() + ' برنامه انتخاب شده',
                      style: const TextStyle(fontSize: 12)),
                  SizedBox(
                    height: MediaQuery.sizeOf(sheet).height * .40,
                    child: visible.isEmpty
                        ? const Center(child: Text('برنامه‌ای پیدا نشد.'))
                        : ListView.builder(
                            itemCount: visible.length,
                            itemBuilder: (_, index) {
                              final item = visible[index];
                              final package = item['package']!;
                              return CheckboxListTile(
                                key: ValueKey('gozar-app-' + package),
                                dense: true,
                                title: Text(item['label']!),
                                subtitle: Text(package,
                                    textDirection: TextDirection.ltr,
                                    style: const TextStyle(fontSize: 10)),
                                value: picked.contains(package),
                                onChanged: (yes) {
                                  updateSheet(() {
                                    if (yes == true) {
                                      picked.add(package);
                                    } else {
                                      picked.remove(package);
                                    }
                                  });
                                },
                              );
                            },
                          ),
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: choice == 'selected' && picked.isEmpty
                      ? null : () async {
                    await widget.preferences.setString(
                        'gozar_routing_mode', choice);
                    await widget.preferences.setStringList(
                        'gozar_selected_packages', picked.toList());
                    if (!mounted) return;
                    setState(() {
                      mode = choice;
                      packages = picked;
                    });
                    if (sheet.mounted) Navigator.of(sheet).pop();
                    if (stage == 'running') {
                      notice('برای اعمال انتخاب جدید، VPN را قطع و دوباره وصل کنید.');
                    }
                  },
                  child: const Text('ذخیره انتخاب برنامه‌ها'),
                ),
              ],
            ),
          ));
        }),
      );
    } finally {
      searchController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = stage == 'running';
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('گذر'),
          centerTitle: true, backgroundColor: colors.surface),
      body: SafeArea(child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Card(child: Padding(padding: const EdgeInsets.all(22),
            child: Column(children: [
              Icon(connected ? Icons.shield_rounded : Icons.shield_outlined,
                  size: 62, color: connected ? colors.primary
                      : colors.onSurfaceVariant),
              const SizedBox(height: 8),
              const Text('گذر', style: TextStyle(
                  fontSize: 30, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text('VPN مستقل برای اینترنت گوشی',
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(detail, key: const ValueKey('gozar-vpn-status'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.primary)),
            ]),
          )),
          const SizedBox(height: 14),
          Card(child: Padding(padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('کانفیگ VPN', style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 17)),
                const SizedBox(height: 8),
                const Text('لینک VMess، VLESS، Trojan یا JSON کامل Xray را '
                    'اینجا وارد کنید. کانفیگ در حافظه امن همین برنامه ذخیره می‌شود.',
                    style: TextStyle(fontSize: 12)),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('gozar-config'),
                  controller: profile,
                  obscureText: hideProfile,
                  maxLines: hideProfile ? 1 : 3,
                  autocorrect: false,
                  enableSuggestions: false,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.left,
                  decoration: InputDecoration(
                    hintText: 'vmess:// یا vless:// یا trojan://',
                    suffixIcon: IconButton(
                      tooltip: hideProfile ? 'نمایش کانفیگ' : 'پنهان‌کردن کانفیگ',
                      onPressed: () =>
                          setState(() { hideProfile = !hideProfile; }),
                      icon: Icon(hideProfile
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const ValueKey('gozar-choose-apps'),
                  onPressed: busy ? null : chooseApps,
                  icon: const Icon(Icons.apps_outlined),
                  label: Text(mode == 'all' ? 'انتخاب برنامه‌ها: همه برنامه‌ها'
                      : 'انتخاب برنامه‌ها: فقط ' +
                        packages.length.toString() + ' برنامه'),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  key: const ValueKey('gozar-connect'),
                  onPressed: busy || connected ? null : connect,
                  icon: const Icon(Icons.power_settings_new),
                  label: const Text('اتصال VPN'),
                ),
                const SizedBox(height: 5),
                OutlinedButton.icon(
                  key: const ValueKey('gozar-disconnect'),
                  onPressed: busy || stage == 'off' ? null : disconnect,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('قطع اتصال'),
                ),
                TextButton.icon(
                  onPressed: busy ? null : refresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('بررسی وضعیت اتصال'),
                ),
              ],
            ),
          )),
          const SizedBox(height: 12),
          const Padding(padding: EdgeInsets.all(8),
            child: Text('گذر به‌صورت جداگانه نصب و اجرا می‌شود. '
              'اگر «همه برنامه‌ها» فعال باشد، کافی‌نت و نبض خبر نیز '
              'از VPN گوشی استفاده می‌کنند. خودِ گذر برای جلوگیری از '
              'حلقه‌شدن اتصال از تونل خودش عبور نمی‌کند.',
              style: TextStyle(fontSize: 12), textAlign: TextAlign.justify),
          ),
        ],
      )),
    );
  }
}
