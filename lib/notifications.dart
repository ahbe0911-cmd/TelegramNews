import 'dart:async';
import 'dart:typed_data';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

final localNotifications = FlutterLocalNotificationsPlugin();
const notificationInit = InitializationSettings(
    android: AndroidInitializationSettings('ic_stat_news'));

@pragma('vm:entry-point')
Future<void> backgroundMessage(RemoteMessage message) async {
  await Firebase.initializeApp();
  await localNotifications.initialize(notificationInit);
  await displayMessage(message);
}

Future<void> displayMessage(RemoteMessage message) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs
      .reload(); // the background isolate must see current user preferences
  final d = message.data;
  if (!(prefs.getBool('notifications') ?? true)) return;
  if ((prefs.getBool('important') ?? false) && d['important'] != 'true') return;
  final id = int.tryParse(d['postId'] ?? '');
  if (id == null) return;
  final quiet = quietNow(DateTime.now(), prefs.getBool('quiet') ?? false,
      prefs.getInt('start') ?? 1320, prefs.getInt('end') ?? 480);
  Uint8List? bytes;
  final image = Uri.tryParse(d['image'] ?? '');
  if (image != null && image.scheme == 'https') {
    try {
      final response =
          await http.get(image).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200 &&
          response.bodyBytes.length < 5 * 1024 * 1024)
        bytes = response.bodyBytes;
    } catch (_) {/* A missing image must never prevent a text notification. */}
  }
  final bitmap = bytes == null ? null : ByteArrayAndroidBitmap(bytes);
  await localNotifications.show(
      id,
      d['title'] ?? 'خبر جدید',
      d['body'] ?? '',
      NotificationDetails(
          android: AndroidNotificationDetails(
        quiet ? 'news_quiet_v1' : 'news_sound_v1',
        quiet ? 'خبرهای بی‌صدا' : 'خبرهای کانال',
        channelDescription: 'آخرین پست‌های کانال',
        importance: quiet ? Importance.low : Importance.high,
        priority: quiet ? Priority.low : Priority.high,
        playSound: !quiet,
        enableVibration: !quiet,
        sound: quiet ? null : const RawResourceAndroidNotificationSound('news'),
        largeIcon: bitmap,
        styleInformation: bitmap == null
            ? BigTextStyleInformation(d['body'] ?? '')
            : BigPictureStyleInformation(bitmap,
                contentTitle: d['title'], summaryText: d['body']),
      )),
      payload: '$id');
}

class PushService {
  final void Function(String) open;
  final void Function(String) status;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  PushService(this.open, this.status);
  Future<void> start() async {
    await localNotifications.initialize(notificationInit,
        onDidReceiveNotificationResponse: (response) {
      if (response.payload != null) open(response.payload!);
    });
    final launch = await localNotifications.getNotificationAppLaunchDetails();
    if ((launch?.didNotificationLaunchApp ?? false) &&
        launch?.notificationResponse?.payload != null)
      open(launch!.notificationResponse!.payload!);
    final permission = await FirebaseMessaging.instance.requestPermission();
    if (permission.authorizationStatus == AuthorizationStatus.denied) {
      status('مجوز اعلان در تنظیمات اندروید خاموش است');
    } else {
      status('اعلان‌ها متصل هستند');
    }
    _subscriptions.add(FirebaseMessaging.onMessage.listen((message) {
      unawaited(displayMessage(message));
    }));
    _subscriptions.add(FirebaseMessaging.onMessageOpenedApp.listen((message) {
      if (message.data['postId'] != null) open(message.data['postId']!);
    }));
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial?.data['postId'] != null) open(initial!.data['postId']!);
    await FirebaseMessaging.instance.subscribeToTopic('channel_news');
    _subscriptions.add(FirebaseMessaging.instance.onTokenRefresh.listen((_) {
      unawaited(FirebaseMessaging.instance
          .subscribeToTopic('channel_news')
          .catchError((Object _) {
        status('اتصال اعلان نیاز به تلاش مجدد دارد');
      }));
    }));
  }

  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
  }
}
