import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'gozar_visuals.dart';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'td_system_vpn.dart';

class GozarProfile {
  final String name;
  final String link;
  const GozarProfile(this.name, this.link);

  factory GozarProfile.fromJson(Map<String, dynamic> input) =>
      GozarProfile(input['name']?.toString() ?? 'سرور شخصی',
          input['link']?.toString() ?? '');

  Map<String, String> toJson() => {'name': name, 'link': link};
}

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
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: GozarPalette.cyan,
        brightness: Brightness.dark,
        surface: GozarPalette.navy,
      ),
      scaffoldBackgroundColor: GozarPalette.base,
      fontFamily: 'Roboto',
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: Color(0xff203657),
        contentTextStyle: TextStyle(color: GozarPalette.text),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xff49628b)),
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

class _GozarHomeState extends State<GozarHome> with WidgetsBindingObserver {
  static const _vault = FlutterSecureStorage();
  final profile = TextEditingController();
  String stage = 'off';
  String detail = 'VPN خاموش است.';
  String mode = 'all';
  Set<String> packages = {};
  bool busy = false;
  bool hideProfile = true;
  int currentPage = 0;
  int selectedProfile = -1;
  List<GozarProfile> profiles = [];
  Timer? countersTimer;
  bool samplingCounters = false;
  DateTime? connectedObservedAt;
  DateTime? sampledAt;
  int? receivedAtSample;
  int? sentAtSample;
  int? receivedAtStart;
  int? sentAtStart;
  double? receivedMbps;
  double? sentMbps;
  int? receivedSession;
  int? sentSession;
  final List<double> receivedSeries = [];
  final List<double> sentSeries = [];
  int? tcpLatencyMs;
  bool checkingTcp = false;

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
      final encoded = await _vault.read(key: 'gozar_profiles_v2');
      final parsed = encoded == null ? null : jsonDecode(encoded);
      final saved = <GozarProfile>[];
      if (parsed is List) {
        for (final entry in parsed) {
          if (entry is Map) {
            final p = GozarProfile.fromJson(Map<String, dynamic>.from(entry));
            if (p.link.isNotEmpty) saved.add(p);
          }
        }
      }
      // Migrate the previously installed Gozar profile, without losing it.
      final legacy = await _vault.read(key: 'gozar_xray_profile');
      if (saved.isEmpty && legacy != null && legacy.trim().isNotEmpty) {
        saved.add(GozarProfile('سرور قبلی', legacy.trim()));
      }
      if (!mounted) return;
      final preferred = widget.preferences.getInt('gozar_profile_index') ?? 0;
      final index = saved.isEmpty ? -1 : preferred.clamp(0, saved.length - 1);
      setState(() {
        profiles = saved;
        selectedProfile = index;
      });
      if (index >= 0 && profile.text.isEmpty) {
        profile.text = saved[index].link;
      }
    } catch (_) {
      // Secure storage may be temporarily unavailable; manual entry remains.
    }
  }

  Future<void> _persistProfiles() async {
    await _vault.write(key: 'gozar_profiles_v2',
        value: jsonEncode(profiles.map((p) => p.toJson()).toList()));
    await widget.preferences.setInt('gozar_profile_index',
        selectedProfile < 0 ? 0 : selectedProfile);
  }

  Future<void> saveProfile({bool quiet = false}) async {
    final input = profile.text.trim();
    try {
      // Use exactly the same strict config validation as the VPN connection.
      buildFullDeviceXrayConfig(input);
      final updated = List<GozarProfile>.from(profiles);
      final index = selectedProfile;
      if (index >= 0 && index < updated.length) {
        updated[index] = GozarProfile(updated[index].name, input);
      } else {
        updated.add(GozarProfile('سرور ' + (updated.length + 1).toString(),
            input));
      }
      if (!mounted) return;
      setState(() {
        profiles = updated;
        selectedProfile = index >= 0 && index < updated.length
            ? index : updated.length - 1;
      });
      await _persistProfiles();
      await _vault.write(key: 'gozar_xray_profile', value: input);
      if (!quiet) notice('کانفیگ در حافظه امن گذر ذخیره شد.');
    } on FormatException catch (error) {
      if (!quiet) notice(error.message.toString());
      rethrow;
    } catch (_) {
      if (!quiet) notice('ذخیره کانفیگ انجام نشد؛ دوباره تلاش کنید.');
      rethrow;
    }
  }

  void selectProfile(int index) {
    if (index < 0 || index >= profiles.length) return;
    setState(() {
      selectedProfile = index;
      profile.text = profiles[index].link;
      tcpLatencyMs = null;
      currentPage = 0;
    });
    unawaited(widget.preferences.setInt('gozar_profile_index', index));
    if (stage == 'running') {
      notice('برای استفاده از سرور جدید، اتصال را قطع و دوباره برقرار کنید.');
    }
  }

  void addProfile() {
    setState(() {
      selectedProfile = -1;
      profile.clear();
      tcpLatencyMs = null;
      currentPage = 0;
    });
  }

  Future<void> renameProfile(int index) async {
    if (index < 0 || index >= profiles.length) return;
    final name = TextEditingController(text: profiles[index].name);
    try {
      final value = await showDialog<String>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('نام سرور'),
          content: TextField(
            autofocus: true, controller: name,
            maxLength: 40,
            decoration: const InputDecoration(hintText: 'نام دلخواه'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialog).pop(),
                child: const Text('انصراف')),
            FilledButton(
              onPressed: () => Navigator.of(dialog).pop(name.text.trim()),
              child: const Text('ذخیره'),
            ),
          ],
        ),
      );
      if (value == null || value.isEmpty || !mounted) return;
      final updated = List<GozarProfile>.from(profiles);
      updated[index] = GozarProfile(value, updated[index].link);
      setState(() { profiles = updated; });
      await _persistProfiles();
    } finally {
      name.dispose();
    }
  }

  Future<void> deleteProfile(int index) async {
    if (stage == 'running') {
      notice('برای حذف سرور فعال، ابتدا VPN را قطع کنید.');
      return;
    }
    if (index < 0 || index >= profiles.length) return;
    final updated = List<GozarProfile>.from(profiles)..removeAt(index);
    if (!mounted) return;
    final nextIndex = updated.isEmpty ? -1
        : selectedProfile == index ? 0
        : selectedProfile > index ? selectedProfile - 1 : selectedProfile;
    setState(() {
      profiles = updated;
      selectedProfile = nextIndex;
      profile.text = nextIndex < 0 ? '' : updated[nextIndex].link;
    });
    await _persistProfiles();
    if (updated.isEmpty) await _vault.delete(key: 'gozar_xray_profile');
  }

  void _stopCounters() {
    countersTimer?.cancel();
    countersTimer = null;
    receivedAtSample = null;
    sentAtSample = null;
    sampledAt = null;
    receivedAtStart = null;
    sentAtStart = null;
    receivedMbps = null;
    sentMbps = null;
    receivedSession = null;
    sentSession = null;
    receivedSeries.clear();
    sentSeries.clear();
    connectedObservedAt = null;
  }

  void _startCounters() {
    if (countersTimer != null) return;
    connectedObservedAt = DateTime.now();
    unawaited(sampleCounters());
    countersTimer = Timer.periodic(const Duration(seconds: 2),
        (_) => unawaited(sampleCounters()));
  }

  Future<void> sampleCounters() async {
    if (!mounted || samplingCounters || stage != 'running') return;
    samplingCounters = true;
    try {
      final now = DateTime.now();
      final counters = await SystemVpnBridge.networkCounters();
      if (!mounted || stage != 'running') return;
      final rx = counters['rx'] ?? -1;
      final tx = counters['tx'] ?? -1;
      if (rx < 0 || tx < 0) return;
      if (receivedAtStart == null || sentAtStart == null ||
          receivedAtSample == null || sentAtSample == null ||
          sampledAt == null) {
        setState(() {
          receivedAtStart = rx;
          sentAtStart = tx;
          receivedAtSample = rx;
          sentAtSample = tx;
          sampledAt = now;
        });
        return;
      }
      final seconds = now.difference(sampledAt!).inMilliseconds / 1000;
      if (seconds <= 0) return;
      final download = rx >= receivedAtSample!
          ? (rx - receivedAtSample!) * 8 / (seconds * 1000000) : 0.0;
      final upload = tx >= sentAtSample!
          ? (tx - sentAtSample!) * 8 / (seconds * 1000000) : 0.0;
      setState(() {
        receivedMbps = download;
        sentMbps = upload;
        receivedSession = rx >= receivedAtStart!
            ? rx - receivedAtStart! : 0;
        sentSession = tx >= sentAtStart! ? tx - sentAtStart! : 0;
        receivedAtSample = rx;
        sentAtSample = tx;
        sampledAt = now;
        receivedSeries.add(download);
        sentSeries.add(upload);
        if (receivedSeries.length > 27) receivedSeries.removeAt(0);
        if (sentSeries.length > 27) sentSeries.removeAt(0);
      });
    } catch (_) {
      // TrafficStats may be unsupported by a particular Android build.
      // A missing reading stays unavailable; never fabricate chart values.
    } finally {
      samplingCounters = false;
    }
  }

  String _speed(double? speed) =>
      speed == null ? '—' : speed.toStringAsFixed(2) + ' Mb/s';

  String _volume(int? bytes) {
    if (bytes == null) return '—';
    if (bytes < 1024) return bytes.toString() + ' B';
    if (bytes < 1048576) return (bytes / 1024).toStringAsFixed(1) + ' KB';
    if (bytes < 1073741824) {
      return (bytes / 1048576).toStringAsFixed(1) + ' MB';
    }
    return (bytes / 1073741824).toStringAsFixed(2) + ' GB';
  }

  Future<void> checkTcpLatency() async {
    if (checkingTcp) return;
    setState(() { checkingTcp = true; tcpLatencyMs = null; });
    try {
      final config = jsonDecode(buildFullDeviceXrayConfig(profile.text.trim()))
          as Map<String, dynamic>;
      final outbound = (config['outbounds'] as List).first as Map;
      final settings = outbound['settings'] as Map;
      final endpoint = (settings['vnext'] as List?)?.first ??
          (settings['servers'] as List?)?.first;
      if (endpoint is! Map || endpoint['address'] is! String ||
          endpoint['port'] is! int) {
        throw const FormatException('نشانی سرور برای آزمایش TCP در دسترس نیست.');
      }
      // Because Gozar hosts the VPN, its own sockets bypass the TUN. This
      // checks direct TCP reachability, not Telegram ping or VPN throughput.
      final timer = Stopwatch()..start();
      final socket = await Socket.connect(endpoint['address'] as String,
          endpoint['port'] as int, timeout: const Duration(seconds: 5));
      timer.stop();
      socket.destroy();
      if (mounted) setState(() { tcpLatencyMs = timer.elapsedMilliseconds; });
    } catch (_) {
      notice('ارتباط مستقیم TCP با سرور برقرار نشد؛ این تست سرعت VPN نیست.');
    } finally {
      if (mounted) setState(() { checkingTcp = false; });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    countersTimer?.cancel();
    profile.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    try {
      final native = await SystemVpnBridge.status();
      if (!mounted) return;
      final status = native['stage']?.toString() ?? 'off';
      if (status == 'running') {
        _startCounters();
      } else if (countersTimer != null) {
        _stopCounters();
      }
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
      // Only the selected server is changed; native TUN and routing logic
      // remains the same as the previous released Gozar build.
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

