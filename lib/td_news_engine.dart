import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tdlib/tdlib.dart';

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

  NewsPost(this.chatId, this.id, this.date, this.source, this.username, this.body,
      this.photoId, this.photoPath,
      {this.mediaKind = 'none', this.mediaFileId, this.mediaPath, this.fileName});

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
  final photoTargets = <int, Set<String>>{};
  final downloadWaiters = <int, Completer<String>>{};
  StreamSubscription<Map<String, dynamic>>? listener;
  String state = 'setup';
  String status = 'API ID و API Hash را برای ورود وارد کنید';
  bool busy = false;
  bool disposed = false;
  bool parametersSubmitted = false;
  int apiId = 0;
  String apiHash = '';
  String dbDirectory = '';

  TdNewsController(this.prefs) {
    for (final raw in prefs.getStringList('td_channels') ?? <String>[]) {
      try {
        final source = NewsSource.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        sources[source.id] = source;
      } catch (_) { /* Invalid local preference is ignored. */ }
    }
  }

  void changed() { if (!disposed) notifyListeners(); }
  List<NewsPost> get feed => posts.values.toList()
    ..sort((a, b) => b.date != a.date ? b.date.compareTo(a.date) : b.id.compareTo(a.id));

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
          changed();
        }
      case 'updateFile':
        if (event['file'] is Map) {
          final file = Map<String, dynamic>.from(event['file'] as Map);
          updatePhoto(file);
          completeAttachment(file);
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
        await bridge.request({
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
        });
      } catch (_) {
        parametersSubmitted = false;
        status = 'API ID یا API Hash پذیرفته نشد؛ مقادیر را بررسی کنید.';
        changed();
      }
    } else if (state == 'authorizationStateReady') {
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
      // The Add + Join UI explicitly tells the user this joins the channel.
      try {
        await bridge.request({'@type': 'joinChat', 'chat_id': id});
      } catch (error) {
        if (!error.toString().toLowerCase().contains('already')) rethrow;
      }
      sources[id] = NewsSource(id, name, chat['title']?.toString() ?? name);
      await persist();
      await loadHistory(id);
      status = 'کانال افزوده شد؛ اخبار تازه دریافت می‌شوند.';
    } finally { busy = false; changed(); }
  }

  Future<void> removeChannel(int id) async {
    sources.remove(id);
    posts.removeWhere((_, value) => value.chatId == id);
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
    for (final source in sources.values.toList()) { await loadHistory(source.id); }
  }

  Future<void> loadHistory(int id) async {
    try {
      final response = await bridge.request({
        '@type': 'getChatHistory', 'chat_id': id, 'from_message_id': 0,
        'offset': 0, 'limit': 40, 'only_local': false,
      });
      if (response['messages'] is List) {
        for (final m in response['messages'] as List) {
          if (m is Map) record(Map<String, dynamic>.from(m));
        }
      }
    } catch (_) {
      status = 'دریافت تاریخچه یکی از کانال‌ها موفق نبود؛ دوباره تلاش کنید.';
      changed();
    }
  }

  String messageText(Map<String, dynamic> content) {
    final type = content['@type'];
    final formatted = type == 'messageText' ? content['text']
        : (type == 'messagePhoto' || type == 'messageVideo' ||
           type == 'messageDocument' || type == 'messageAnimation')
            ? content['caption'] : null;
    if (formatted is Map && formatted['text'] is String &&
        (formatted['text'] as String).trim().isNotEmpty) {
      return formatted['text'] as String;
    }
    if (type == 'messagePhoto') return 'خبر تصویری';
    if (type == 'messageVideo' || type == 'messageVideoNote' || type == 'messageAnimation') return 'ویدئو';
    if (type == 'messageDocument') {
      final doc = content['document'];
      final name = doc is Map ? doc['file_name']?.toString() : null;
      return name == null || name.isEmpty ? 'سند پیوست' : name;
    }
    return 'خبر جدید؛ برای مشاهده در تلگرام باز کنید';
  }

  void record(Map<String, dynamic> message) {
    final chatId = message['chat_id'];
    final messageId = message['id'];
    if (chatId is! int || messageId is! int || !sources.containsKey(chatId) ||
        message['content'] is! Map) return;
    final source = sources[chatId]!;
    final content = Map<String, dynamic>.from(message['content'] as Map);
    int? fileId;
    int? mediaFileId;
    String? fileName;
    String mediaKind = 'none';
    if (content['@type'] == 'messagePhoto' && content['photo'] is Map) {
      mediaKind = 'photo';
      final sizes = (content['photo'] as Map)['sizes'];
      if (sizes is List && sizes.isNotEmpty && sizes.last is Map) {
        final photo = (sizes.last as Map)['photo'];
        if (photo is Map && photo['id'] is int) fileId = photo['id'] as int;
      }
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
        }
      }
      final thumb = document['thumbnail'];
      if (mediaKind != 'none' && thumb is Map && thumb['file'] is Map) {
        final image = thumb['file'] as Map;
        if (image['id'] is int) fileId = image['id'] as int;
      }
    }
    final key = chatId.toString() + ':' + messageId.toString();
    final prior = posts[key];
    posts[key] = NewsPost(chatId, messageId, message['date'] as int? ?? 0,
        source.title, source.username, messageText(content), fileId, prior?.photoPath,
        mediaKind: mediaKind,
        mediaFileId: mediaFileId,
        mediaPath: prior?.mediaFileId == mediaFileId ? prior?.mediaPath : null,
        fileName: fileName);
    changed();
    if (fileId != null && prior?.photoPath == null) {
      photoTargets.putIfAbsent(fileId, () => <String>{}).add(key);
      unawaited(downloadPhoto(fileId));
    }
  }

  /// Downloads an attachment only when the reader opens it. The TDLib file
  /// remains in the app-private directory, not in an unauthenticated URL.
  Future<String> ensureMedia(NewsPost post) async {
    final id = post.mediaFileId;
    if (id == null || (post.mediaKind != 'video' && post.mediaKind != 'pdf')) {
      throw StateError('فایل قابل پخش یا PDF در این پیام پیدا نشد.');
    }
    if (post.mediaPath != null && post.mediaPath!.isNotEmpty) {
      return post.mediaPath!;
    }
    final existing = downloadWaiters[id];
    if (existing != null) return existing.future;
    final waiter = Completer<String>();
    downloadWaiters[id] = waiter;
    try {
      final result = await bridge.request({
        '@type': 'downloadFile',
        'file_id': id,
        'priority': 24,
        'offset': 0,
        'limit': 0,
        'synchronous': false,
      });
      completeAttachment(result);
      final path = await waiter.future.timeout(const Duration(minutes: 3));
      post.mediaPath = path;
      changed();
      return path;
    } finally {
      downloadWaiters.remove(id);
    }
  }

  void completeAttachment(Map<String, dynamic> file) {
    final id = file['id'];
    if (id is! int) return;
    final waiter = downloadWaiters[id];
    if (waiter == null || waiter.isCompleted) return;
    final local = file['local'];
    if (local is! Map) return;
    final path = local['path'];
    if (local['is_downloading_completed'] == true && path is String && path.isNotEmpty) {
      waiter.complete(path);
    }
  }

  Future<void> downloadPhoto(int id) async {
    try {
      final file = await bridge.request({
        '@type': 'downloadFile', 'file_id': id, 'priority': 1,
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
