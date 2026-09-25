import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_news/gozar_telegram_web.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Telegram retains a full-height official web page', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(
      body: GozarTelegramWeb(active: true, testWebPage: SizedBox.expand(
        key: ValueKey('gozar-test-telegram-web'))),
    )));
    await tester.pump(const Duration(milliseconds: 130));
    expect(find.byKey(const ValueKey('gozar-telegram-header')), findsOneWidget);
    expect(find.text('web.telegram.org'), findsOneWidget);
    final header = tester.getRect(
      find.byKey(const ValueKey('gozar-telegram-header')));
    final web = tester.getRect(
      find.byKey(const ValueKey('gozar-test-telegram-web')));
    expect(header.height, 45);
    expect((web.top - header.bottom).abs(), lessThan(1));
    expect(web.height, greaterThan(400));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Telegram options have no MTProto or VPN but keep font and reload',
      (tester) async {
    final calls = <MethodCall>[];
    const channel = MethodChannel(
      'ir.channel.telegram_tdnews/gozar_telegram_controls');
    final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(const MaterialApp(home: Scaffold(
      body: GozarTelegramWeb(active: true,
        testWebPage: SizedBox.expand()),
    )));
    await tester.pump(const Duration(milliseconds: 130));
    await tester.tap(find.byKey(const ValueKey('gozar-telegram-options')));
    await tester.pumpAndSettle();
    expect(find.text('افزودن MTProto از لینک کانال'), findsNothing);
    expect(find.text('افزودن MTProto در برنامه تلگرام'), findsNothing);
    expect(find.text('اتصال خودکار و VPN گوشی'), findsNothing);
    await tester.tap(find.text('استفاده از فونت فارسی گذر'));
    await tester.pump(const Duration(milliseconds: 140));
    expect(calls.any((c) => c.method == 'setFontEnabled' &&
      (c.arguments as Map)['enabled'] == true), isTrue);
    await tester.tap(find.byKey(const ValueKey('gozar-telegram-options')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('بارگذاری مجدد'));
    await tester.pump(const Duration(milliseconds: 140));
    expect(calls.any((c) => c.method == 'reload'), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
