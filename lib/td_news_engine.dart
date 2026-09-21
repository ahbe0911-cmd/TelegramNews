import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:io';
import 'dart:typed_data';

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
  Uint8List? previewBytes;
  /// Original photo dimensions for an uncropped Telegram-like chat preview.
  double? photoAspectRatio;

  NewsPost(this.chatId, this.id, this.date, this.source, this.username, this.body,
      this.photoId, this.photoPath,
      {this.mediaKind = 'none', this.mediaFileId, this.mediaPath, this.fileName,
       this.previewBytes, this.photoAspectRatio});

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
  /// Channel names awaiting remote resolution; do not block the settings UI.
  final pendingChannels = <String, String>{};
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
  /// Messages in the current Telegram account's Saved Messages chat.
  /// Separate from the news bookmarks, and never inserted into the news feed.
  final telegramSavedMessages = <String, NewsPost>{};
  int? telegramSavedChatId;
  bool telegramSavedBusy = false;
  bool telegramSavedHasMore = true;
  String? telegramSavedError;
  final forwardedToTelegram = <String>{};
  final forwardingToTelegram = <String>{};
  final _forwardByTemporaryId = <int, String>{};
  String? telegramForwardError;

  bool isForwardedToTelegram(NewsPost post) => forwardedToTelegram.contains(post.key);
  bool isForwardingToTelegram(NewsPost post) => forwardingToTelegram.contains(post.key);

  Future<void> _markForwarded(String key) async {
    forwardingToTelegram.remove(key);
    forwardedToTelegram.add(key);
    await prefs.setStringList('td_forwarded_to_telegram', forwardedToTelegram.toList());
    changed();
  }


  List<NewsPost> get telegramSavedFeed => telegramSavedMessages.values.toList()
    ..sort((a, b) => b.id.compareTo(a.id));

  TdNewsController(this.prefs) {
    forwardedToTelegram.addAll(prefs.getStringList('td_forwarded_to_telegram') ?? const <String>[]);
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

  Future<int> _savedChatId() async {
    if (state != 'authorizationStateReady' || bridge.sender == null) {
      throw StateError('ابتدا وارد حساب تلگرام شوید.');
    }
    if (telegramSavedChatId != null) return telegramSavedChatId!;
    final me = await bridge.request({'@type': 'getMe'});
    final myId = me['id'];
    if (myId is! int || myId <= 0) throw StateError('شناسه حساب دریافت نشد.');
    final chat = await bridge.request({
      '@type': 'createPrivateChat', 'user_id': myId, 'force': false,
    });
    final id = chat['id'];
    if (id is! int) throw StateError('Saved Messages در دسترس نیست.');
    telegramSavedChatId = id;
    return id;
  }

  bool vpnSocksWanted = false;
  bool vpnSocksInstalled = false;
  String? vpnSocksError;
  Future<void>? _vpnProxyAttempt;
  String telegramConnectionState = 'unknown';

  /// The VPN host's package is intentionally outside Android's TUN so native
  /// Xray outbound sockets cannot loop. TDLib must use Xray's local SOCKS
  /// inbound instead. Remember the request across Telegram login transitions.
  Future<void> enableSystemVpnForTelegram() {
    vpnSocksWanted = true;
    vpnSocksError = null;
    changed();
    return _applySystemVpnForTelegram();
  }

  /// Re-establish the local proxy even if the previous TDLib response was
  /// successful. A successful addProxy call alone does not prove Telegram
  /// has an active connection to its data centres.
  Future<String> repairInternalTelegramVpn() async {
    vpnSocksWanted = true;
    if (bridge.sender == null || state == 'setup' || state == 'failed' ||
        state == 'authorizationStateWaitTdlibParameters') {
      return 'موتور تلگرام هنوز آماده نیست؛ ابتدا ورود تلگرام را کامل کنید.';
    }
    final pending = _vpnProxyAttempt;
    if (pending != null) {
      try { await pending.timeout(const Duration(seconds: 8)); } catch (_) {}
    }
    vpnSocksInstalled = false;
    vpnSocksError = null;
    changed();
    try {
      await _applySystemVpnForTelegram().timeout(
          const Duration(seconds: 10));
      return await probeTelegramVpnConnection();
    } catch (_) {
      return vpnSocksError ??
          'ارتباط تلگرام با SOCKS محلی برقرار نشد؛ اتصال VPN را دوباره راه‌اندازی کنید.';
    }
  }

  /// Distinguish a live local SOCKS proxy from Telegram server connectivity.
  Future<String> probeTelegramVpnConnection() async {
    if (bridge.sender == null) {
      return 'موتور تلگرام راه‌اندازی نشده است.';
    }
    if (!vpnSocksInstalled) {
      return 'پروکسی داخلی تلگرام هنوز فعال نشده است.';
    }
    try {
      final result = await bridge.request(
          {'@type': 'getConnectionState'}).timeout(
          const Duration(seconds: 7));
      final type = result['@type']?.toString() ?? '';
      telegramConnectionState = type;
      changed();
      return switch (type) {
        'connectionStateReady' => 'تلگرام به سرور متصل است؛ خبرها را تازه‌سازی کنید.',
        'connectionStateUpdating' => 'تلگرام متصل است و در حال همگام‌سازی پیام‌هاست.',
        'connectionStateConnectingToProxy' =>
          'تلگرام در حال اتصال به پروکسی داخلی است؛ چند لحظه بعد دوباره بررسی کنید.',
        'connectionStateConnecting' =>
          'تلگرام از طریق پروکسی در حال اتصال به سرور است.',
        'connectionStateWaitingForNetwork' =>
          'تلگرام هنوز شبکه را در دسترس نمی‌بیند؛ VPN را قطع و دوباره وصل کنید.',
        _ => 'وضعیت اتصال تلگرام هنوز مشخص نیست؛ دوباره بررسی کنید.',
      };
    } catch (_) {
      return 'وضعیت سرور تلگرام دریافت نشد؛ اتصال VPN و ورود تلگرام را بررسی کنید.';
    }
  }


  Future<void> _applySystemVpnForTelegram() {
    if (!vpnSocksWanted || vpnSocksInstalled ||
        bridge.sender == null || state == 'setup' || state == 'connecting' ||
        state == 'authorizationStateWaitTdlibParameters' ||
        state == 'authorizationStateClosed') {
      return Future<void>.value();
    }
    final pending = _vpnProxyAttempt;
    if (pending != null) return pending;
    final task = _installSystemVpnProxy();
    _vpnProxyAttempt = task;
    return task.whenComplete(() { _vpnProxyAttempt = null; });
  }

  Future<void> _installSystemVpnProxy() async {
    try {
      // TDLib's addProxy call accepts loopback only when a listener exists.
      // Report local-SOCKS readiness separately from Telegram auth/server.
      final socket = await Socket.connect('127.0.0.1', 10808,
          timeout: const Duration(seconds: 2));
      try {
        // Verify an actual SOCKS5 listener, not just an unrelated open port.
        socket.add([0x05, 0x01, 0x00]);
        final reply = await socket.first.timeout(const Duration(seconds: 2));
        if (reply.length < 2 || reply[0] != 0x05 || reply[1] != 0x00) {
          throw StateError('Local SOCKS5 authentication handshake failed');
        }
      } finally {
        socket.destroy();
      }
      if (!vpnSocksWanted) return;
      // Avoid creating a duplicate proxy when reconnecting after a stop or
      // app restart. TDLib keeps local proxy entries in its database.
      final existing = await bridge.request({'@type': 'getProxies'});
      final known = existing['proxies'];
      int? proxyId;
      if (known is List) {
        for (final item in known.whereType<Map>()) {
          if (item['server'] == '127.0.0.1' && item['port'] == 10808 &&
              item['id'] is int) {
            proxyId = item['id'] as int;
            break;
          }
        }
      }
      if (proxyId == null) {
        final response = await bridge.request({
          '@type': 'addProxy', 'server': '127.0.0.1', 'port': 10808,
          'enable': true, 'type': {
            '@type': 'proxyTypeSocks5', 'username': '', 'password': '',
          },
        });
        if (response['@type'] != 'proxy' || response['id'] is! int) {
          throw StateError('TDLib proxy response is invalid');
        }
      } else {
        await bridge.request({'@type': 'enableProxy', 'proxy_id': proxyId});
      }
      if (!vpnSocksWanted) {
        await bridge.request({'@type': 'disableProxy'});
        return;
      }
      vpnSocksInstalled = true;
      vpnSocksError = null;
      changed();
      // Notifier exposes an intermediate state; Telegram may still be
      // connecting to its remote data centres.
      unawaited(probeTelegramVpnConnection());
    } catch (error) {
      vpnSocksInstalled = false;
      vpnSocksError = error is SocketException || error is TimeoutException
          ? 'سرویس SOCKS موتور Xray در دسترس نیست؛ VPN را قطع و دوباره وصل کنید.'
          : 'فعال‌سازی پروکسی تلگرام ناموفق بود؛ «تعمیر اتصال داخلی» را بزنید.';
      changed();
      rethrow;
    }
  }

  Future<void> disableSystemVpnForTelegram() async {
    vpnSocksWanted = false;
    vpnSocksError = null;
    telegramConnectionState = 'unknown';
    if (bridge.sender != null && vpnSocksInstalled) {
      try {
        await bridge.request({'@type': 'disableProxy'});
      } finally {
        vpnSocksInstalled = false;
        changed();
      }
    } else {
      vpnSocksInstalled = false;
      changed();
    }
  }

  /// Sends text to the actual Telegram self-chat.
  Future<void> sendTelegramSavedText(String text) async {
    final body = text.trim();
    if (body.isEmpty) throw const FormatException('متن پیام خالی است.');
    if (body.length > 4000) throw const FormatException('پیام را کوتاه‌تر کنید.');
    final id = await _savedChatId();
    final result = await bridge.request({
      '@type': 'sendMessage',
      'chat_id': id,
      'input_message_content': {
        '@type': 'inputMessageText',
        'text': {'@type': 'formattedText', 'text': body, 'entities': []},
      },
    });
    if (result['@type'] != 'message') {
      throw StateError('تلگرام پیام را نپذیرفت.');
    }
    record(result, fromTelegramSaved: true);
  }

  /// Forwards an actual news message including its media if forwardable.
  /// Pending messages are not marked saved until TDLib confirms success.
  Future<void> forwardNewsToTelegramSaved(NewsPost post) async {
    if (forwardedToTelegram.contains(post.key) ||
        forwardingToTelegram.contains(post.key)) return;
    forwardingToTelegram.add(post.key);
    telegramForwardError = null;
    changed();
    try {
      final destination = await _savedChatId();
      if (destination == post.chatId) {
        throw StateError('پیام از قبل در پیام‌های ذخیره‌شده است.');
      }
      final result = await bridge.request({
        '@type': 'forwardMessages',
        'chat_id': destination,
        'from_chat_id': post.chatId,
        'message_ids': [post.id],
        'send_copy': false,
        'remove_caption': false,
      });
      final messages = result['messages'];
      if (messages is! List || messages.isEmpty || messages.first is! Map) {
        throw StateError('تلگرام ارسال این خبر را نپذیرفت.');
      }
      final sent = Map<String, dynamic>.from(messages.first as Map);
      final state = sent['sending_state'];
      final stateType = state is Map ? state['@type'] : null;
      if (stateType == 'messageSendingStateFailed') {
        throw StateError('خبر ارسال نشد.');
      }
      if (stateType == 'messageSendingStatePending') {
        final tempId = sent['id'];
        if (tempId is! int) throw StateError('شناسه ارسال دریافت نشد.');
        _forwardByTemporaryId[tempId] = post.key;
      } else {
        await _markForwarded(post.key);
      }
      record(sent, fromTelegramSaved: true);
    } catch (_) {
      forwardingToTelegram.remove(post.key);
      telegramForwardError = 'ذخیره خبر در تلگرام ناموفق بود؛ دوباره تلاش کنید.';
      changed();
      rethrow;
    }
  }

  Future<void> _appendSavedHistory(Map<String, dynamic> response,
      {required bool older}) async {
    final messages = response['messages'];
    if (messages is! List) return;
    final before = telegramSavedMessages.length;
    for (final raw in messages) {
      if (raw is Map) {
        record(Map<String, dynamic>.from(raw),
            fromTelegramSaved: true, notify: false);
      }
    }
    if (messages.isNotEmpty) {
      telegramSavedHasMore = messages.length >= 20 &&
          (!older || telegramSavedMessages.length > before);
    }
    changed();
  }

  Future<void> loadTelegramSavedMessages({bool older = false}) async {
    if (telegramSavedBusy || (older && !telegramSavedHasMore)) return;
    telegramSavedBusy = true;
    telegramSavedError = null;
    changed();
    try {
      final id = await _savedChatId();
      final current = telegramSavedFeed;
      final fromId = older && current.isNotEmpty ? current.last.id : 0;
      if (!older && current.isEmpty) {
        // Render existing TDLib on-device messages while the network request
        // runs. Network fetch does not block the first visible chat bubbles.
        try {
          final cached = await bridge.request({
            '@type': 'getChatHistory', 'chat_id': id,
            'from_message_id': 0, 'offset': 0,
            'limit': 20, 'only_local': true,
          }).timeout(const Duration(seconds: 4));
          await _appendSavedHistory(cached, older: false);
        } catch (_) { /* No local cache yet; continue with network. */ }
      }
      final response = await bridge.request({
        '@type': 'getChatHistory',
        'chat_id': id, 'from_message_id': fromId,
        'offset': 0, 'limit': 20, 'only_local': false,
      });
      await _appendSavedHistory(response, older: older);
    } catch (_) {
      telegramSavedError = telegramSavedMessages.isEmpty
          ? 'دریافت پیام‌ها با تأخیر روبه‌رو شد؛ اتصال تلگرام را بررسی کنید.'
          : null;
      changed();
    } finally {
      telegramSavedBusy = false;
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
      // IMPORTANT: do not disable an active local SOCKS proxy installed
      // while TDLib parameters / authorization were loading. This used to
      // undo the app's own VPN proxy after Android reported VPN running.
      if (parametersSetup != null) await parametersSetup;
      if (vpnSocksWanted) {
        unawaited(_applySystemVpnForTelegram().catchError((Object _) {}));
      } else {
        try { await bridge.request({'@type': 'disableProxy'}); } catch (_) {}
        vpnSocksInstalled = false;
      }
    } catch (_) {
      state = 'failed';
      status = 'راه‌اندازی TDLib ناموفق بود؛ تنظیمات یا کتابخانه بومی را بررسی کنید.';
      changed();
    }
  }

  void onEvent(Map<String, dynamic> event) {
    switch (event['@type']) {
      case 'updateConnectionState':
        final connection = event['state'];
        if (connection is Map) {
          telegramConnectionState =
              connection['@type']?.toString() ?? 'unknown';
          changed();
        }
      case 'updateAuthorizationState':
        if (event['authorization_state'] is Map) {
          unawaited(onAuthorization(Map<String, dynamic>.from(event['authorization_state'] as Map)));
        }
      case 'updateMessageSendSucceeded':
        final oldId = event['old_message_id'];
        final confirmed = event['message'];
        if (oldId is int) {
          final key = _forwardByTemporaryId.remove(oldId);
          if (key != null) unawaited(_markForwarded(key));
          if (confirmed is Map && confirmed['chat_id'] == telegramSavedChatId) {
            telegramSavedMessages.remove(confirmed['chat_id'].toString() + ':' +
                oldId.toString());
            record(Map<String, dynamic>.from(confirmed), fromTelegramSaved: true);
          }
        }
      case 'updateMessageSendFailed':
        final oldId = event['old_message_id'];
        if (oldId is int) {
          final key = _forwardByTemporaryId.remove(oldId);
          if (key != null) {
            forwardingToTelegram.remove(key);
            telegramForwardError = 'ذخیره خبر در تلگرام ناموفق بود؛ دوباره تلاش کنید.';
            changed();
          }
        }
      case 'updateNewMessage':
        if (event['message'] is Map) {
          final message = Map<String, dynamic>.from(event['message'] as Map);
          record(message, fromTelegramSaved:
              telegramSavedChatId != null && message['chat_id'] == telegramSavedChatId);
        }
      case 'updateMessageContent':
        final key = event['chat_id'].toString() + ':' + event['message_id'].toString();
        final savedMessage = telegramSavedMessages[key];
        final previous = posts[key] ?? savedMessage;
        if (previous != null && event['new_content'] is Map) {
          record({
            'chat_id': previous.chatId,
            'id': previous.id,
            'date': previous.date,
            'content': event['new_content'],
          }, fromTelegramSaved: savedMessage != null);
        }
      case 'updateDeleteMessages':
        if (event['is_permanent'] == true && event['message_ids'] is List) {
          for (final id in event['message_ids'] as List) {
            final key = event['chat_id'].toString() + ':' + id.toString();
            posts.remove(key);
            telegramSavedMessages.remove(key);
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
    } else if (state != 'authorizationStateReady' &&
        state != 'authorizationStateWaitTdlibParameters' && vpnSocksWanted) {
      // Phone/code/password authorization must also use the local proxy.
      unawaited(_applySystemVpnForTelegram().catchError((Object _) {}));
    } else if (state == 'authorizationStateReady') {
      // VPN may already be running when this account logs in.
      // Apply SOCKS without holding back cached feed rendering.
      if (vpnSocksWanted) {
        unawaited(_applySystemVpnForTelegram().catchError((Object _) {}));
      }
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

  /// Queue discovery immediately. A slow Telegram search must not freeze the
  /// add-channel button or make users wait for the 40-second request timeout.
  Future<void> addChannel(String raw) async {
    if (state != 'authorizationStateReady') {
      throw StateError('ابتدا وارد تلگرام شوید.');
    }
    final name = parsePublicUsername(raw);
    if (name == null) {
      throw FormatException('آدرس کانال باید مانند t.me/channelname باشد.');
    }
    if (sources.values.any((source) =>
        source.username.toLowerCase() == name.toLowerCase())) return;
    if (pendingChannels[name] == 'در حال شناسایی کانال…') return;
    pendingChannels[name] = 'در حال شناسایی کانال…';
    status = 'کانال @$name در صف بررسی تلگرام قرار گرفت.';
    changed();
    unawaited(_resolveChannel(name));
  }

  Future<void> _resolveChannel(String name) async {
    try {
      final chat = await bridge.request({
        '@type': 'searchPublicChat', 'username': name,
      });
      if (disposed || !pendingChannels.containsKey(name)) return;
      final type = chat['type'];
      if (type is! Map || type['@type'] != 'chatTypeSupergroup' ||
          type['is_channel'] != true) {
        throw StateError('این آدرس کانال عمومی نیست.');
      }
      final id = chat['id'];
      if (id is! int) throw StateError('شناسه کانال معتبر نیست.');
      sources[id] = NewsSource(id, name, chat['title']?.toString() ?? name);
      await persist();
      pendingChannels.remove(name);
      _sortedFeed = null;
      status = 'کانال @$name به منابع خبری اضافه شد.';
      changed();
      unawaited(loadHistory(id, limit: 12, onlyLocal: true));
      unawaited(_joinAndWarm(id));
    } catch (_) {
      if (disposed || !pendingChannels.containsKey(name)) return;
      pendingChannels[name] =
          'ارتباط با تلگرام برقرار نشد؛ برای تلاش دوباره لمس کنید.';
      changed();
    }
  }

  void retryChannel(String name) {
    if (!pendingChannels.containsKey(name) ||
        pendingChannels[name] == 'در حال شناسایی کانال…') return;
    pendingChannels[name] = 'در حال شناسایی کانال…';
    changed();
    unawaited(_resolveChannel(name));
  }

  void cancelPendingChannel(String name) {
    pendingChannels.remove(name);
    changed();
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

  void record(Map<String, dynamic> message,
      {bool notify = true, bool fromTelegramSaved = false}) {
    final chatId = message['chat_id'];
    final messageId = message['id'];
    if (chatId is! int || messageId is! int ||
        (!fromTelegramSaved && !sources.containsKey(chatId)) ||
        (fromTelegramSaved && chatId != telegramSavedChatId) ||
        message['content'] is! Map) return;
    final source = fromTelegramSaved
        ? NewsSource(chatId, '', 'پیام‌های ذخیره‌شده تلگرام')
        : sources[chatId]!;
    final content = mediaContent(Map<String, dynamic>.from(message['content'] as Map));
    int? fileId;
    int? mediaFileId;
    String? fileName;
    String? cachedPreviewPath;
    double? photoAspectRatio;
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
          if (rank < previewRank) {
            previewRank = rank;
            fileId = id;
            final local = photo['local'];
            cachedPreviewPath = local is Map &&
                    local['is_downloading_completed'] == true &&
                    local['path'] is String &&
                    (local['path'] as String).isNotEmpty
                ? local['path'] as String : null;
            if (width > 0 && height > 0) {
              photoAspectRatio = width / height;
            }
          }
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
    final media = content['photo'] ?? content['video'] ??
        content['video_note'] ?? content['animation'] ?? content['document'];
    final miniature = media is Map ? media['minithumbnail'] : null;
    final encoded = miniature is Map ? miniature['data'] : null;
    if (encoded is String && encoded.isNotEmpty && encoded.length < 120000) {
      try { previewBytes = base64Decode(encoded); } catch (_) {}
    }
    final key = chatId.toString() + ':' + messageId.toString();
    final target = fromTelegramSaved ? telegramSavedMessages : posts;
    final prior = target[key];
    target[key] = NewsPost(chatId, messageId, message['date'] as int? ?? 0,
        source.title, source.username, messageText(content), fileId,
        cachedPreviewPath ?? (prior?.photoId == fileId ? prior?.photoPath : null),
        mediaKind: mediaKind,
        mediaFileId: mediaFileId,
        mediaPath: prior?.mediaFileId == mediaFileId ? prior?.mediaPath : null,
        fileName: fileName,
        previewBytes: previewBytes ?? prior?.previewBytes,
        photoAspectRatio: photoAspectRatio ?? prior?.photoAspectRatio);
    if (!fromTelegramSaved) _sortedFeed = null;
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
    for (final key in photoTargets[id] ?? <String>{}) {
      posts[key]?.photoPath = path;
      telegramSavedMessages[key]?.photoPath = path;
    }
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
