import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegram_news/gozar_main.dart';
import 'package:telegram_news/td_system_vpn.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Gozar is a standalone VPN screen without news or Telegram',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemVpnBridge.channel, (call) async {
      if (call.method == 'status') {
        return {'stage': 'off', 'detail': 'not connected'};
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemVpnBridge.channel, null);
    });
    await tester.pumpWidget(GozarApp(
        preferences: await SharedPreferences.getInstance()));
    await tester.pumpAndSettle();
    expect(find.text('گذر'), findsWidgets);
    expect(find.byKey(const ValueKey('gozar-config')), findsOneWidget);
    expect(find.byKey(const ValueKey('gozar-choose-apps')), findsOneWidget);
    expect(find.byKey(const ValueKey('gozar-connect')), findsOneWidget);
    expect(find.byKey(const ValueKey('gozar-disconnect')), findsOneWidget);
    expect(find.text('پیام‌های من'), findsNothing);
    expect(find.text('افزودن کانال عمومی'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
