import 'dart:async';
import 'dart:convert';

import 'gozar_visuals.dart';
import 'gozar_subscription.dart';
import 'gozar_shortcuts.dart';
import 'gozar_launcher.dart';
import 'gozar_dashboard_clock.dart';

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
      fontFamily: 'Vazirmatn',
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
  bool disconnecting = false;
  int operationId = 0;
  int statusReadId = 0;
  Timer? statusTimer;
  bool hideProfile = true;
  int currentPage = 0;
  // Mount tabs lazily once, then keep their State (launcher page/scroll
  // position, icon futures, settings) alive when switching between tabs.
  final Set<int> visitedPages = {0};
  late final GozarLauncher launcherPage;
  int selectedProfile = -1;
  List<GozarProfile> profiles = [];
  List<GozarShortcut> shortcuts = [];
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
  final Map<String, int> tcpLatencies = {};
  final Set<String> checkingTcpProfiles = {};
  bool importingSubscription = false;
  bool choosingBestServer = false;
  bool testingProxy = false;
  bool? proxyVerified;
  int? proxyLatencyMs;
  int proxyTestId = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    shortcuts = GozarShortcutStore.load(widget.preferences);
    launcherPage = GozarLauncher(
      preferences: widget.preferences, onOpenApp: _openShortcut);
    mode = widget.preferences.getString('gozar_routing_mode') == 'selected'
        ? 'selected' : 'all';
    packages = (widget.preferences.getStringList('gozar_selected_packages')
        ?? const <String>[]).toSet();
    unawaited(_loadProfile());
    unawaited(refresh());
    // Observe OS-initiated disconnects without rebuilding the whole UI every frame.
    statusTimer = Timer.periodic(const Duration(seconds: 2),
        (_) => unawaited(refresh()));
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

  Future<void> importSubscription() async {
    if (importingSubscription) return;
    final controller = TextEditingController();
    try {
      final url = await showDialog<String>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('افزودن لینک اشتراک'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(
              hintText: 'https://example.com/subscription',
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialog).pop(),
                child: const Text('انصراف')),
            FilledButton(
              onPressed: () => Navigator.of(dialog).pop(controller.text.trim()),
              child: const Text('دریافت'),
            ),
          ],
        ),
      );
      if (url == null || url.isEmpty || !mounted) return;
      setState(() { importingSubscription = true; });
      final nodes = await fetchGozarSubscription(url);
      final updated = List<GozarProfile>.from(profiles);
      final existing = updated.map((item) => item.link).toSet();
      var added = 0;
      for (final node in nodes) {
        if (existing.add(node.link)) {
          updated.add(GozarProfile(node.name, node.link));
          added++;
        }
      }
      if (!mounted) return;
      setState(() {
        profiles = updated;
        if (selectedProfile < 0 && updated.isNotEmpty) {
          selectedProfile = 0;
          profile.text = updated.first.link;
        }
      });
      await _persistProfiles();
      notice(added == 0
          ? 'همه سرورهای این اشتراک از قبل وجود داشتند.'
          : added.toString() + ' سرور معتبر از اشتراک اضافه شد.');
    } on FormatException catch (error) {
      notice(error.message.toString());
    } catch (_) {
      notice('دریافت اشتراک انجام نشد؛ اینترنت و اعتبار لینک را بررسی کنید.');
    } finally {
      controller.dispose();
      if (mounted) setState(() { importingSubscription = false; });
    }
  }

  Future<void> chooseBestServer() async {
    if (choosingBestServer || profiles.isEmpty) return;
    setState(() { choosingBestServer = true; });
    try {
      final result = await chooseBestGozarNode(
        profiles.map((item) => item.link).toList(),
      );
      if (result == null) {
        notice('هیچ سرور قابل دسترسی در آزمایش TCP پیدا نشد.');
        return;
      }
      if (!mounted) return;
      setState(() {
        selectedProfile = result.index;
        profile.text = profiles[result.index].link;
        tcpLatencies[profiles[result.index].link] = result.latencyMs;
        currentPage = 0;
      });
      await widget.preferences.setInt('gozar_profile_index', result.index);
      notice('سرور با کمترین تأخیر TCP انتخاب شد: ' + profiles[result.index].name +
          ' — ' + result.latencyMs.toString() + ' ms');
      if (stage == 'running') {
        notice('برای اعمال سرور جدید، VPN را قطع و دوباره وصل کنید.');
      }
    } finally {
      if (mounted) setState(() { choosingBestServer = false; });
    }
  }

  void selectProfile(int index) {
    if (index < 0 || index >= profiles.length) return;
    setState(() {
      selectedProfile = index;
      profile.text = profiles[index].link;
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

  Future<void> checkTcpLatency(int index) async {
    if (index < 0 || index >= profiles.length) return;
    final link = profiles[index].link;
    if (checkingTcpProfiles.contains(link)) return;
    setState(() {
      checkingTcpProfiles.add(link);
      tcpLatencies.remove(link);
    });
    try {
      final latency = await probeGozarNode(
        link,
        timeout: const Duration(seconds: 5),
      );
      if (latency == null) {
        throw StateError('TCP unreachable');
      }
      if (mounted && profiles.any((item) => item.link == link)) {
        setState(() { tcpLatencies[link] = latency; });
      }
    } catch (_) {
      notice('اتصال TCP این سرور برقرار نشد.');
    } finally {
      if (mounted) {
        setState(() { checkingTcpProfiles.remove(link); });
      }
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
    statusTimer?.cancel();
    profile.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    final readId = ++statusReadId;
    final operation = operationId;
    try {
      final native = await SystemVpnBridge.status();
      // Ignore stale responses started before disconnect or a newer read.
      if (!mounted || readId != statusReadId || operation != operationId) {
        return;
      }
      final status = native['stage']?.toString() ?? 'off';
      // A status read that began before a stop request must not repaint
      // "running" over the user's explicit disconnect action.
      if (disconnecting && (status == 'running' || status == 'starting')) {
        return;
      }
      if (status == 'running') {
        _startCounters();
      } else if (countersTimer != null) {
        _stopCounters();
      }
      final nextDetail = switch (status) {
          'running' => 'تونل اندروید فعال است؛ اتصال اینترنت سرور را '
              'با دکمه آزمون جداگانه بررسی کنید.',
          'starting' => 'در حال راه‌اندازی موتور Xray و تونل اندروید…',
          'consent' => 'مجوز VPN را در پنجره سیستم تأیید کنید.',
          'stopping' => 'در حال بستن تونل و توقف موتور VPN…',
          'error' => 'موتور VPN راه‌اندازی نشد؛ کانفیگ و مجوز اندروید را بررسی کنید.',
          _ => 'VPN خاموش است.',
        };
      final clearProbe = status != 'running' &&
          (testingProxy || proxyVerified != null || proxyLatencyMs != null);
      if (status != stage || nextDetail != detail || clearProbe) {
        setState(() {
          stage = status;
          detail = nextDetail;
          if (clearProbe) {
            proxyTestId++;
            testingProxy = false;
            proxyVerified = null;
            proxyLatencyMs = null;
          }
        });
      }
    } catch (_) {
      if (mounted && readId == statusReadId && operation == operationId) {
        setState(() { detail = 'سرویس VPN در دسترس نیست.'; });
      }
    }
  }

  /// A manual end-to-end test through Xray's selected outbound.
  /// A blocked probe endpoint is inconclusive, not proof that the VPN is off.
  Future<void> testProxyConnection() async {
    if (!mounted || stage != 'running' || testingProxy) return;
    final testId = ++proxyTestId;
    setState(() {
      testingProxy = true;
      proxyVerified = null;
      proxyLatencyMs = null;
    });
    try {
      final delay = await SystemVpnBridge.measureConnection();
      if (!mounted || stage != 'running' || testId != proxyTestId) return;
      setState(() {
        proxyVerified = delay != null;
        proxyLatencyMs = delay;
      });
    } catch (_) {
      if (!mounted || stage != 'running' || testId != proxyTestId) return;
      setState(() {
        proxyVerified = false;
        proxyLatencyMs = null;
      });
    } finally {
      if (mounted && testId == proxyTestId) {
        setState(() { testingProxy = false; });
      }
    }
  }

  void notice(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> connect() async {
    if (busy || disconnecting || stage == 'stopping') return;
    final requestId = ++operationId;
    setState(() {
      busy = true;
      proxyTestId++;
      testingProxy = false;
      proxyVerified = null;
      proxyLatencyMs = null;
    });
    try {
      if (mode == 'selected' && packages.isEmpty) {
        throw const FormatException(
          'حداقل یک برنامه را انتخاب کنید یا حالت «همه برنامه‌ها» را بزنید.');
      }
      final input = profile.text.trim();
      final config = buildFullDeviceXrayConfig(input);
      await _vault.write(key: 'gozar_xray_profile', value: input);
      if (requestId != operationId) return;
      // Only the selected server is changed; native TUN and routing logic
      // remains the same as the previous released Gozar build.
      await SystemVpnBridge.start(config, mode: mode,
          packages: packages.toList());
      if (requestId != operationId) {
        // Stop can be pressed during the async permission/start operation.
        await SystemVpnBridge.stop();
        return;
      }
      await refresh();
      // Android's permission sheet is asynchronous; do not claim connectivity
      // until the native service reports that it started its TUN core.
      for (var i = 0; i < 18 && mounted && requestId == operationId; i++) {
        if (stage == 'running' || stage == 'error' || stage == 'off' ||
            stage == 'stopping') break;
        await Future<void>.delayed(const Duration(milliseconds: 850));
        await refresh();
      }
    } on FormatException catch (error) {
      notice(error.message.toString());
    } catch (_) {
      notice('اتصال برقرار نشد؛ مجوز VPN و فرمت کانفیگ را بررسی کنید.');
      await refresh();
    } finally {
      if (mounted && requestId == operationId) {
        setState(() { busy = false; });
      }
    }
  }

  Future<void> disconnect() async {
    // Disconnect must work even while an earlier connect() is awaiting
    // permission, profile storage or native startup.
    if (disconnecting) return;
    final requestId = ++operationId;
    setState(() {
      disconnecting = true;
      busy = false;
      stage = 'stopping';
      detail = 'در حال بستن تونل و توقف موتور VPN…';
      proxyTestId++;
      testingProxy = false;
      proxyVerified = null;
      proxyLatencyMs = null;
    });
    try {
      await SystemVpnBridge.stop();
      // Do not show OFF until Android confirms the TUN/core are stopped.
      for (var i = 0; i < 24 && mounted && requestId == operationId; i++) {
        await refresh();
        if (stage == 'off' || stage == 'error') break;
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      if (stage == 'stopping') {
        notice('توقف موتور هنوز ادامه دارد؛ وضعیت VPN را بررسی کنید.');
      }
    } catch (_) {
      notice('قطع VPN انجام نشد؛ دوباره تلاش کنید.');
      await refresh();
    } finally {
      if (mounted && requestId == operationId) {
        setState(() { disconnecting = false; });
      }
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

  String get serverLabel =>
      selectedProfile >= 0 && selectedProfile < profiles.length
          ? profiles[selectedProfile].name : 'کانفیگ جدید';

  Widget _eyebrow(IconData icon, String title, {Color? color}) => Row(
    children: [
      Icon(icon, color: color ?? GozarPalette.cyan, size: 20),
      const SizedBox(width: 9),
      Expanded(child: Text(title, style: const TextStyle(
          color: GozarPalette.text, fontWeight: FontWeight.w800,
          fontSize: 16))),
    ],
  );

  Future<void> _saveShortcuts(List<GozarShortcut> updated) async {
    final previous = shortcuts;
    if (updated.length > GozarShortcutStore.maxCount) {
      notice('حداکثر ۱۰ میانبر در صفحه اصلی قابل ثبت است.');
      return;
    }
    setState(() { shortcuts = updated; });
    final saved = await GozarShortcutStore.save(widget.preferences, updated);
    if (!saved && mounted) {
      setState(() { shortcuts = previous; });
      notice('میانبر ذخیره نشد؛ دوباره تلاش کنید.');
    }
  }

  Future<void> _addShortcut(GozarShortcut shortcut) async {
    if (shortcuts.any((item) => item.key == shortcut.key)) {
      notice('این میانبر قبلاً اضافه شده است.');
      return;
    }
    if (shortcuts.length >= GozarShortcutStore.maxCount) {
      notice('حداکثر ۱۰ میانبر مجاز است؛ ابتدا یکی را حذف کنید.');
      return;
    }
    await _saveShortcuts([...shortcuts, shortcut]);
  }

  Future<void> _renameShortcut(GozarShortcut shortcut) async {
    final controller = TextEditingController(text: shortcut.title);
    try {
      final renamed = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('ویرایش نام میانبر'),
          content: TextField(
            key: const ValueKey('gozar-edit-shortcut-name'),
            controller: controller,
            maxLength: 48,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'نام نمایشی',
              helperText: 'نام برنامه یا نشانی سایت تغییر نمی‌کند.',
            ),
            onSubmitted: (value) {
              final trimmed = value.trim();
              if (trimmed.isNotEmpty) {
                Navigator.pop(dialogContext, trimmed);
              }
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext),
                child: const Text('انصراف')),
            FilledButton(
              key: const ValueKey('gozar-apply-shortcut-name'),
              onPressed: () {
                final trimmed = controller.text.trim();
                if (trimmed.isEmpty || trimmed.length > 48) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text(
                      'نام میانبر باید بین ۱ تا ۴۸ نویسه باشد.')));
                  return;
                }
                Navigator.pop(dialogContext, trimmed);
              },
              child: const Text('ذخیره نام'),
            ),
          ],
        ),
      );
      if (!mounted || renamed == null || renamed == shortcut.title) return;
      // Recompute the index against the latest list: the target's immutable
      // package/activity or URL identifies it even after a reorder.
      final index = shortcuts.indexWhere((item) => item.key == shortcut.key);
      if (index == -1) return;
      final updated = List<GozarShortcut>.from(shortcuts);
      updated[index] = updated[index].renamed(renamed);
      await _saveShortcuts(updated);
    } finally {
      // Do not dispose controllers until the route's closing transition ends.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      controller.dispose();
    }
  }

  Future<void> _chooseShortcutApp() async {
    if (shortcuts.length >= GozarShortcutStore.maxCount) {
      notice('برای افزودن میانبر، ابتدا یکی را حذف کنید.');
      return;
    }
    List<Map<String, String>> installed;
    try {
      installed = await SystemVpnBridge.installedApps();
    } catch (_) {
      notice('فهرست برنامه‌های نصب‌شده دریافت نشد.');
      return;
    }
    if (!mounted) return;
    var filter = '';
    final chosen = await showModalBottomSheet<GozarShortcut>(
      context: context,
      isScrollControlled: true,
      backgroundColor: GozarPalette.navy,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setPickerState) {
          final matching = installed.where((app) =>
            (app['label'] ?? '').toLowerCase().contains(filter) ||
            (app['package'] ?? '').toLowerCase().contains(filter)).toList();
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
              ),
              child: SizedBox(
                height: MediaQuery.sizeOf(sheetContext).height * .73,
                child: Column(children: [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('انتخاب برنامه برای میانبر',
                      style: TextStyle(color: GozarPalette.text,
                        fontWeight: FontWeight.w800, fontSize: 17)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: TextField(
                      key: const ValueKey('gozar-app-shortcut-search'),
                      onChanged: (value) => setPickerState(() {
                        filter = value.trim().toLowerCase();
                      }),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search_rounded),
                        hintText: 'نام برنامه را جستجو کنید',
                      ),
                    ),
                  ),
                  const SizedBox(height: 9),
                  Expanded(child: matching.isEmpty
                    ? const Center(child: Text(
                        'برنامه‌ای پیدا نشد.',
                        style: TextStyle(color: GozarPalette.muted)))
                    : ListView.builder(
                        itemCount: matching.length,
                        itemBuilder: (context, index) {
                          final app = matching[index];
                          final shortcut = GozarShortcut(
                            kind: 'app',
                            target: app['package'] ?? '',
                            title: app['label'] ?? '',
                            component: app['component'] ?? '',
                          );
                          final exists = shortcuts.any(
                              (item) => item.key == shortcut.key);
                          return ListTile(
                            leading: GozarShortcutIcon(shortcut: shortcut),
                            title: Text(shortcut.title),
                            subtitle: Text(shortcut.target,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                            trailing: exists
                              ? const Icon(Icons.check_circle,
                                  color: GozarPalette.green)
                              : const Icon(Icons.add_circle_outline,
                                  color: GozarPalette.cyan),
                            onTap: exists ? null : () =>
                              Navigator.pop(sheetContext, shortcut),
                          );
                        },
                      )),
                ]),
              ),
            ),
          );
        },
      ),
    );
    if (chosen != null && mounted) await _addShortcut(chosen);
  }

  Future<void> _addWebShortcut() async {
    if (shortcuts.length >= GozarShortcutStore.maxCount) {
      notice('برای افزودن میانبر، ابتدا یکی را حذف کنید.');
      return;
    }
    final name = TextEditingController();
    final link = TextEditingController();
    try {
      final chosen = await showDialog<GozarShortcut>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('افزودن میانبر سایت'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              key: const ValueKey('gozar-web-shortcut-title'),
              controller: name, maxLength: 48,
              decoration: const InputDecoration(hintText: 'نام میانبر'),
            ),
            TextField(
              key: const ValueKey('gozar-web-shortcut-url'),
              controller: link,
              keyboardType: TextInputType.url,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(
                hintText: 'https://example.com'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext),
                child: const Text('انصراف')),
            FilledButton(
              key: const ValueKey('gozar-save-web-shortcut'),
              onPressed: () {
                final title = name.text.trim();
                final entered = link.text.trim();
                final full = entered.startsWith('https://')
                    ? entered : 'https://' + entered;
                final url = GozarShortcut.validWebUrl(full);
                if (title.isEmpty || title.length > 48 || url == null ||
                    full.length > 2048) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text(
                      'نام و نشانی معتبر HTTPS وارد کنید.')));
                  return;
                }
                Navigator.pop(dialogContext, GozarShortcut(
                    kind: 'web', target: full, title: title));
              },
              child: const Text('ذخیره'),
            ),
          ],
        ),
      );
      if (chosen != null && mounted) await _addShortcut(chosen);
    } finally {
      // Allow the closing dialog animation to finish before controllers die.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      name.dispose();
      link.dispose();
    }
  }

  Future<void> _openShortcut(GozarShortcut shortcut) async {
    try {
      if (shortcut.kind == 'web') {
        await SystemVpnBridge.openShortcutWeb(
            shortcut.target, shortcut.title);
      } else {
        await SystemVpnBridge.openShortcutApp(shortcut.target,
            component: shortcut.component);
      }
    } catch (_) {
      notice(shortcut.kind == 'web'
          ? 'سایت در مرورگر داخلی باز نشد.'
          : 'برنامه باز نشد. از تنظیمات، میانبر را حذف و دوباره انتخاب کنید.');
    }
  }

  Widget _shortcutTile(GozarShortcut shortcut) => InkWell(
    key: ValueKey('gozar-shortcut-' + shortcut.key),
    borderRadius: BorderRadius.circular(16),
    onTap: () => _openShortcut(shortcut),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Expanded(child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xff153b62), Color(0xff0b213b)]),
          border: Border.all(color: GozarPalette.blue.withOpacity(.42)),
        ),
        child: Center(child: GozarShortcutIcon(
            shortcut: shortcut, size: 44)),
      )),
      const SizedBox(height: 4),
      Text(shortcut.title, maxLines: 1, overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: const TextStyle(color: GozarPalette.text,
          fontSize: 11, fontWeight: FontWeight.w600)),
    ]),
  );

  Widget _shortcutPanel() {
    return GozarPanel(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 15),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.apps_rounded, color: GozarPalette.cyan, size: 27),
          const SizedBox(width: 7),
          const Expanded(child: Text('میانبر برنامه‌ها',
            style: TextStyle(color: GozarPalette.text,
              fontSize: 18, fontWeight: FontWeight.w800))),
          Text(persianDigits(shortcuts.length) + '/۱۰',
            style: const TextStyle(color: GozarPalette.muted)),
          IconButton(
            key: const ValueKey('gozar-shortcut-settings'),
            tooltip: 'مدیریت میانبرها',
            onPressed: () => setState(() {
              visitedPages.add(3);
              currentPage = 3;
            }),
            icon: const Icon(Icons.tune_rounded, color: GozarPalette.cyan)),
        ]),
        const SizedBox(height: 10),
        if (shortcuts.isEmpty) ...[
          const Padding(
            padding: EdgeInsets.all(14),
            child: Text(
              'هنوز میانبری ثبت نکرده‌اید. برنامه‌ها و سایت‌های دلخواهتان را '
              'از تنظیمات اضافه کنید.',
              textAlign: TextAlign.center,
              style: TextStyle(color: GozarPalette.muted, fontSize: 12))),
          OutlinedButton.icon(
            key: const ValueKey('gozar-manage-shortcuts-empty'),
            onPressed: () => setState(() {
              visitedPages.add(3);
              currentPage = 3;
            }),
            icon: const Icon(Icons.add_rounded),
            label: const Text('افزودن میانبر'),
          ),
        ] else LayoutBuilder(builder: (context, constraints) {
          final columns = constraints.maxWidth >= 420 ? 5
              : constraints.maxWidth >= 300 ? 4 : 3;
          return GridView.builder(
            key: const ValueKey('gozar-user-shortcut-grid'),
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            itemCount: shortcuts.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: 8, crossAxisSpacing: 7,
              childAspectRatio: .98,
            ),
            itemBuilder: (context, index) => _shortcutTile(shortcuts[index]),
          );
        }),
      ]),
    );
  }

  Widget _shortcutSettings() => GozarPanel(
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _eyebrow(Icons.apps_rounded, 'میانبر برنامه‌ها'),
      const SizedBox(height: 8),
      const Text(
        'برنامه‌ها و سایت‌های دلخواه را اضافه کنید، نام آن‌ها را تغییر دهید '
        'و با نگه‌داشتن و کشیدن دستگیره، ترتیب نمایش در صفحه اصلی را بچینید.',
        style: TextStyle(color: GozarPalette.muted, fontSize: 12),
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: OutlinedButton.icon(
          key: const ValueKey('gozar-add-app-shortcut'),
          onPressed: shortcuts.length >= GozarShortcutStore.maxCount
              ? null : _chooseShortcutApp,
          icon: const Icon(Icons.apps_rounded),
          label: const Text('برنامه نصب‌شده'),
        )),
        const SizedBox(width: 8),
        Expanded(child: OutlinedButton.icon(
          key: const ValueKey('gozar-add-web-shortcut'),
          onPressed: shortcuts.length >= GozarShortcutStore.maxCount
              ? null : _addWebShortcut,
          icon: const Icon(Icons.public_rounded),
          label: const Text('سایت'),
        )),
      ]),
      if (shortcuts.isEmpty)
        const Padding(padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('فهرست میانبرها خالی است.',
            style: TextStyle(color: GozarPalette.muted))),
      if (shortcuts.isNotEmpty) ...[
        const SizedBox(height: 10),
        ReorderableListView.builder(
          key: const ValueKey('gozar-reorder-shortcuts'),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: shortcuts.length,
          onReorder: (oldIndex, newIndex) => _saveShortcuts(
            GozarShortcutStore.reordered(shortcuts, oldIndex, newIndex)),
          itemBuilder: (context, index) {
            final shortcut = shortcuts[index];
            return ListTile(
              key: ValueKey('gozar-manage-shortcut-' + shortcut.key),
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: GozarShortcutIcon(shortcut: shortcut, size: 34),
              title: Text(shortcut.title, maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              subtitle: Text(shortcut.kind == 'web'
                  ? 'سایت' : 'برنامه اندروید',
                  style: const TextStyle(
                    color: GozarPalette.muted, fontSize: 10)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  key: ValueKey('gozar-rename-' + shortcut.key),
                  tooltip: 'ویرایش نام میانبر',
                  onPressed: () => _renameShortcut(shortcut),
                  icon: const Icon(Icons.edit_outlined,
                    color: GozarPalette.cyan, size: 19)),
                IconButton(
                  tooltip: 'حذف میانبر',
                  onPressed: () => _saveShortcuts([
                    for (final item in shortcuts)
                      if (item.key != shortcut.key) item,
                  ]),
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: GozarPalette.red, size: 19)),
                ReorderableDragStartListener(
                  index: index,
                  child: const SizedBox(width: 38, height: 48,
                    child: Center(child: Icon(Icons.drag_handle_rounded,
                        color: GozarPalette.muted, size: 23))),
                ),
              ]),
            );
          },
        ),
      ],
      const SizedBox(height: 9),
      const Text(
        'سایت‌ها داخل مرورگر گذر باز می‌شوند؛ برنامه‌های نصب‌شده '
        'در محیط خودشان اجرا می‌شوند. به‌دلیل مستثنا بودن خود گذر از '
        'تونل VPN، ترافیک مرورگر داخلی لزوماً از VPN عبور نمی‌کند.',
        style: TextStyle(color: GozarPalette.muted, fontSize: 10),
      ),
    ]),
  );

  Widget _hero() {
    final connected = stage == 'running';
    final canStop = busy || connected || stage == 'starting' ||
        stage == 'consent' || stage == 'stopping';
    return GozarPanel(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
      glow: connected ? GozarPalette.green : GozarPalette.blue,
      child: Column(children: [
        // Both columns use the SAME 154dp dial at the SAME top edge.
        // On narrower devices they are scaled down by an equal factor.
        SizedBox(height: 198, child: Row(children: [
          Expanded(child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topCenter,
            child: const SizedBox(
              width: 154, height: 196,
              child: GozarLiveClock(),
            ),
          )),
          const SizedBox(width: 3),
          Expanded(child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topCenter,
            child: SizedBox(width: 154, height: 196,
              child: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: 154, height: 154,
                  child: GozarPowerButton(
                    key: const ValueKey('gozar-power'),
                    connected: connected,
                    busy: busy || disconnecting || stage == 'starting' ||
                        stage == 'consent' || stage == 'stopping',
                    label: canStop
                        ? 'برای قطع اتصال لمس کنید'
                        : 'برای اتصال لمس کنید',
                    onPressed: disconnecting ? null
                        : canStop ? disconnect : connect,
                  ),
                ),
              ),
            ),
          )),
        ])),
        const SizedBox(height: 4),
        Text(detail, key: const ValueKey('gozar-vpn-status'),
          textAlign: TextAlign.center,
          style: TextStyle(color: connected
              ? GozarPalette.cyan : GozarPalette.muted, fontSize: 11)),
        if (connected) ...[
          const SizedBox(height: 6),
          OutlinedButton.icon(
            key: const ValueKey('gozar-test-real-connection'),
            onPressed: testingProxy ? null : testProxyConnection,
            icon: testingProxy
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.public_rounded, size: 18),
            label: Text(testingProxy ? 'آزمایش اینترنت سرور…'
                : 'آزمایش اینترنت از مسیر سرور',
                style: const TextStyle(fontSize: 11)),
          ),
          if (proxyVerified != null)
            Text(proxyVerified!
                ? 'آزمون اتصال سرور موفق: ' +
                    proxyLatencyMs.toString() + ' ms'
                : 'آزمون اتصال موفق نبود؛ سرور یا مقصد آزمایش '
                    'ممکن است در دسترس نباشد.',
                key: const ValueKey('gozar-real-connection-result'),
                textAlign: TextAlign.center,
                style: TextStyle(color: proxyVerified!
                    ? GozarPalette.green : GozarPalette.red, fontSize: 11)),
        ],
        const SizedBox(height: 5),
        Row(children: [
          const Icon(Icons.dns_rounded, size: 15,
              color: GozarPalette.cyan),
          const SizedBox(width: 5),
          Expanded(child: Text(serverLabel,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: GozarPalette.text, fontSize: 11))),
          TextButton(
            onPressed: () => setState(() {
              visitedPages.add(2);
              currentPage = 2;
            }),
            child: const Text('تغییر سرور', style: TextStyle(
              color: GozarPalette.cyan, fontSize: 11)),
          ),
        ]),
      ]),
    );
  }

  Widget _connectActions() => Row(children: [
    Expanded(child: FilledButton.icon(
      key: const ValueKey('gozar-connect'),
      onPressed: busy || disconnecting || stage == 'running' ||
          stage == 'starting' || stage == 'consent' ||
          stage == 'stopping' ? null : connect,
      style: FilledButton.styleFrom(
        backgroundColor: GozarPalette.blue,
        foregroundColor: GozarPalette.text,
        padding: const EdgeInsets.symmetric(vertical: 13),
      ),
      icon: const Icon(Icons.power_settings_new_rounded),
      label: const Text('اتصال VPN'),
    )),
    const SizedBox(width: 9),
    Expanded(child: OutlinedButton.icon(
      key: const ValueKey('gozar-disconnect'),
      onPressed: disconnecting || (stage == 'off' && !busy)
          ? null : disconnect,
      style: OutlinedButton.styleFrom(
        foregroundColor: GozarPalette.text,
        side: const BorderSide(color: GozarPalette.red),
        padding: const EdgeInsets.symmetric(vertical: 13),
      ),
      icon: const Icon(Icons.stop_circle_outlined),
      label: const Text('قطع اتصال'),
    )),
  ]);

  Widget _profileInput() => GozarPanel(
    glow: GozarPalette.purple,
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _eyebrow(Icons.link_rounded, 'کانفیگ سرور',
            color: GozarPalette.purple),
        const SizedBox(height: 7),
        const Text('VMess / VLESS / Trojan / Xray JSON',
          textDirection: TextDirection.ltr,
          style: TextStyle(color: GozarPalette.muted, fontSize: 11)),
        const SizedBox(height: 11),
        TextField(
          key: const ValueKey('gozar-config'),
          controller: profile,
          obscureText: hideProfile,
          maxLines: hideProfile ? 1 : 3,
          autocorrect: false,
          enableSuggestions: false,
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.left,
          style: const TextStyle(color: GozarPalette.text),
          decoration: InputDecoration(
            hintText: 'vmess:// …',
            hintStyle: const TextStyle(color: GozarPalette.muted),
            fillColor: const Color(0xff07132b).withOpacity(.80),
            filled: true,
            suffixIcon: IconButton(
              tooltip: hideProfile ? 'نمایش کانفیگ' : 'پنهان کردن کانفیگ',
              onPressed: () => setState(() { hideProfile = !hideProfile; }),
              icon: Icon(hideProfile
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined),
            ),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: busy ? null : () =>
              unawaited(saveProfile().catchError((Object _) {})),
          icon: const Icon(Icons.save_outlined),
          label: Text(selectedProfile < 0
              ? 'ذخیره سرور جدید' : 'ذخیره تغییرات سرور'),
          style: OutlinedButton.styleFrom(
            foregroundColor: GozarPalette.cyan,
            side: const BorderSide(color: Color(0xff2b7795)),
          ),
        ),
        const SizedBox(height: 6),
        _connectActions(),
      ],
    ),
  );

  Widget _home() => ListView(
    key: const ValueKey('gozar-home'),
    padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
    children: [
      _hero(),
      const SizedBox(height: 12),
      _shortcutPanel(),
    ],
  );

  Widget _serverCard(int index) {
    final item = profiles[index];
    final selected = selectedProfile == index;
    final latency = tcpLatencies[item.link];
    final testing = checkingTcpProfiles.contains(item.link);
    return GozarPanel(
      glow: selected ? GozarPalette.cyan : GozarPalette.purple,
      child: Column(children: [
        Row(children: [
          Icon(selected ? Icons.check_circle_rounded
              : Icons.dns_rounded,
              color: selected ? GozarPalette.cyan : GozarPalette.purple),
          const SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.name, style: const TextStyle(
                  color: GozarPalette.text,
                  fontSize: 15, fontWeight: FontWeight.w800)),
              const Text('کانفیگ ذخیره‌شده • آدرس پنهان',
                style: TextStyle(color: GozarPalette.muted, fontSize: 11)),
            ],
          )),
          TextButton(
            key: ValueKey('gozar-test-server-' + index.toString()),
            onPressed: testing ? null : () => checkTcpLatency(index),
            child: Text(testing ? '…' : 'تست'),
          ),
          if (latency != null)
            Text(latency.toString() + ' ms',
              key: ValueKey('gozar-tcp-' + index.toString()),
              textDirection: TextDirection.ltr,
              style: const TextStyle(
                color: GozarPalette.cyan,
                fontWeight: FontWeight.w800,
              )),
          if (selected) const Padding(
            padding: EdgeInsets.only(right: 7),
            child: Icon(Icons.verified_outlined,
              color: GozarPalette.cyan, size: 20),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: FilledButton(
            onPressed: () => selectProfile(index),
            child: Text(selected ? 'ویرایش / مشاهده' : 'انتخاب این سرور'),
          )),
          IconButton(
            tooltip: 'ویرایش نام',
            onPressed: () => unawaited(renameProfile(index)),
            icon: const Icon(Icons.edit_outlined,
                color: GozarPalette.muted),
          ),
          IconButton(
            tooltip: 'حذف سرور',
            onPressed: stage == 'running'
                ? null : () => unawaited(deleteProfile(index)),
            icon: const Icon(Icons.delete_outline_rounded,
                color: GozarPalette.purple),
          ),
        ]),
      ]),
    );
  }

  Widget _servers() => ListView(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
    children: [
      GozarPanel(child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _eyebrow(Icons.dns_outlined, 'سرورهای من'),
          const SizedBox(height: 8),
          const Text('سرورها و لینک‌ها فقط از خودتان دریافت می‌شوند؛ '
            'فهرست یا موقعیت جغرافیایی ساختگی نمایش داده نمی‌شود.',
            style: TextStyle(color: GozarPalette.muted, fontSize: 12)),
          const SizedBox(height: 13),
          FilledButton.icon(
            key: const ValueKey('gozar-add-profile'),
            onPressed: addProfile,
            icon: const Icon(Icons.add_rounded),
            label: const Text('افزودن سرور جدید'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('gozar-import-subscription'),
            onPressed: busy || importingSubscription
                ? null : importSubscription,
            icon: importingSubscription
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.cloud_download_outlined),
            label: const Text('افزودن لینک اشتراک'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('gozar-best-server'),
            onPressed: busy || choosingBestServer || profiles.isEmpty
                ? null : chooseBestServer,
            icon: choosingBestServer
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.speed_rounded),
            label: const Text('انتخاب سرور با کمترین تأخیر TCP'),
          ),
        ],
      )),
      const SizedBox(height: 13),
      _profileInput(),
      const SizedBox(height: 13),
      if (profiles.isEmpty)
        const GozarPanel(child: Text('هنوز سروری ذخیره نکرده‌اید. '
            'سرور جدید را اضافه کنید و لینک اختصاصی خود را وارد کنید.',
            style: TextStyle(color: GozarPalette.muted)))
      else ...[
        for (var i = 0; i < profiles.length; i++) ...[
          _serverCard(i),
          const SizedBox(height: 10),
        ],
      ],
    ],
  );

  Widget _security() => ListView(
    key: const ValueKey('gozar-settings-page'),
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
    children: [
      _shortcutSettings(),
      const SizedBox(height: 13),
      GozarPanel(child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _eyebrow(Icons.settings_rounded, 'تنظیمات گذر'),
          const SizedBox(height: 8),
          const Text('انتخاب برنامه‌های VPN، امنیت و کنترل وضعیت اتصال',
            style: TextStyle(color: GozarPalette.muted, fontSize: 12)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const ValueKey('gozar-choose-apps'),
            onPressed: busy ? null : chooseApps,
            icon: const Icon(Icons.apps_rounded),
            label: Text(mode == 'all' ? 'برنامه‌ها: همه'
                : 'برنامه‌ها: ' + packages.length.toString() + ' انتخاب‌شده'),
          ),
          const SizedBox(height: 8),
          const Text('در صورت تغییر برنامه‌ها، VPN را قطع و دوباره وصل کنید.',
              style: TextStyle(color: GozarPalette.muted, fontSize: 11)),
          const SizedBox(height: 6),
          const Text('برنامه‌های بانکی، روبیکا و بله در حالت «همه» '
              'به‌طور خودکار از اینترنت مستقیم استفاده می‌کنند.',
              style: TextStyle(color: GozarPalette.cyan, fontSize: 11)),
          TextButton.icon(
            onPressed: refresh,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('بررسی وضعیت VPN'),
          ),
        ],
      )),
      const SizedBox(height: 13),
      GozarPanel(glow: GozarPalette.purple,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _eyebrow(Icons.shield_rounded, 'امنیت اتصال',
                color: GozarPalette.purple),
            const SizedBox(height: 11),
            const Text('Kill Switch از طریق تنظیمات رسمی اندروید',
              style: TextStyle(color: GozarPalette.text,
                  fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('در تنظیمات VPN اندروید، گذر را انتخاب کنید '
              'و در صورت وجود گزینه‌ها، «VPN همیشه روشن» و '
              '«مسدودکردن اتصال‌های بدون VPN» را فعال کنید. '
              'این گزینه‌ها تحت کنترل خود اندروید هستند.',
              style: TextStyle(color: GozarPalette.muted, fontSize: 12)),
            const SizedBox(height: 13),
            FilledButton.icon(
              key: const ValueKey('gozar-vpn-settings'),
              onPressed: () async {
                try {
                  await SystemVpnBridge.openVpnSettings();
                } catch (_) {
                  notice('تنظیمات VPN اندروید باز نشد؛ '
                    'آن را از تنظیمات گوشی باز کنید.');
                }
              },
              icon: const Icon(Icons.settings_outlined),
              label: const Text('بازکردن تنظیمات VPN اندروید'),
            ),
          ],
        )),
      const SizedBox(height: 12),
      GozarPanel(child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _eyebrow(Icons.privacy_tip_outlined, 'حریم خصوصی'),
          const SizedBox(height: 10),
          const Text('گذر تاریخچه وب‌گردی را در رابط خود ذخیره نمی‌کند. '
              'کانفیگ‌های شما در فضای امن گوشی نگهداری می‌شوند. '
              'سیاست نگهداری داده توسط ارائه‌دهنده سرور، مستقل از این '
              'برنامه است و قابل تضمین از طرف گذر نیست.',
              style: TextStyle(color: GozarPalette.muted, fontSize: 12)),
          const SizedBox(height: 10),
          const Text('وضعیت «تونل فعال» به‌معنی تایید سرعت یا '
              'امنیت سرور نیست؛ برای اطمینان، اتصال واقعی اینترنت '
              'برنامه‌های انتخاب‌شده را آزمایش کنید.',
              style: TextStyle(color: GozarPalette.muted, fontSize: 12)),
        ],
      )),
    ],
  );

  @override
  Widget build(BuildContext context) {
    Widget tab(int index) {
      if (!visitedPages.contains(index)) return const SizedBox.shrink();
      switch (index) {
        case 0: return _home();
        case 1: return launcherPage;
        case 2: return _servers();
        default: return _security();
      }
    }
    return Scaffold(
      backgroundColor: GozarPalette.base,
      body: Stack(children: [
        const AuroraBackdrop(),
        SafeArea(child: Column(children: [
          if (currentPage != 1) Padding(
            padding: const EdgeInsets.fromLTRB(18, 7, 18, 8),
            child: Row(children: [
              const Icon(Icons.shield_outlined,
                color: GozarPalette.cyan, size: 27),
              const SizedBox(width: 7),
              const Text('گذر', style: TextStyle(
                color: GozarPalette.text,
                fontSize: 22, fontWeight: FontWeight.w800)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: (stage == 'running'
                    ? GozarPalette.cyan : GozarPalette.purple)
                      .withOpacity(.13),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: (stage == 'running'
                    ? GozarPalette.cyan : GozarPalette.purple)
                      .withOpacity(.34)),
                ),
                child: Text(stage == 'running' ? '●  تونل فعال'
                    : stage == 'starting' || stage == 'consent'
                        ? '●  در حال اتصال'
                        : stage == 'stopping' ? '●  در حال قطع'
                        : '●  خاموش',
                    style: TextStyle(fontSize: 11,
                        color: stage == 'running'
                            ? GozarPalette.cyan : GozarPalette.muted)),
              ),
              IconButton(
                tooltip: 'به‌روزرسانی وضعیت',
                onPressed: refresh,
                icon: const Icon(Icons.refresh_rounded,
                    color: GozarPalette.muted, size: 20),
              ),
            ]),
          ),
          Expanded(child: IndexedStack(
            index: currentPage,
            children: [for (var index = 0; index < 4; index++) tab(index)],
          )),
          NavigationBar(
            height: 68,
            backgroundColor: const Color(0xff08172e),
            indicatorColor: const Color(0xff154264),
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            selectedIndex: currentPage,
            onDestinationSelected: (index) {
              setState(() {
                visitedPages.add(index);
                currentPage = index;
              });
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded,
                    color: GozarPalette.cyan),
                label: 'خانه'),
              NavigationDestination(
                icon: Icon(Icons.grid_view_outlined),
                selectedIcon: Icon(Icons.grid_view_rounded,
                    color: GozarPalette.cyan),
                label: 'لانچر'),
              NavigationDestination(
                icon: Icon(Icons.dns_outlined),
                selectedIcon: Icon(Icons.dns_rounded,
                    color: GozarPalette.cyan),
                label: 'سرورها'),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings_rounded,
                    color: GozarPalette.cyan),
                label: 'تنظیمات'),
            ],
          ),
        ])),
      ]),
    );
  }
}
