import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:iconsax/iconsax.dart';
import 'package:shimmer/shimmer.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'models.dart';
import 'state.dart';
import 'notifications.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(ProviderScope(
      overrides: [prefsProvider.overrideWithValue(prefs)],
      child: const NewsApp()));
}

final navigatorKey = GlobalKey<NavigatorState>();
const brand = Color(0xff667eea);

class NewsApp extends ConsumerStatefulWidget {
  const NewsApp({super.key});
  @override
  ConsumerState<NewsApp> createState() => _NewsAppState();
}

class _NewsAppState extends ConsumerState<NewsApp> {
  PushService? push;
  @override
  void initState() {
    super.initState();
    if (firebaseEnabled)
      WidgetsBinding.instance.addPostFrameCallback((_) => connectPush());
  }

  Future<void> connectPush() async {
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(backgroundMessage);
      if (!mounted) return;
      push = PushService((id) {
        navigatorKey.currentState?.push(
            MaterialPageRoute<void>(builder: (_) => DetailScreen(id: id)));
      }, (status) {
        if (mounted) ref.read(pushStatusProvider.notifier).state = status;
      });
      await push!.start();
    } catch (_) {
      if (mounted)
        ref.read(pushStatusProvider.notifier).state =
            'اتصال اعلان برقرار نشد؛ تنظیمات Firebase و اینترنت را بررسی کنید';
    }
  }

  @override
  void dispose() {
    push?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = ref.watch(darkProvider);
    ThemeData theme(Brightness brightness) => ThemeData(
          useMaterial3: true,
          fontFamily: 'CustomFont',
          brightness: brightness,
          colorScheme:
              ColorScheme.fromSeed(seedColor: brand, brightness: brightness),
          scaffoldBackgroundColor: brightness == Brightness.light
              ? const Color(0xfff5f6fb)
              : const Color(0xff111420),
          inputDecorationTheme: InputDecorationTheme(
              filled: true,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none)),
        );
    return MaterialApp(
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        title: appTitle,
        locale: const Locale('fa'),
        supportedLocales: const [Locale('fa')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: theme(Brightness.light),
        darkTheme: theme(Brightness.dark),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        themeAnimationDuration: const Duration(milliseconds: 250),
        home: const HomeScreen());
  }
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  final scroll = ScrollController();
  Timer? debounce, polling;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() => ref.read(feedProvider.notifier).refresh());
    scroll.addListener(() {
      if (scroll.position.extentAfter < 400 &&
          ref.read(feedProvider).error == null)
        ref.read(feedProvider.notifier).more();
    });
    startPolling();
  }

  void startPolling() {
    polling?.cancel();
    if (apiBase.isNotEmpty)
      polling = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted && ref.read(feedProvider).query.isEmpty)
          ref.read(feedProvider.notifier).refresh(silent: true);
      });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      startPolling();
      ref.read(feedProvider.notifier).refresh(silent: true);
    } else {
      polling?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    polling?.cancel();
    debounce?.cancel();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(feedProvider);
    return Scaffold(
        body: SafeArea(
            child: Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: RefreshIndicator(
                      onRefresh: () =>
                          ref.read(feedProvider.notifier).refresh(),
                      child: CustomScrollView(
                          controller: scroll,
                          physics: const AlwaysScrollableScrollPhysics(),
                          slivers: [
                            SliverToBoxAdapter(
                                child: Padding(
                                    padding: const EdgeInsets.all(18),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          const Header(),
                                          const SizedBox(height: 24),
                                          Row(children: [
                                            Text('آخرین خبرها',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .headlineSmall
                                                    ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.bold)),
                                            const Spacer(),
                                            Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 6),
                                                decoration: BoxDecoration(
                                                    color:
                                                        brand.withOpacity(.12),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            20)),
                                                child: Text(
                                                    apiBase.isEmpty
                                                        ? 'پیش‌نمایش'
                                                        : 'هر ۳۰ ثانیه',
                                                    style: const TextStyle(
                                                        color: brand,
                                                        fontSize: 12)))
                                          ]),
                                          const SizedBox(height: 14),
                                          TextField(
                                              onChanged: (value) {
                                                debounce?.cancel();
                                                debounce = Timer(
                                                    const Duration(
                                                        milliseconds: 400),
                                                    () => ref
                                                        .read(feedProvider
                                                            .notifier)
                                                        .refresh(
                                                            query:
                                                                value.trim()));
                                              },
                                              decoration: const InputDecoration(
                                                  hintText:
                                                      'جست‌وجو میان خبرها…',
                                                  prefixIcon: Icon(
                                                      Iconsax.search_normal))),
                                          if (apiBase.isEmpty)
                                            const Padding(
                                                padding:
                                                    EdgeInsets.only(top: 12),
                                                child: Text(
                                                    'حالت نمایشی • کانال هنوز متصل نشده است',
                                                    style: TextStyle(
                                                        color: brand,
                                                        fontSize: 12))),
                                          if (feed.error != null)
                                            Padding(
                                                padding: const EdgeInsets.only(
                                                    top: 12),
                                                child: MaterialBanner(
                                                    content: Text(feed.error!),
                                                    actions: [
                                                      TextButton(
                                                          onPressed: () => ref
                                                              .read(feedProvider
                                                                  .notifier)
                                                              .refresh(),
                                                          child: const Text(
                                                              'تلاش دوباره'))
                                                    ])),
                                        ]))),
                            if (feed.loading && feed.posts.isEmpty)
                              SliverList(
                                  delegate: SliverChildBuilderDelegate(
                                      (_, i) => const LoadingCard(),
                                      childCount: 3))
                            else if (feed.posts.isEmpty && !feed.loading)
                              SliverToBoxAdapter(
                                  child: Padding(
                                      padding: const EdgeInsets.all(40),
                                      child: Column(children: [
                                        const Icon(Iconsax.document,
                                            size: 56, color: brand),
                                        const SizedBox(height: 16),
                                        Text(feed.query.isEmpty
                                            ? 'هنوز خبری منتشر نشده است'
                                            : 'خبری پیدا نشد'),
                                        if (feed.cursor != null)
                                          TextButton(
                                              onPressed: () => ref
                                                  .read(feedProvider.notifier)
                                                  .more(),
                                              child: const Text(
                                                  'جست‌وجو در خبرهای قدیمی‌تر'))
                                      ])))
                            else
                              SliverList(
                                  delegate: SliverChildBuilderDelegate(
                                      (_, i) => NewsCard(post: feed.posts[i]),
                                      childCount: feed.posts.length)),
                            SliverToBoxAdapter(
                                child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        24, 8, 24, 32),
                                    child: Center(
                                        child: feed.loading &&
                                                feed.posts.isNotEmpty
                                            ? const CircularProgressIndicator()
                                            : feed.cursor != null
                                                ? TextButton(
                                                    onPressed: () => ref
                                                        .read(feedProvider
                                                            .notifier)
                                                        .more(),
                                                    child: const Text(
                                                        'خبرهای بیشتر'))
                                                : Text('همراه شما، خبر به خبر',
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodySmall)))),
                          ]),
                    )))));
  }
}

class Header extends ConsumerWidget {
  const Header({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
      decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [brand, Color(0xff764ba2)]),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
                color: brand.withOpacity(.22),
                blurRadius: 22,
                offset: const Offset(0, 10))
          ]),
      padding: const EdgeInsets.all(18),
      child: DefaultTextStyle(
          style: const TextStyle(fontFamily: 'CustomFont', color: Colors.white),
          child: Column(children: [
            StreamBuilder<DateTime>(
                stream: Stream<DateTime>.periodic(
                    const Duration(seconds: 1), (_) => DateTime.now()),
                initialData: DateTime.now(),
                builder: (_, snapshot) {
                  final now = snapshot.data!;
                  return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                            child: Text(persianDate(now, weekday: true),
                                style: const TextStyle(fontSize: 11))),
                        const SizedBox(width: 8),
                        Text(
                            fa('${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}'),
                            textDirection: TextDirection.ltr,
                            style: const TextStyle(fontSize: 15))
                      ]);
                }),
            const SizedBox(height: 18),
            Row(children: [
              IconButton(
                  tooltip: 'حالت شب و روز',
                  onPressed: () async {
                    final value = !ref.read(darkProvider);
                    ref.read(darkProvider.notifier).state = value;
                    await ref.read(prefsProvider).setBool('dark', value);
                  },
                  icon: Icon(
                      ref.watch(darkProvider) ? Iconsax.sun_1 : Iconsax.moon,
                      color: Colors.white)),
              Expanded(
                  child: Column(children: [
                Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: Colors.white.withOpacity(.18),
                        borderRadius: BorderRadius.circular(18)),
                    child: const Icon(Iconsax.global,
                        color: Colors.white, size: 30)),
                const SizedBox(height: 8),
                Text(appTitle,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold))
              ])),
              IconButton(
                  tooltip: 'تنظیمات',
                  onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                          builder: (_) => const SettingsScreen())),
                  icon: const Icon(Iconsax.setting_2, color: Colors.white))
            ]),
            const SizedBox(height: 10),
            const Text('روایت امروز، همین‌جا',
                style: TextStyle(fontSize: 12, color: Colors.white70)),
          ])));
}

class Cover extends StatelessWidget {
  final Post post;
  final double height;
  const Cover({super.key, required this.post, this.height = 190});
  Widget placeholder() => Container(
      height: height,
      decoration: const BoxDecoration(
          gradient: LinearGradient(
              colors: [Color(0xff667eea), Color(0xff38466a)],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft)),
      child: Center(
          child: Icon(Iconsax.document_text,
              size: 60, color: Colors.white.withOpacity(.65))));
  @override
  Widget build(BuildContext context) => Hero(
      tag: 'cover-${post.id}',
      child: post.image == null
          ? placeholder()
          : Image.network(post.image!,
              height: height,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => placeholder()));
}

class NewsCard extends StatelessWidget {
  final Post post;
  const NewsCard({super.key, required this.post});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 350),
      builder: (_, value, child) => Opacity(
          opacity: value,
          child: Transform.translate(
              offset: Offset(0, 16 * (1 - value)), child: child)),
      child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          child: Material(
              color: Theme.of(context).colorScheme.surface,
              elevation: 2,
              shadowColor: Colors.black12,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                  onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                          builder: (_) =>
                              DetailScreen(id: post.id, initial: post))),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Stack(children: [
                          Cover(post: post),
                          if (post.important)
                            Positioned(
                                top: 12,
                                right: 12,
                                child: Chip(
                                    backgroundColor: Colors.white,
                                    label: const Text('مهم',
                                        style: TextStyle(
                                            color: brand, fontSize: 11)),
                                    avatar: const Icon(Iconsax.flash_1,
                                        size: 15, color: brand)))
                        ]),
                        Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(post.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                              height: 1.7)),
                                  const SizedBox(height: 8),
                                  Text(post.text,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                              height: 1.8,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant)),
                                  const SizedBox(height: 18),
                                  Row(children: [
                                    const Icon(Iconsax.calendar_1,
                                        size: 14, color: brand),
                                    const SizedBox(width: 6),
                                    Expanded(
                                        child: Text(persianDate(post.date),
                                            style:
                                                const TextStyle(fontSize: 11))),
                                    const Icon(Iconsax.eye, size: 14),
                                    const SizedBox(width: 4),
                                    Text(
                                        post.views == null
                                            ? '—'
                                            : fa(post.views!),
                                        style: const TextStyle(fontSize: 11))
                                  ]),
                                ]))
                      ])))));
}

class LoadingCard extends StatelessWidget {
  const LoadingCard({super.key});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      child: Shimmer.fromColors(
          baseColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          highlightColor: Theme.of(context).colorScheme.surface,
          child: Container(
              height: 250,
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16)))));
}

Future<bool> openExternal(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !['https', 'http', 'tg', 'mailto'].contains(uri.scheme))
    return false;
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

class DetailScreen extends ConsumerStatefulWidget {
  final String id;
  final Post? initial;
  const DetailScreen({super.key, required this.id, this.initial});
  @override
  ConsumerState<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends ConsumerState<DetailScreen> {
  late Future<Post> future;
  @override
  void initState() {
    super.initState();
    future = widget.initial != null
        ? Future.value(widget.initial)
        : ref.read(repositoryProvider).post(widget.id);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('متن خبر')),
      body: FutureBuilder<Post>(
          future: future,
          builder: (_, snapshot) {
            if (snapshot.hasError)
              return Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('خبر در دسترس نیست یا اتصال قطع شده است'),
                TextButton(
                    onPressed: () => setState(() {
                          future = ref.read(repositoryProvider).post(widget.id);
                        }),
                    child: const Text('تلاش دوباره'))
              ]));
            if (!snapshot.hasData)
              return const Center(child: CircularProgressIndicator());
            final post = snapshot.data!;
            return Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child:
                        ListView(padding: const EdgeInsets.all(20), children: [
                      ClipRRect(
                          borderRadius: BorderRadius.circular(22),
                          child: Cover(post: post, height: 240)),
                      const SizedBox(height: 24),
                      Text(post.title,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                  fontWeight: FontWeight.bold, height: 1.6)),
                      const SizedBox(height: 12),
                      Text(persianDate(post.date, weekday: true),
                          style: const TextStyle(color: brand)),
                      const SizedBox(height: 24),
                      SelectionArea(
                          child: HtmlWidget(post.html,
                              textStyle: const TextStyle(
                                  fontFamily: 'CustomFont',
                                  fontSize: 16,
                                  height: 2),
                              onTapUrl: openExternal)),
                      const SizedBox(height: 28),
                      Wrap(spacing: 12, runSpacing: 12, children: [
                        FilledButton.icon(
                            onPressed: () => Share.share(
                                '${post.title}\n\n${post.text}\n${post.url}'),
                            icon: const Icon(Iconsax.share),
                            label: const Text('اشتراک‌گذاری')),
                        OutlinedButton.icon(
                            onPressed: post.url.isEmpty
                                ? null
                                : () async {
                                    final ok = await openExternal(post.url);
                                    if (!ok && context.mounted)
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(const SnackBar(
                                              content: Text(
                                                  'باز کردن تلگرام ممکن نشد')));
                                  },
                            icon: const Icon(Iconsax.send_2),
                            label: const Text('باز کردن در تلگرام'))
                      ]),
                    ])));
          }));
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  Future<void> pick(BuildContext context, WidgetRef ref, bool start) async {
    final settings = ref.read(settingsProvider);
    final minute = start ? settings.start : settings.end;
    final result = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: minute ~/ 60, minute: minute % 60));
    if (result != null) {
      final value = result.hour * 60 + result.minute;
      await ref
          .read(settingsProvider.notifier)
          .update(start: start ? value : null, end: start ? null : value);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);
    String time(int n) => fa(
        '${(n ~/ 60).toString().padLeft(2, '0')}:${(n % 60).toString().padLeft(2, '0')}');
    return Scaffold(
        appBar: AppBar(title: const Text('تنظیمات')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          ListTile(
              leading: const Icon(Iconsax.notification, color: brand),
              title: const Text('وضعیت اتصال'),
              subtitle: Text(ref.watch(pushStatusProvider))),
          SwitchListTile(
              title: const Text('دریافت اعلان‌ها'),
              subtitle: const Text('خبرهای جدید کانال'),
              value: s.enabled,
              onChanged: (v) => controller.update(enabled: v)),
          SwitchListTile(
              title: const Text('فقط خبرهای مهم'),
              subtitle: const Text('پست‌های دارای #مهم یا #فوری'),
              value: s.importantOnly,
              onChanged: s.enabled
                  ? (v) => controller.update(importantOnly: v)
                  : null),
          const Divider(height: 32),
          SwitchListTile(
              title: const Text('ساعت‌های بی‌صدا'),
              subtitle: const Text('اعلان نمایش داده می‌شود، بدون صدا و لرزش'),
              value: s.quiet,
              onChanged: s.enabled ? (v) => controller.update(quiet: v) : null),
          ListTile(
              enabled: s.quiet,
              title: const Text('شروع'),
              trailing: Text(time(s.start)),
              onTap: s.quiet ? () => pick(context, ref, true) : null),
          ListTile(
              enabled: s.quiet,
              title: const Text('پایان'),
              trailing: Text(time(s.end)),
              onTap: s.quiet ? () => pick(context, ref, false) : null),
          const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                  'زمان‌ها مطابق ساعت گوشی هستند. شروع و پایان یکسان یعنی بی‌صدا در تمام روز.',
                  style: TextStyle(fontSize: 12))),
          const Divider(height: 32),
          SwitchListTile(
              title: const Text('حالت تاریک'),
              value: ref.watch(darkProvider),
              onChanged: (v) {
                ref.read(darkProvider.notifier).state = v;
                ref.read(prefsProvider).setBool('dark', v);
              }),
          const ListTile(
              title: Text('درباره برنامه'),
              subtitle: Text(
                  'نبض خبر • نسخه ۱.۰\nنمایش خبرهای یک کانال عمومی تلگرام')),
        ]));
  }
}
