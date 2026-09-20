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
import 'td_media_viewer.dart';
import 'td_inline_video.dart';
import 'td_clock_card.dart';
import 'td_downloads.dart';

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
      // Delete credentials belonging to the removed V2Ray feature.
      try { await vault.delete(key: 'td_v2ray_link'); } catch (_) {}
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
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xff255f9a),
            surface: const Color(0xffffffff),
          ),
          fontFamily: 'CustomFont',
          scaffoldBackgroundColor: const Color(0xfff5f7fb),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xfff5f7fb),
            elevation: 0,
            scrolledUnderElevation: 0,
          ),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xff91baff),
            brightness: Brightness.dark,
          ),
          fontFamily: 'CustomFont',
          appBarTheme: const AppBarTheme(elevation: 0, scrolledUnderElevation: 0),
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
  int selectedTab = 0; // 0: news, 1: settings
  bool refreshing = false;
  String? inlineVideoKey;
  final savingPosts = <String>{};
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


  InputDecoration decoratedInput(String hint, {IconData? icon}) => InputDecoration(
        hintText: hint,
        prefixIcon: icon == null ? null : Icon(icon),
        filled: true,
        fillColor: Theme.of(context).colorScheme.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 17, vertical: 17),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(17)),
      );

  Widget surfacePanel({required Widget child, EdgeInsets? padding}) => Material(
        color: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .48),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: padding ?? const EdgeInsets.all(18),
          child: SizedBox(width: double.infinity, child: child),
        ),
      );

  Widget settingsScreen() {
    final colors = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
      children: [
        const SizedBox(height: 8),
        Text('تنظیمات', style: Theme.of(context).textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w800,
        )),
        const SizedBox(height: 6),
        Text('مدیریت منابع خبری و ظاهر برنامه', style: TextStyle(color: colors.onSurfaceVariant)),
        const SizedBox(height: 24),
        sectionTitle('منابع خبری'),
        surfacePanel(child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              CircleAvatar(
                backgroundColor: colors.primaryContainer,
                foregroundColor: colors.onPrimaryContainer,
                child: const Icon(Icons.add_link_rounded),
              ),
              const SizedBox(width: 12),
              const Expanded(child: Text('افزودن کانال عمومی',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
            ]),
            const SizedBox(height: 9),
            Text('با افزودن کانال، حساب تلگرام شما عضو آن می‌شود تا پست‌های جدید دریافت شوند.',
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13)),
            const SizedBox(height: 15),
            TextField(
              controller: channel,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.left,
              textInputAction: TextInputAction.done,
              decoration: decoratedInput('t.me/channelname', icon: Icons.link_rounded),
              onSubmitted: (_) => addChannel(),
            ),
            const SizedBox(height: 11),
            FilledButton.icon(
              onPressed: submitting || widget.news.busy ? null : addChannel,
              icon: const Icon(Icons.add_rounded),
              label: const Text('افزودن و عضویت'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(49),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        )),
        const SizedBox(height: 24),
        sectionTitle('کانال‌های من'),
        if (widget.news.sources.isEmpty)
          surfacePanel(child: const Text('هنوز کانالی اضافه نکرده‌اید.'))
        else
          surfacePanel(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            child: Column(children: [
              for (final source in widget.news.sources.values) ...[
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: colors.primaryContainer,
                    foregroundColor: colors.onPrimaryContainer,
                    child: const Icon(Icons.campaign_outlined),
                  ),
                  title: Text(source.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('@' + source.username, textDirection: TextDirection.ltr,
                    textAlign: TextAlign.right),
                  trailing: IconButton(
                    tooltip: 'حذف کانال از فهرست برنامه',
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () async {
                      final shouldRemove = await showDialog<bool>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          title: const Text('حذف منبع خبری؟'),
                          content: Text('«' + source.title +
                            '» از فهرست خبرهای برنامه حذف می‌شود. عضویت شما در تلگرام تغییر نمی‌کند.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dialogContext, false),
                              child: const Text('انصراف'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(dialogContext, true),
                              child: const Text('حذف از برنامه'),
                            ),
                          ],
                        ),
                      );
                      if (shouldRemove == true) {
                        await widget.news.removeChannel(source.id);
                      }
                    },
                  ),
                ),
                if (source.id != widget.news.sources.values.last.id)
                  Divider(height: 1, indent: 62, color: colors.outlineVariant.withValues(alpha: .55)),
              ],
            ]),
          ),
        const SizedBox(height: 24),
        sectionTitle('نمایش و همگام‌سازی'),
        surfacePanel(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          child: Column(children: [
            SwitchListTile.adaptive(
              secondary: Icon(widget.dark ? Icons.dark_mode_outlined : Icons.light_mode_outlined),
              title: const Text('حالت تاریک'),
              subtitle: const Text('تغییر رنگ‌بندی برنامه'),
              value: widget.dark,
              onChanged: (_) => widget.onToggleTheme(),
            ),
            Divider(height: 1, indent: 60, color: colors.outlineVariant.withValues(alpha: .55)),
            ListTile(
              leading: const Icon(Icons.sync_rounded),
              title: const Text('تازه‌سازی خبرها'),
              subtitle: const Text('دریافت آخرین پست‌های منابع انتخابی'),
              trailing: const Icon(Icons.chevron_left_rounded),
              onTap: () async {
                await refreshNews();
                if (mounted) message('درخواست تازه‌سازی انجام شد.');
              },
            ),
          ]),
        ),
        const SizedBox(height: 24),
        surfacePanel(child: Row(children: [
          Icon(Icons.verified_user_outlined, color: colors.primary),
          const SizedBox(width: 11),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('حساب تلگرام', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('متصل • اطلاعات ورود در همین گوشی نگهداری می‌شود',
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
          ])),
        ])),
      ],
    );
  }

  Future<void> refreshNews() async {
    if (refreshing || widget.news.busy) return;
    setState(() { refreshing = true; });
    try {
      await widget.news.refresh();
    } finally {
      if (mounted) setState(() { refreshing = false; });
    }
  }


  Future<void> savePost(NewsPost post) async {
    if (!savingPosts.add(post.key)) return;
    setState(() {});
    try {
      await NewsDownloadService.save(widget.news, post);
      message('فایل در پوشه Downloads/NabzKhabar ذخیره شد.');
    } catch (_) {
      message('ذخیره فایل انجام نشد؛ اینترنت و فضای گوشی را بررسی کنید.');
    } finally {
      savingPosts.remove(post.key);
      if (mounted) setState(() {});
    }
  }

  void openAttachment(NewsPost post) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => NewsMediaViewer(news: widget.news, post: post),
    ));
  }

  Widget postCard(NewsPost post) {
    final colors = Theme.of(context).colorScheme;
    final hasPhoto = post.photoPath != null && post.photoPath!.isNotEmpty;
    final hasPreview = post.previewBytes != null && post.previewBytes!.isNotEmpty;
    final headline = post.body.trim().split('\n').first;
    final playingInline = inlineVideoKey == post.key;
    if (post.photoId != null && !hasPhoto) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.news.requestThumbnail(post);
      });
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: .46)),
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: .035),
            blurRadius: 18,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          if (post.mediaKind == 'pdf' || post.mediaKind == 'photo') {
            openAttachment(post); return;
          }
          if (post.mediaKind == 'file') { unawaited(savePost(post)); return; }
          if (post.mediaKind == 'video') {
            setState(() { inlineVideoKey = playingInline ? null : post.key; });
            return;
          }
          showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (sheetContext) => SafeArea(
            child: FractionallySizedBox(
              heightFactor: .82,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(post.source, style: Theme.of(sheetContext).textTheme.titleLarge),
                    const SizedBox(height: 6),
                    Text(dateLabel(post.date),
                      style: Theme.of(sheetContext).textTheme.bodySmall),
                    const SizedBox(height: 16),
                    Expanded(child: SingleChildScrollView(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        if (hasPhoto) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.file(
                              File(post.photoPath!),
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                        SelectableText(post.body,
                          textAlign: TextAlign.justify,
                          textDirection: TextDirection.rtl,
                          style: const TextStyle(fontSize: 16, height: 1.9)),
                      ]),
                    )),
                    const SizedBox(height: 12),
                    if (post.mediaKind == 'video' || post.mediaKind == 'pdf') ...[
                      FilledButton.icon(
                        onPressed: () => openAttachment(post),
                        icon: Icon(post.mediaKind == 'pdf'
                            ? Icons.picture_as_pdf_rounded : Icons.play_circle_rounded),
                        label: Text(post.mediaKind == 'pdf'
                            ? 'خواندن PDF در برنامه' : 'پخش ویدئو در برنامه'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    FilledButton.icon(
                      onPressed: () => launchUrl(Uri.parse(post.link),
                          mode: LaunchMode.externalApplication),
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: const Text('مشاهده خبر در تلگرام'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          );
        },
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (post.mediaKind == 'pdf')
            Container(
              height: 122,
              width: double.infinity,
              color: colors.primaryContainer.withValues(alpha: .47),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.picture_as_pdf_rounded, size: 48, color: colors.primary),
                const SizedBox(width: 12),
                Flexible(child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('سند PDF', style: TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 16)),
                    Text(post.fileName ?? 'برای نمایش لمس کنید',
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                )),
              ]),
            )
          else if (post.mediaKind == 'video' && playingInline)
            NewsInlineVideo(
              key: ValueKey(post.key), news: widget.news, post: post,
              onClose: () => setState(() { inlineVideoKey = null; }),
            )
          else if (post.mediaKind == 'video')
            SizedBox(
              height: 192,
              width: double.infinity,
              child: Stack(fit: StackFit.expand, children: [
                if (hasPhoto)
                  Image.file(
                    File(post.photoPath!), fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  )
                else if (hasPreview)
                  Image.memory(
                    post.previewBytes!, fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) => ColoredBox(
                      color: colors.primaryContainer.withValues(alpha: .45)),
                  )
                else
                  ColoredBox(color: colors.primaryContainer.withValues(alpha: .45)),
                Center(child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: Color(0xbf000000), shape: BoxShape.circle),
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Icon(Icons.play_arrow_rounded,
                      size: 36, color: Colors.white),
                  ),
                )),
                const Positioned(
                  right: 12, bottom: 11,
                  child: Text('ویدئو', style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ]),
            )
          else if (post.mediaKind == 'file')
            Container(
              padding: const EdgeInsets.all(18),
              height: 100, color: colors.primaryContainer.withValues(alpha: .4),
              child: Row(children: [
                Icon(Icons.insert_drive_file_rounded, color: colors.primary, size: 39),
                const SizedBox(width: 11),
                Expanded(child: Text(post.fileName ?? 'فایل پیوست',
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700))),
              ]),
            )
          else if (hasPhoto)
            Image.file(
              File(post.photoPath!), height: 192, width: double.infinity,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.low,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            )
          else if (post.mediaKind == 'photo' && hasPreview)
            Image.memory(post.previewBytes!, height: 192, width: double.infinity,
              fit: BoxFit.cover, filterQuality: FilterQuality.low,
              errorBuilder: (_, __, ___) => const SizedBox.shrink()),
          Padding(
            padding: const EdgeInsets.fromLTRB(17, 17, 17, 18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: colors.primaryContainer,
                  foregroundColor: colors.onPrimaryContainer,
                  child: const Icon(Icons.campaign_outlined, size: 19),
                ),
                const SizedBox(width: 9),
                Expanded(child: Text(post.source,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                const SizedBox(width: 7),
                Text(dateLabel(post.date),
                  style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
              ]),
              const SizedBox(height: 14),
              Text(headline,
                textAlign: TextAlign.justify,
                textDirection: TextDirection.rtl,
                maxLines: 3, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 19, height: 1.6,
                  fontFamily: 'Rooznameh', fontWeight: FontWeight.w700)),
              if (post.body.trim().contains('\n')) ...[
                const SizedBox(height: 7),
                Text(post.body.trim().split('\n').skip(1).join('\n'),
                  textAlign: TextAlign.justify,
                  textDirection: TextDirection.rtl,
                  maxLines: 3, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, height: 1.65,
                    color: colors.onSurfaceVariant)),
              ],
              const SizedBox(height: 12),
              Row(children: [
                Text(post.mediaKind == 'pdf' ? 'خواندن PDF'
                    : post.mediaKind == 'video' ? 'پخش ویدئو'
                    : post.mediaKind == 'file' ? 'دریافت فایل'
                    : post.mediaKind == 'photo' ? 'نمایش تصویر' : 'ادامه خبر', style: TextStyle(
                  color: colors.primary, fontWeight: FontWeight.w700, fontSize: 12)),
                const SizedBox(width: 3),
                Icon(Icons.arrow_back_rounded, size: 16, color: colors.primary),
                const Spacer(),
                if (post.mediaFileId != null || post.photoId != null)
                  savingPosts.contains(post.key)
                      ? const SizedBox(width: 22, height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : IconButton(
                          key: ValueKey('download-' + post.key),
                          tooltip: 'دانلود و ذخیره در گوشی',
                          onPressed: () => savePost(post),
                          icon: Icon(Icons.download_rounded, color: colors.primary),
                        ),
                Icon(Icons.open_in_new_rounded, size: 15, color: colors.onSurfaceVariant),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget newsScreen(List<NewsPost> filtered) {
    final colors = Theme.of(context).colorScheme;
    final header = <Widget>[
      const NewsClockCard(),
      const SizedBox(height: 14),
      TextField(
        controller: search,
        onChanged: (value) => setState(() { filter = value; }),
        decoration: decoratedInput('جست‌وجو در میان خبرها', icon: Icons.search_rounded),
      ),
      const SizedBox(height: 15),
      Row(children: [
        Text('آخرین خبرها',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(50)),
          child: Text(filtered.length.toString(),
            style: TextStyle(color: colors.onPrimaryContainer,
                fontSize: 12, fontWeight: FontWeight.w800)),
        ),
        const Spacer(),
        IconButton(
          onPressed: refreshing ? null : refreshNews,
          tooltip: 'تازه‌سازی اخبار',
          icon: refreshing
              ? const SizedBox(width: 19, height: 19,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.refresh_rounded),
        ),
      ]),
      const SizedBox(height: 8),
      if (widget.news.sources.isEmpty)
        surfacePanel(child: Column(children: [
          Container(
            width: 61, height: 61,
            decoration: BoxDecoration(color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(18)),
            child: Icon(Icons.newspaper_rounded, color: colors.primary, size: 31),
          ),
          const SizedBox(height: 12),
          const Text('هنوز منبع خبری ندارید',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 7),
          Text('اولین کانال عمومی را از تنظیمات اضافه کنید.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant)),
          const SizedBox(height: 15),
          FilledButton.icon(
            onPressed: () => setState(() { selectedTab = 1; }),
            icon: const Icon(Icons.settings_outlined),
            label: const Text('مدیریت منابع خبری'),
          ),
        ]))
      else if (filtered.isEmpty)
        surfacePanel(child: Column(children: [
          Icon(filter.trim().isEmpty
              ? Icons.hourglass_empty_rounded : Icons.manage_search_rounded,
              size: 38, color: colors.primary),
          const SizedBox(height: 12),
          Text(filter.trim().isEmpty
              ? 'در حال دریافت تازه‌ترین خبرها…'
              : 'خبری با این عبارت پیدا نشد',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('برای تازه‌سازی، صفحه را پایین بکشید.',
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12)),
        ])),
      if (filtered.isNotEmpty) const SizedBox(height: 3),
    ];
    return RefreshIndicator(
      onRefresh: refreshNews,
      child: NotificationListener<ScrollNotification>(
        onNotification: (event) {
          if (event is ScrollStartNotification && inlineVideoKey != null) {
            setState(() { inlineVideoKey = null; });
          }
          return false;
        },
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          // Only construct visible cards. Building every news card at once
          // caused UI stalls when multiple channels were synchronized.
          itemCount: header.length + filtered.length + 1,
          itemBuilder: (context, index) {
            if (index < header.length) return header[index];
            final offset = index - header.length;
            if (offset < filtered.length) {
              final post = filtered[offset];
              return KeyedSubtree(key: ValueKey(post.key), child: postCard(post));
            }
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 17),
              child: Text('برای دریافت خبرهای تازه، صفحه را به پایین بکشید.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.news,
        builder: (context, _) {
          final ready = widget.news.state == 'authorizationStateReady';
          final filtered = widget.news.feed.where((post) =>
              (post.source + ' ' + post.body)
                  .toLowerCase().contains(filter.trim().toLowerCase())).toList();
          final colors = Theme.of(context).colorScheme;
          return Scaffold(
            appBar: AppBar(
              title: Row(children: [
                Container(
                  width: 37, height: 37,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.newspaper_rounded, size: 21,
                    color: colors.onPrimaryContainer),
                ),
                const SizedBox(width: 10),
                const Text('نبض خبر', style: TextStyle(
                  fontFamily: 'Rooznameh', fontSize: 23,
                  fontWeight: FontWeight.w800)),
              ]),
              actions: [
                if (ready && selectedTab == 0)
                  IconButton(
                    tooltip: 'تنظیمات',
                    icon: const Icon(Icons.tune_rounded),
                    onPressed: () => setState(() { selectedTab = 1; }),
                  ),
              ],
            ),
            body: SafeArea(
              child: Center(child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: !ready
                    ? ListView(
                        padding: const EdgeInsets.all(20),
                        children: [
                          if (widget.news.state == 'setup') setup()
                          else authorization(),
                        ],
                      )
                    : selectedTab == 0
                        ? newsScreen(filtered)
                        : settingsScreen(),
              )),
            ),
            bottomNavigationBar: ready
                ? NavigationBar(
                    selectedIndex: selectedTab,
                    onDestinationSelected: (index) => setState(() {
                      inlineVideoKey = null;
                      selectedTab = index;
                    }),
                    destinations: const [
                      NavigationDestination(
                        icon: Icon(Icons.home_outlined),
                        selectedIcon: Icon(Icons.home_rounded),
                        label: 'خبرها',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.settings_outlined),
                        selectedIcon: Icon(Icons.settings_rounded),
                        label: 'تنظیمات',
                      ),
                    ],
                  )
                : null,
          );
        },
      );
}
