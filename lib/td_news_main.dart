import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamsi_date/shamsi_date.dart';
import 'package:url_launcher/url_launcher.dart';

import 'td_news_engine.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  runApp(TdNewsApp(preferences: preferences));
}

class TdNewsApp extends StatefulWidget {
  final SharedPreferences preferences;
  const TdNewsApp({super.key, required this.preferences});
  @override
  State<TdNewsApp> createState() => _TdNewsAppState();
}

class _TdNewsAppState extends State<TdNewsApp> {
  late final TdNewsController news = TdNewsController(widget.preferences);
  bool dark = false;

  @override
  void initState() {
    super.initState();
    dark = widget.preferences.getBool('dark') ?? false;
    unawaited(restoreSession());
  }

  Future<void> restoreSession() async {
    const vault = FlutterSecureStorage();
    try {
      final id = int.tryParse(await vault.read(key: 'td_api_id') ?? '');
      final hash = await vault.read(key: 'td_api_hash');
      if (id == null || id <= 0 || hash == null || hash.isEmpty) return;
      final dir = await getApplicationSupportDirectory();
      await news.start(id, hash, dir.path);
    } catch (_) { /* Device can still show the manual login form. */ }
  }

  @override
  void dispose() {
    news.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'نبض خبر',
        locale: const Locale('fa'),
        supportedLocales: const [Locale('fa')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: const Color(0xff3768be),
          fontFamily: 'CustomFont',
          scaffoldBackgroundColor: const Color(0xfff6f8fc),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: const Color(0xff7aa8ff),
          brightness: Brightness.dark,
          fontFamily: 'CustomFont',
        ),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: TdHome(
            news: news,
            onToggleTheme: () {
              setState(() { dark = !dark; });
              widget.preferences.setBool('dark', dark);
            },
            dark: dark,
          ),
        ),
      );
}

class TdHome extends StatefulWidget {
  final TdNewsController news;
  final VoidCallback onToggleTheme;
  final bool dark;
  const TdHome({
    super.key, required this.news, required this.onToggleTheme, required this.dark,
  });
  @override
  State<TdHome> createState() => _TdHomeState();
}

class _TdHomeState extends State<TdHome> {
  final apiId = TextEditingController();
  final apiHash = TextEditingController();
  final login = TextEditingController();
  final channel = TextEditingController();
  final search = TextEditingController();
  String filter = '';
  bool submitting = false;

  @override
  void dispose() {
    apiId.dispose();
    apiHash.dispose();
    login.dispose();
    channel.dispose();
    search.dispose();
    super.dispose();
  }

  void message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> connect() async {
    final id = int.tryParse(apiId.text.trim());
    final hash = apiHash.text.trim();
    if (id == null || id <= 0 || !RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(hash)) {
      message('API ID عددی و API Hash سی‌ودوکاراکتری را وارد کنید.');
      return;
    }
    setState(() { submitting = true; });
    try {
      const vault = FlutterSecureStorage();
      await vault.write(key: 'td_api_id', value: id.toString());
      await vault.write(key: 'td_api_hash', value: hash);
      apiHash.clear();
      final dir = await getApplicationSupportDirectory();
      await widget.news.start(id, hash, dir.path);
    } catch (_) {
      message('تنظیمات ذخیره نشد؛ دوباره تلاش کنید.');
    } finally {
      if (mounted) setState(() { submitting = false; });
    }
  }

  Future<void> loginStep() async {
    if (login.text.trim().isEmpty) return;
    setState(() { submitting = true; });
    try {
      await widget.news.submitLogin(login.text);
      login.clear();
    } catch (_) {
      message('درخواست ورود انجام نشد.');
    } finally {
      if (mounted) setState(() { submitting = false; });
    }
  }

  Future<void> addChannel() async {
    if (channel.text.trim().isEmpty) return;
    setState(() { submitting = true; });
    try {
      await widget.news.addChannel(channel.text);
      channel.clear();
      message('کانال به منابع خبری اضافه شد.');
    } catch (error) {
      message(error.toString().replaceFirst('Bad state: ', '').replaceFirst('FormatException: ', ''));
    } finally {
      if (mounted) setState(() { submitting = false; });
    }
  }

  String dateLabel(int epoch) {
    final d = DateTime.fromMillisecondsSinceEpoch(epoch * 1000);
    final j = Jalali.fromDateTime(d).formatter;
    return ' ' + j.yyyy.toString() + '/' + j.mm + '/' + j.dd +
        ' • ' + d.hour.toString().padLeft(2, '0') + ':' + d.minute.toString().padLeft(2, '0');
  }

  Widget sectionTitle(String title, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          Expanded(child: Text(title,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold))),
          if (trailing != null) trailing,
        ]),
      );

  Widget setup() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        sectionTitle('اتصال امن به تلگرام'),
        const Text('API ID و API Hash اختصاصی برنامه را از my.telegram.org/apps بگیرید. '
            'این اطلاعات فقط در حافظه امن همین گوشی ذخیره می‌شوند.'),
        const SizedBox(height: 14),
        TextField(
          controller: apiId, keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'API ID', border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: apiHash, autocorrect: false, obscureText: true,
          decoration: const InputDecoration(
            labelText: 'API Hash', border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: submitting ? null : connect,
          icon: const Icon(Icons.lock_open), label: const Text('شروع اتصال'),
        ),
        TextButton(
          onPressed: () => launchUrl(Uri.parse('https://my.telegram.org/apps'),
              mode: LaunchMode.externalApplication),
          child: const Text('دریافت شناسه برنامه از تلگرام'),
        ),
      ]);

  Widget authorization() {
    final current = widget.news.state;
    final isInput = [
      'authorizationStateWaitPhoneNumber',
      'authorizationStateWaitCode',
      'authorizationStateWaitPassword',
      'authorizationStateWaitEmailAddress',
      'authorizationStateWaitEmailCode',
    ].contains(current);
    String title = 'اطلاعات ورود';
    if (current == 'authorizationStateWaitPhoneNumber') title = 'شماره همراه با پیش‌شماره کشور';
    if (current == 'authorizationStateWaitCode') title = 'کد ورود تلگرام';
    if (current == 'authorizationStateWaitPassword') title = 'گذرواژه دومرحله‌ای';
    if (current == 'authorizationStateWaitEmailAddress') title = 'ایمیل حساب';
    if (current == 'authorizationStateWaitEmailCode') title = 'کد تأیید ایمیل';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      sectionTitle('ورود به حساب تلگرام'),
      Text(widget.news.status),
      const SizedBox(height: 14),
      if (current == 'failed') ...[
        const Text('در صورت خطا برنامه را ببندید و دوباره باز کنید.'),
      ] else if (isInput) ...[
        TextField(
          key: ValueKey(current), controller: login,
          obscureText: current == 'authorizationStateWaitPassword' ||
              current == 'authorizationStateWaitCode' ||
              current == 'authorizationStateWaitEmailCode',
          keyboardType: current == 'authorizationStateWaitPhoneNumber'
              ? TextInputType.phone : TextInputType.text,
          decoration: InputDecoration(labelText: title, border: const OutlineInputBorder()),
          onSubmitted: (_) => loginStep(),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: submitting || widget.news.busy ? null : loginStep,
          child: const Text('تأیید و ادامه'),
        ),
      ] else ...[
        const Center(child: Padding(
          padding: EdgeInsets.all(22), child: CircularProgressIndicator(),
        )),
      ],
      const SizedBox(height: 14),
      const Text('شماره، کد ورود و رمز دومرحله‌ای به گیت‌هاب یا Cloudflare ارسال نمی‌شوند.'),
    ]);
  }

  Widget channelPicker() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        sectionTitle('منابع خبری انتخابی', trailing: IconButton(
          tooltip: 'تازه‌سازی خبرها',
          onPressed: widget.news.busy ? null : () => widget.news.refresh(),
          icon: const Icon(Icons.refresh),
        )),
        const Text('با افزودن هر کانال، حساب شما عضو آن می‌شود تا پست‌های جدید را دریافت کند.'),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextField(
            controller: channel, textDirection: TextDirection.ltr,
            decoration: const InputDecoration(
              hintText: 't.me/channelname', border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => addChannel(),
          )),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: submitting || widget.news.busy ? null : addChannel,
            child: const Text('افزودن و عضویت'),
          ),
        ]),
        if (widget.news.sources.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 6, children: [
            for (final source in widget.news.sources.values)
              InputChip(
                label: Text(source.title),
                onDeleted: () => widget.news.removeChannel(source.id),
                deleteIcon: const Icon(Icons.close, size: 17),
                tooltip: 'حذف از فهرست برنامه (بدون خروج از کانال تلگرام)',
              ),
          ]),
        ],
      ]);

  Widget postCard(NewsPost p) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showModalBottomSheet<void>(
            context: context, isScrollControlled: true,
            showDragHandle: true,
            builder: (context) => SafeArea(child: Padding(
              padding: const EdgeInsets.all(22),
              child: SingleChildScrollView(child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(p.source, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  Text(p.body, style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => launchUrl(Uri.parse(p.link),
                        mode: LaunchMode.externalApplication),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('باز کردن پست در تلگرام'),
                  ),
                ],
              )),
            )),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (p.photoPath != null)
              Image.file(
                File(p.photoPath!), height: 180, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            Padding(padding: const EdgeInsets.all(14), child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(p.source + ' • ' + dateLabel(p.date),
                    style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: 6),
                Text(
                  p.body.split('\n').first,
                  style: const TextStyle(fontFamily: 'Rooznameh',
                      fontSize: 19, fontWeight: FontWeight.bold),
                ),
                if (p.body.contains('\n')) ...[
                  const SizedBox(height: 6),
                  Text(p.body, maxLines: 4, overflow: TextOverflow.ellipsis),
                ],
              ],
            )),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.news,
        builder: (context, _) {
          final ready = widget.news.state == 'authorizationStateReady';
          final filtered = widget.news.feed.where((p) =>
              (p.source + ' ' + p.body).toLowerCase().contains(filter.toLowerCase())).toList();
          return Scaffold(
            appBar: AppBar(
              title: const Text('نبض خبر', style: TextStyle(fontFamily: 'Rooznameh')),
              actions: [
                IconButton(
                  icon: Icon(widget.dark ? Icons.light_mode : Icons.dark_mode),
                  tooltip: 'تغییر حالت شب و روز', onPressed: widget.onToggleTheme,
                ),
              ],
            ),
            body: SafeArea(child: Center(child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(padding: const EdgeInsets.all(16), children: [
                if (widget.news.state == 'setup') setup()
                else if (!ready) authorization()
                else ...[
                  channelPicker(),
                  const SizedBox(height: 10),
                  sectionTitle('آخرین خبرها'),
                  TextField(
                    controller: search,
                    onChanged: (v) => setState(() { filter = v; }),
                    decoration: const InputDecoration(
                      hintText: 'جست‌وجو در خبرهای دریافت‌شده',
                      prefixIcon: Icon(Icons.search), border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (widget.news.sources.isEmpty)
                    const Text('برای شروع، آدرس اولین کانال عمومی را اضافه کنید.')
                  else if (filtered.isEmpty)
                    const Text('هنوز خبری دریافت نشده است. گزینه تازه‌سازی را بزنید.')
                  else
                    for (final post in filtered) postCard(post),
                ],
                const SizedBox(height: 16),
                Text(widget.news.status, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 20),
              ]),
            ))),
          );
        },
      );
}
