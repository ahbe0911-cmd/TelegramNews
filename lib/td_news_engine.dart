import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tdlib/tdlib.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'td_mtproto_proxy.dart';

/// The blocking TDLib receive loop runs away from Flutter's UI isolate.
Future<void> tdWorker(SendPort output) async {
  final input = ReceivePort();
  output.send(input.sendPort);
  var running = true;
  int client = 0;
  try {
    TdNativePlugin.registerWith();
    await TdPlugin.initialize('libtdjson.so');
    client = TdPlugin.instance.tdJsonClientCreate();
    input.listen((dynamic command) {
      if (command is! Map) return;
      if (command['op'] == 'stop') {
        running = false;
      } else if (command['op'] == 'send') {
        TdPlugin.instance.tdJsonClientSend(client, jsonEncode(command['data']));
      }
    });
    while (running) {
      final result = TdPlugin.instance.tdJsonClientReceive(client, 0.2);
      if (result != null) output.send(jsonDecode(result));
      await Future<void>.delayed(Duration.zero);
    }
    TdPlugin.instance.tdJsonClientSend(client, jsonEncode({'@type': 'close'}));
    for (var i = 0; i < 30; i++) {
      final result = TdPlugin.instance.tdJsonClientReceive(client, 0.2);
      if (result == null) continue;
      final event = jsonDecode(result) as Map;
      if (event['@type'] == 'updateAuthorizationState' &&
          (event['authorization_state'] as Map?)?['@type'] == 'authorizationStateClosed') break;
    }
  } catch (_) {
    output.send({'@type': 'engineFailure'});
  } finally {
    if (client != 0) TdPlugin.instance.tdJsonClientDestroy(client);
    input.close();
  }
}

class TdBridge {
  final updates = StreamController<Map<String, dynamic>>.broadcast();
  final waiters = <String, Completer<Map<String, dynamic>>>{};
  SendPort? sender;
  ReceivePort? receiver;
  int serial = 0;

  Future<void> start() async {
    final inbox = ReceivePort();
    receiver = inbox;
    final initialized = Completer<void>();
    inbox.listen((dynamic message) {
      if (message is SendPort) {
        sender = message;
        initialized.complete();
      } else if (message is Map) {
        final event = Map<String, dynamic>.from(message);
        final tag = event['@extra']?.toString();
        final waiter = tag == null ? null : waiters.remove(tag);
        if (waiter != null) {
          if (event['@type'] == 'error') {
            waiter.completeError(StateError(event['message']?.toString() ?? 'Telegram error'));
          } else {
            waiter.complete(event);
          }
        } else {
          updates.add(event);
        }
      }
    });
    await Isolate.spawn(tdWorker, inbox.sendPort);
    await initialized.future.timeout(const Duration(seconds: 15));
  }

  Future<Map<String, dynamic>> request(Map<String, dynamic> body) async {
    if (sender == null) throw StateError('TDLib is not ready');
    final tag = 'query-' + (++serial).toString();
    final waiter = Completer<Map<String, dynamic>>();
    waiters[tag] = waiter;
    sender!.send({'op': 'send', 'data': {...body, '@extra': tag}});
    try {
      return await waiter.future.timeout(const Duration(seconds: 40));
    } finally {
      waiters.remove(tag);
    }
  }

  void stop() {
    sender?.send({'op': 'stop'});
    sender = null;
    receiver?.close();
    for (final waiter in waiters.values) {
      if (!waiter.isCompleted) waiter.completeError(StateError('Client closed'));
    }
    waiters.clear();
    updates.close();
  }
}

class NewsSource {
  final int id;
  final String username;
  final String title;
  NewsSource(this.id, this.username, this.title);
  factory NewsSource.fromJson(Map<String, dynamic> m) =>
      NewsSource(m['id'] as int, m['username'] as String, m['title'] as String);
  Map<String, dynamic> toJson() => {'id': id, 'username': username, 'title': title};
}

class NewsPost {
  final int chatId;
  final int id;
  final int date;
  final String source;
  final String username;
  String body;
  int? photoId;
  String? photoPath;
  String mediaKind; // photo | video | pdf | none
  int? mediaFileId;
  String? mediaPath;
  String? fileName;
  Uint8List? previewBytes;

  NewsPost(this.chatId, this.id, this.date, this.source, this.username, this.body,
      this.photoId, this.photoPath,
      {this.mediaKind = 'none', this.mediaFileId, this.mediaPath, this.fileName,
       this.previewBytes});

  String get key => chatId.toString() + ':' + id.toString();
  String get link => 'https://t.me/' + username + '/' + (id >> 20).toString();
}

String? parsePublicUsername(String input) {
  final cleaned = input.trim()
      .replaceFirst(RegExp(r'^https?://(?:www\.)?t\.me/', caseSensitive: false), '')
      .replaceFirst(RegExp(r'^@'), '').split('/').first.split('?').first;
  return RegExp(r'^[a-zA-Z][a-zA-Z0-9_]{4,31}$').hasMatch(cleaned) ? cleaned : null;
}

class TdNewsController extends ChangeNotifier {
  final SharedPreferences prefs;
  final bridge = TdBridge();
  final sources = <int, NewsSource>{};
  final posts = <String, NewsPost>{};
  final saved = <String, NewsPost>{};
  final photoTargets = <int, Set<String>>{};
  final downloadWaiters = <int, Completer<String>>{};
  final downloadProgress = <int, double>{};
  final _thumbnailStarted = <int>{};
  List<NewsPost>? _sortedFeed;
  StreamSubscription<Map<String, dynamic>>? listener;
  String state = 'setup';
  String status = 'API ID و API Hash را برای ورود وارد کنید';
  bool busy = false;
  bool disposed = false;
  bool parametersSubmitted = false;
  Future<void>? parametersSetup;
  int apiId = 0;
  String apiHash = '';
  String dbDirectory = '';
  // Proxy links (including their secrets) live in Android secure storage.
  static const _proxyStorageKey = 'td_manual_mtproto_proxy';
  static const _vault = FlutterSecureStorage();
  bool get manualProxyEnabled => prefs.getBool('td_manual_mtproto_enabled') ?? false;
  bool manualProxyBusy = false;
  bool manualProxyActive = false; // TDLib accepted it; reachability is separate.
  bool manualProxyConnected = false;
  String manualProxyStatus = 'لینک MTProto را وارد کنید و اتصال را بزنید.';

  TdNewsController(this.prefs) {
    for (final raw in prefs.getStringList('td_channels') ?? <String>[]) {
      try {
        final source = NewsSource.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        sources[source.id] = source;
      } catch (_) { /* Invalid local preference is ignored. */ }
    }
    for (final raw in prefs.getStringList('td_saved_posts') ?? <String>[]) {
      try {
        final item = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        final savedPost = NewsPost(
          item['chat_id'] as int,
          item['message_id'] as int,
          item['date'] as int,
          item['source'] as String,
          item['username'] as String,
          item['body'] as String,
          item['photo_id'] as int?,
          null,
          mediaKind: item['media_kind'] as String? ?? 'none',
          mediaFileId: item['media_file_id'] as int?,
          fileName: item['file_name'] as String?,
        );
        saved[savedPost.key] = savedPost;
      } catch (_) { /* One invalid bookmark must not hide other bookmarks. */ }
    }
  }

  bool isSaved(NewsPost post) => saved.containsKey(post.key);

  List<NewsPost> get savedFeed {
    final result = saved.entries.map((entry) => posts[entry.key] ?? entry.value).toList();
    result.sort((a, b) => b.date != a.date
        ? b.date.compareTo(a.date) : b.id.compareTo(a.id));
    return result;
  }

  Future<void> toggleSaved(NewsPost post) async {
    if (saved.containsKey(post.key)) {
      saved.remove(post.key);
    } else {
      saved[post.key] = post;
    }
    changed();
    // Persist a compact text-and-attachment snapshot: saved posts remain
    // readable even when they leave the 25-message live history window.
    await prefs.setStringList('td_saved_posts', saved.values.map((post) {
      return jsonEncode({
        'chat_id': post.chatId,
        'message_id': post.id,
        'date': post.date,
        'source': post.source,
        'username': post.username,
        'body': post.body,
        'photo_id': post.photoId,
        'media_kind': post.mediaKind,
        'media_file_id': post.mediaFileId,
        'file_name': post.fileName,
      });
    }).toList());
  }

  void changed() { if (!disposed) notifyListeners(); }
  List<NewsPost> get feed => _sortedFeed ??= (posts.values.toList()
    ..sort((a, b) => b.date != a.date ? b.date.compareTo(a.date) : b.id.compareTo(a.id)));

  Future<void> _applyManualProxy(MtprotoProxyConfig proxy) async {
    await bridge.request({
      '@type': 'addProxy',
      'server': proxy.server,
      'port': proxy.port,
      'enable': true,
      'type': {'@type': 'proxyTypeMtproto', 'secret': proxy.secret},
    });
    manualProxyActive = true;
    manualProxyConnected = false;
    manualProxyStatus = 'پروکسی انتخاب شد؛ در حال بررسی اتصال تلگرام…';
    changed();
  }

  /// Save before starting TDLib so the proxy is available on the login screen.
  /// Adding a proxy in TDLib does NOT establish that the remote server works.
  Future<void> connectManualProxy(String link) async {
    final proxy = parseMtprotoProxyLink(link);
    if (manualProxyBusy) return;
    manualProxyBusy = true;
    changed();
    try {
      await _vault.write(key: _proxyStorageKey, value: link.trim());
      await prefs.setBool('td_manual_mtproto_enabled', true);
      if (bridge.sender == null || state == 'setup' || state == 'failed') {
        manualProxyStatus = 'لینک ذخیره شد؛ هنگام راه‌اندازی تلگرام فعال می‌شود.';
      } else {
        if (parametersSetup != null) await parametersSetup;
        await _applyManualProxy(proxy);
      }
    } catch (_) {
      manualProxyActive = false;
      manualProxyConnected = false;
      manualProxyStatus = 'ثبت یا فعال‌سازی پروکسی ناموفق بود؛ دوباره تلاش کنید.';
      rethrow;
    } finally {
      manualProxyBusy = false;
      changed();
    }
  }

  Future<void> disconnectManualProxy() async {
    if (manualProxyBusy) return;
    manualProxyBusy = true;
    changed();
    try {
      if (bridge.sender != null) {
        await bridge.request({'@type': 'disableProxy'});
      }
      await prefs.setBool('td_manual_mtproto_enabled', false);
      await _vault.delete(key: _proxyStorageKey);
      manualProxyActive = false;
      manualProxyConnected = false;
      manualProxyStatus = 'پروکسی غیرفعال شد؛ اتصال مستقیم.';
    } catch (_) {
      manualProxyStatus = 'قطع پروکسی انجام نشد؛ دوباره تلاش کنید.';
      rethrow;
    } finally {
      manualProxyBusy = false;
      changed();
    }
  }

  Future<void> restoreManualProxy() async {
    // A previously selected TDLib proxy may survive an app restart.
    if (!manualProxyEnabled) {
      await bridge.request({'@type': 'disableProxy'});
      manualProxyActive = false;
      manualProxyConnected = false;
      manualProxyStatus = 'اتصال مستقیم؛ برای فعال‌سازی لینک MTProto وارد کنید.';
      changed();
      return;
    }
    try {
      final link = await _vault.read(key: _proxyStorageKey);
      if (link == null || link.isEmpty) {
        manualProxyStatus = 'لینک ذخیره‌شده پیدا نشد؛ لینک MTProto جدید وارد کنید.';
        await bridge.request({'@type': 'disableProxy'});
        await prefs.setBool('td_manual_mtproto_enabled', false);
        changed();
        return;
      }
      await _applyManualProxy(parseMtprotoProxyLink(link));
    } catch (_) {
      manualProxyActive = false;
      manualProxyConnected = false;
      manualProxyStatus = 'فعال‌سازی لینک قبلی ناموفق بود؛ لینک جدید وارد کنید.';
      try { await bridge.request({'@type': 'disableProxy'}); } catch (_) {}
      changed();
    }
  }

  Future<void> start(int id, String hash, String path) async {
    if (state != 'setup' && state != 'failed') return;
    apiId = id;
    apiHash = hash;
    dbDirectory = path;
    state = 'connecting';
    status = 'در حال راه‌اندازی TDLib…';
    changed();
    try {
      listener = bridge.updates.stream.listen(onEvent);
      await bridge.start();
      await onAuthorization(await bridge.request({'@type': 'getAuthorizationState'}));
      // TDLib rejects proxy commands while its database/API parameters are
      // still being initialized. Do not stop the local relay prematurely.
      if (parametersSetup != null) await parametersSetup;
      await restoreManualProxy();
    } catch (_) {
      state = 'failed';
      status = 'راه‌اندازی TDLib ناموفق بود؛ تنظیمات یا کتابخانه بومی را بررسی کنید.';
      changed();
    }
  }

  void onEvent(Map<String, dynamic> event) {
    switch (event['@type']) {
      case 'updateAuthorizationState':
        if (event['authorization_state'] is Map) {
          unawaited(onAuthorization(Map<String, dynamic>.from(event['authorization_state'] as Map)));
        }
      case 'updateNewMessage':
        if (event['message'] is Map) record(Map<String, dynamic>.from(event['message'] as Map));
      case 'updateMessageContent':
        final key = event['chat_id'].toString() + ':' + event['message_id'].toString();
        final previous = posts[key];
        if (previous != null && event['new_content'] is Map) {
          record({
            'chat_id': previous.chatId,
            'id': previous.id,
            'date': previous.date,
            'content': event['new_content'],
          });
        }
      case 'updateDeleteMessages':
        if (event['is_permanent'] == true && event['message_ids'] is List) {
          for (final id in event['message_ids'] as List) {
            posts.remove(event['chat_id'].toString() + ':' + id.toString());
          }
          _sortedFeed = null;
          changed();
        }
      case 'updateFile':
        if (event['file'] is Map) {
          final file = Map<String, dynamic>.from(event['file'] as Map);
          updatePhoto(file);
          completeAttachment(file);
        }
      case 'updateConnectionState':
        if (manualProxyEnabled && manualProxyActive) {
          final connection = event['state'];
          final connectionType = connection is Map ? connection['@type'] : null;
          manualProxyConnected = connectionType == 'connectionStateReady';
          manualProxyStatus = manualProxyConnected
              ? 'تلگرام از طریق پروکسی متصل شد.'
              : connectionType == 'connectionStateWaitingForNetwork'
                  ? 'شبکه در دسترس نیست؛ اتصال پروکسی برقرار نشد.'
                  : 'پروکسی انتخاب شده؛ در انتظار اتصال تلگرام…';
          changed();
        }
      case 'engineFailure':
        state = 'failed';
        status = 'کتابخانه بومی TDLib اجرا نشد.';
        changed();
    }
  }

  Future<void> onAuthorization(Map<String, dynamic> authorization) async {
    state = authorization['@type']?.toString() ?? 'connecting';
    status = switch (state) {
      'authorizationStateWaitPhoneNumber' => 'شماره حساب تلگرام را با پیش‌شماره کشور وارد کنید',
      'authorizationStateWaitCode' => 'کد ورودی که تلگرام ارسال کرده است را وارد کنید',
      'authorizationStateWaitPassword' => 'گذرواژه دومرحله‌ای تلگرام را وارد کنید',
      'authorizationStateWaitEmailAddress' => 'ایمیل احراز هویت را وارد کنید',
      'authorizationStateWaitEmailCode' => 'کد تأیید ایمیل را وارد کنید',
      'authorizationStateWaitOtherDeviceConfirmation' => 'ورود را روی دستگاه دیگر تأیید کنید',
      'authorizationStateReady' => 'اتصال به حساب تلگرام برقرار شد',
      _ => 'در حال برقراری اتصال…',
    };
    changed();
    if (state == 'authorizationStateWaitTdlibParameters' && !parametersSubmitted) {
      parametersSubmitted = true;
      try {
        parametersSetup = bridge.request({
          '@type': 'setTdlibParameters', 'use_test_dc': false,
          'database_directory': dbDirectory + '/tdlib',
          'files_directory': dbDirectory + '/media',
          'database_encryption_key': '',
          'use_file_database': true, 'use_chat_info_database': true,
          'use_message_database': true, 'use_secret_chats': false,
          'api_id': apiId, 'api_hash': apiHash,
          'system_language_code': 'fa', 'device_model': 'Samsung Galaxy A54',
          'system_version': 'Android', 'application_version': '1.0',
          'enable_storage_optimizer': true, 'ignore_file_names': false,
        }).then((_) {});
        await parametersSetup;
      } catch (_) {
        parametersSubmitted = false;
        status = 'API ID یا API Hash پذیرفته نشد؛ مقادیر را بررسی کنید.';
        changed();
      }
    } else if (state == 'authorizationStateReady') {
      // Keep the configured in-app proxy after authentication completes.
      // Render TDLib's on-device cache before waiting for a remote round trip.
      for (final source in sources.values) {
        unawaited(loadHistory(source.id, limit: 12, onlyLocal: true));
      }
      unawaited(refresh());
    }
  }

  Future<void> submitLogin(String value) async {
    final command = switch (state) {
      'authorizationStateWaitPhoneNumber' =>
        {'@type': 'setAuthenticationPhoneNumber', 'phone_number': value.trim(), 'settings': null},
      'authorizationStateWaitCode' => {'@type': 'checkAuthenticationCode', 'code': value.trim()},
      'authorizationStateWaitPassword' => {'@type': 'checkAuthenticationPassword', 'password': value},
      'authorizationStateWaitEmailAddress' =>
        {'@type': 'setAuthenticationEmailAddress', 'email_address': value.trim()},
      'authorizationStateWaitEmailCode' =>
        {'@type': 'checkAuthenticationEmailCode',
         'code': {'@type': 'emailAddressAuthenticationCode', 'code': value.trim()}},
      _ => <String, dynamic>{},
    };
    if (command.isEmpty) return;
    busy = true; changed();
    try {
      await bridge.request(command);
      status = 'در انتظار پاسخ تلگرام…';
    } catch (_) {
      status = 'اطلاعات ورود تأیید نشد؛ مقدار را بررسی کنید.';
    } finally { busy = false; changed(); }
  }

  Future<void> addChannel(String raw) async {
    if (state != 'authorizationStateReady') throw StateError('ابتدا وارد تلگرام شوید.');
    final name = parsePublicUsername(raw);
    if (name == null) throw FormatException('آدرس کانال باید مانند t.me/channelname باشد.');
    busy = true; changed();
    try {
      final chat = await bridge.request({'@type': 'searchPublicChat', 'username': name});
      final type = chat['type'];
      if (type is! Map || type['@type'] != 'chatTypeSupergroup' || type['is_channel'] != true) {
        throw StateError('آدرس مربوط به یک کانال عمومی نیست.');
      }
      final id = chat['id'] as int;
      // Make the source visible immediately after Telegram resolves it.
      // Joining and history loading are network work and must not keep the
      // Add button blocked for several seconds.
      sources[id] = NewsSource(id, name, chat['title']?.toString() ?? name);
      await persist();
      _sortedFeed = null;
      status = 'کانال اضافه شد؛ خبرهای ذخیره‌شده فوراً نمایش داده می‌شوند.';
      changed();
      unawaited(loadHistory(id, limit: 12, onlyLocal: true));
      unawaited(_joinAndWarm(id));
    } finally { busy = false; changed(); }
  }

  Future<void> _joinAndWarm(int id) async {
    try {
      await bridge.request({'@type': 'joinChat', 'chat_id': id});
    } catch (error) {
      // Public channels may already be joined. History can still be attempted
      // and the UI should stay responsive either way.
      if (!error.toString().toLowerCase().contains('already')) {
        status = 'کانال اضافه شد؛ عضویت خودکار کامل نشد.';
        changed();
      }
    }
    await loadHistory(id, limit: 18);
  }

  Future<void> removeChannel(int id) async {
    sources.remove(id);
    posts.removeWhere((_, value) => value.chatId == id);
    _sortedFeed = null;
    await persist();
    changed();
    // Does not leave the channel in the user's Telegram account.
  }

  Future<void> persist() async {
    await prefs.setStringList('td_channels',
        sources.values.map((v) => jsonEncode(v.toJson())).toList());
  }

  Future<void> refresh() async {
    if (state != 'authorizationStateReady') return;
    // Fetch channel metadata concurrently; avoid serial round-trip delays.
    await Future.wait(sources.values.map((source) => loadHistory(source.id, limit: 25)));
  }

  Future<void> loadHistory(int id, {int limit = 25, bool onlyLocal = false}) async {
    try {
      final response = await bridge.request({
        '@type': 'getChatHistory', 'chat_id': id, 'from_message_id': 0,
        'offset': 0, 'limit': limit, 'only_local': onlyLocal,
      });
      if (response['messages'] is List) {
        for (final m in response['messages'] as List) {
          if (m is Map) record(Map<String, dynamic>.from(m), notify: false);
        }
        _sortedFeed = null;
        changed();
      }
    } catch (_) {
      status = 'دریافت تاریخچه یکی از کانال‌ها موفق نبود؛ دوباره تلاش کنید.';
      changed();
    }
  }

  String messageText(Map<String, dynamic> content) {
    final type = content['@type'];
    final formatted = content['caption'] ?? content['text'];
    if (formatted is Map && formatted['text'] is String &&
        (formatted['text'] as String).trim().isNotEmpty) {
      return formatted['text'] as String;
    }
    if (type == 'messagePhoto') return 'خبر تصویری';
    if (type == 'messageVideo' || type == 'messageVideoNote' || type == 'messageAnimation') return 'ویدئو';
    if (type == 'messageAudio') return 'فایل صوتی';
    if (type == 'messageVoiceNote') return 'پیام صوتی';
    if (type == 'messageDocument') {
      final doc = content['document'];
      final name = doc is Map ? doc['file_name']?.toString() : null;
      return name == null || name.isEmpty ? 'سند پیوست' : name;
    }
    if (type == 'messageUnsupported') return 'دریافت رسانه کامل نشده؛ برای تلاش دوباره لمس کنید';
    return 'پیام کانال';
  }

  /// Link previews may carry a native Telegram video even though the enclosing
  /// post is messageText. Keep the original text while exposing its attachment.
  Map<String, dynamic> mediaContent(Map<String, dynamic> content) {
    if (content['@type'] != 'messageText') return content;
    final preview = content['link_preview'] ?? content['web_page'];
    if (preview is! Map) return content;
    final type = preview['type'];
    final media = type is Map ? type : preview;
    for (final pair in const {'video': 'messageVideo', 'animation': 'messageAnimation',
      'document': 'messageDocument', 'photo': 'messagePhoto'}.entries) {
      if (media[pair.key] is Map) {
        return {...content, '@type': pair.value, pair.key: media[pair.key],
          'caption': content['text']};
      }
    }
    return content;
  }

  Future<bool> reloadPost(NewsPost post) async {
    try {
      final response = await bridge.request({
        '@type': 'getMessage', 'chat_id': post.chatId, 'message_id': post.id,
      });
      if (disposed) return false;
      record(response);
      return posts[post.key]?.mediaKind != 'unsupported';
    } catch (_) {
      return false;
    }
  }

  void record(Map<String, dynamic> message, {bool notify = true}) {
    final chatId = message['chat_id'];
    final messageId = message['id'];
    if (chatId is! int || messageId is! int || !sources.containsKey(chatId) ||
        message['content'] is! Map) return;
    final source = sources[chatId]!;
    final content = mediaContent(Map<String, dynamic>.from(message['content'] as Map));
    int? fileId;
    int? mediaFileId;
    String? fileName;
    String mediaKind = content['@type'] == 'messageUnsupported' ? 'unsupported' : 'none';
    if (content['@type'] == 'messagePhoto' && content['photo'] is Map) {
      mediaKind = 'photo';
      final sizes = (content['photo'] as Map)['sizes'];
      if (sizes is List) {
        int largest = -1;
        int previewRank = 1 << 30;
        for (final candidate in sizes) {
          if (candidate is! Map || candidate['photo'] is! Map) continue;
          final photo = candidate['photo'] as Map;
          final id = photo['id'];
          if (id is! int) continue;
          final width = candidate['width'] is int ? candidate['width'] as int : 0;
          final height = candidate['height'] is int ? candidate['height'] as int : 0;
          final area = width * height;
          if (area >= largest) { largest = area; mediaFileId = id; }
          final rank = (width - 640).abs() + (height - 640).abs();
          if (rank < previewRank) { previewRank = rank; fileId = id; }
        }
      }
      fileId ??= mediaFileId;
    } else if (content['@type'] == 'messageVideo' && content['video'] is Map) {
      mediaKind = 'video';
      final video = content['video'] as Map;
      final file = video['video'];
      if (file is Map && file['id'] is int) mediaFileId = file['id'] as int;
      final thumb = video['thumbnail'];
      if (thumb is Map && thumb['file'] is Map) {
        final image = thumb['file'] as Map;
        if (image['id'] is int) fileId = image['id'] as int;
      }
    } else if (content['@type'] == 'messageVideoNote' &&
        content['video_note'] is Map) {
      mediaKind = 'video';
      final note = content['video_note'] as Map;
      final file = note['video'];
      if (file is Map && file['id'] is int) mediaFileId = file['id'] as int;
      final thumb = note['thumbnail'];
      if (thumb is Map && thumb['file'] is Map) {
        final image = thumb['file'] as Map;
        if (image['id'] is int) fileId = image['id'] as int;
      }
    } else if (content['@type'] == 'messageAnimation' &&
        content['animation'] is Map) {
      final animation = content['animation'] as Map;
      final name = animation['file_name']?.toString() ?? '';
      final mime = animation['mime_type']?.toString().toLowerCase() ?? '';
      if (mime == 'video/mp4' || name.toLowerCase().endsWith('.mp4')) {
        mediaKind = 'video';
        fileName = name;
        final file = animation['animation'];
        if (file is Map && file['id'] is int) mediaFileId = file['id'] as int;
        final thumb = animation['thumbnail'];
        if (thumb is Map && thumb['file'] is Map) {
          final image = thumb['file'] as Map;
          if (image['id'] is int) fileId = image['id'] as int;
        }
      } else {
        mediaKind = 'file';
        fileName = name.isEmpty ? 'animation.gif' : name;
        final file = animation['animation'];
        if (file is Map && file['id'] is int) mediaFileId = file['id'] as int;
      }
    } else if (content['@type'] == 'messageDocument' && content['document'] is Map) {
      final document = content['document'] as Map;
      fileName = document['file_name']?.toString();
      final file = document['document'];
      final lowerName = fileName?.toLowerCase() ?? '';
      final mime = document['mime_type']?.toString().toLowerCase() ?? '';
      if (file is Map && file['id'] is int) {
        if (lowerName.endsWith('.pdf') || mime == 'application/pdf') {
          mediaKind = 'pdf';
          mediaFileId = file['id'] as int;
        } else if (mime.startsWith('video/') || lowerName.endsWith('.mp4') ||
            lowerName.endsWith('.m4v') || lowerName.endsWith('.webm')) {
          mediaKind = 'video';
          mediaFileId = file['id'] as int;
        } else {
          mediaKind = 'file';
          mediaFileId = file['id'] as int;
        }
      }
      final thumb = document['thumbnail'];
      if (thumb is Map && thumb['file'] is Map) {
        final image = thumb['file'] as Map;
        if (image['id'] is int) fileId = image['id'] as int;
      }
    } else if (content['@type'] == 'messageAudio' && content['audio'] is Map) {
      mediaKind = 'file';
      final audio = content['audio'] as Map;
      fileName = audio['file_name']?.toString();
      mediaFileId = audio['audio'] is Map ? (audio['audio'] as Map)['id'] as int? : null;
    } else if (content['@type'] == 'messageVoiceNote' && content['voice_note'] is Map) {
      mediaKind = 'file';
      fileName = 'voice-note.ogg';
      final voice = content['voice_note'] as Map;
      mediaFileId = voice['voice'] is Map ? (voice['voice'] as Map)['id'] as int? : null;
    }
    // TDLib mini_thumbnail is embedded in message metadata: display it
    // immediately without downloading the full video or an extra image.
    Uint8List? previewBytes;
    final media = content['video'] ?? content['video_note'] ??
        content['animation'] ?? content['document'];
    final miniature = media is Map ? media['minithumbnail'] : null;
    final encoded = miniature is Map ? miniature['data'] : null;
    if (encoded is String && encoded.isNotEmpty && encoded.length < 120000) {
      try { previewBytes = base64Decode(encoded); } catch (_) {}
    }
    final key = chatId.toString() + ':' + messageId.toString();
    final prior = posts[key];
    posts[key] = NewsPost(chatId, messageId, message['date'] as int? ?? 0,
        source.title, source.username, messageText(content), fileId,
        prior?.photoId == fileId ? prior?.photoPath : null,
        mediaKind: mediaKind,
        mediaFileId: mediaFileId,
        mediaPath: prior?.mediaFileId == mediaFileId ? prior?.mediaPath : null,
        fileName: fileName,
        previewBytes: previewBytes ?? prior?.previewBytes);
    _sortedFeed = null;
    if (notify) changed();
    // Thumbnails are requested by visible cards only, never for an entire
    // channel history. This prevents network storms when channels are added.
  }

  void requestThumbnail(NewsPost post) {
    final id = post.photoId;
    if (id == null || post.photoPath != null) return;
    photoTargets.putIfAbsent(id, () => <String>{}).add(post.key);
    if (_thumbnailStarted.add(id)) unawaited(downloadPhoto(id));
  }

  /// TDLib caches completed media in app-private storage. Download on demand:
  /// previews and news updates never request full-length video or PDF files.
  Future<String> ensureMedia(NewsPost post) async {
    final id = post.mediaFileId ?? (post.mediaKind == 'photo' ? post.photoId : null);
    if (id == null) throw StateError('فایل قابل دانلودی در این پیام پیدا نشد.');
    final cached = post.mediaPath;
    if (cached != null && cached.isNotEmpty) return cached;
    final pending = downloadWaiters[id];
    if (pending != null) return pending.future;
    final waiter = Completer<String>();
    downloadWaiters[id] = waiter;
    downloadProgress[id] = 0;
    changed();
    try {
      final result = await bridge.request({
        '@type': 'downloadFile', 'file_id': id, 'priority': 32,
        'offset': 0, 'limit': 0, 'synchronous': false,
      });
      completeAttachment(result);
      final path = await waiter.future.timeout(const Duration(minutes: 12));
      post.mediaPath = path;
      downloadProgress[id] = 1;
      changed();
      return path;
    } finally {
      downloadWaiters.remove(id);
      downloadProgress.remove(id);
      changed();
    }
  }

  /// Exposes coarse-grained progress; the native engine updates it in
  /// response to TDLib events without rebuilding every card for every chunk.
  void completeAttachment(Map<String, dynamic> file) {
    final id = file['id'];
    if (id is! int) return;
    final waiter = downloadWaiters[id];
    if (waiter == null || waiter.isCompleted) return;
    final local = file['local'];
    if (local is! Map) return;
    final path = local['path'];
    if (local['is_downloading_completed'] == true && path is String && path.isNotEmpty) {
      downloadProgress[id] = 1;
      waiter.complete(path);
      changed();
      return;
    }
    final expected = file['expected_size'] is int && (file['expected_size'] as int) > 0
        ? file['expected_size'] as int
        : file['size'] is int ? file['size'] as int : 0;
    final downloaded = local['downloaded_size'];
    if (expected > 0 && downloaded is int) {
      final next = (downloaded / expected).clamp(0.0, 0.99).toDouble();
      final old = downloadProgress[id] ?? 0;
      if (next - old >= .035) {
        downloadProgress[id] = next;
        changed();
      }
    }
  }

  Future<void> downloadPhoto(int id) async {
    try {
      final file = await bridge.request({
        '@type': 'downloadFile', 'file_id': id, 'priority': 32,
        'offset': 0, 'limit': 0, 'synchronous': false,
      });
      updatePhoto(file);
    } catch (_) { /* The text post remains readable. */ }
  }

  void updatePhoto(Map<String, dynamic> file) {
    final id = file['id'];
    if (id is! int || file['local'] is! Map) return;
    final local = file['local'] as Map;
    final path = local['path'];
    if (local['is_downloading_completed'] != true || path is! String || path.isEmpty) return;
    for (final key in photoTargets[id] ?? <String>{}) { posts[key]?.photoPath = path; }
    photoTargets.remove(id);
    changed();
  }

  @override
  void dispose() {
    disposed = true;
    unawaited(listener?.cancel());
    for (final waiter in downloadWaiters.values) {
      if (!waiter.isCompleted) waiter.completeError(StateError('نمایشگر بسته شد.'));
    }
    downloadWaiters.clear();
    bridge.stop();
    super.dispose();
  }
}
