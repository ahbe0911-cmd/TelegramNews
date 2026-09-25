import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:telegram_news/gozar_telegram_web.dart';

void main() {
  testWidgets('single official Telegram Web tab uses light full-height shell',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(
      body: GozarTelegramWeb(
        active: true,
        testWebPage: SizedBox.expand(
          key: ValueKey('gozar-test-telegram-web'),
          child: ColoredBox(color: Colors.white)),
      ),
    )));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('gozar-telegram-header')),
        findsOneWidget);
    expect(find.text('web.telegram.org'), findsOneWidget);
    expect(find.byKey(const ValueKey('gozar-test-telegram-web')),
        findsOneWidget);
    final header = tester.getRect(
        find.byKey(const ValueKey('gozar-telegram-header')));
    final web = tester.getRect(
        find.byKey(const ValueKey('gozar-test-telegram-web')));
    expect(header.height, 45);
    expect((web.top - header.bottom).abs(), lessThan(1));
    expect(web.height, greaterThan(400));
    expect(find.text('بله'), findsNothing);
    expect(find.text('روبیکا'), findsNothing);
    expect(find.text('ایتا'), findsNothing);
    expect(find.byKey(const ValueKey('gozar-social-pages')),
        findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Telegram Web exposes font toggle and validated external MTProto',
      (tester) async {
    final calls = <MethodCall>[];
    const native = MethodChannel(
        'ir.channel.telegram_tdnews/gozar_telegram_controls');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(native, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(native, null));
    await tester.pumpWidget(const MaterialApp(home: Scaffold(
      body: GozarTelegramWeb(
        active: true, testWebPage: SizedBox.expand(),
      ),
    )));
    await tester.pump(const Duration(milliseconds: 130));
    await tester.tap(find.byKey(const ValueKey('gozar-telegram-options')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('استفاده از فونت اصلی سایت'));
    await tester.pump(const Duration(milliseconds: 140));
    expect(calls.any((call) => call.method == 'setFontEnabled' &&
        (call.arguments as Map)['enabled'] == false), isTrue);
    await tester.tap(find.byKey(const ValueKey('gozar-telegram-options')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('افزودن MTProto در برنامه تلگرام'));
    await tester.pumpAndSettle();
    expect(find.textContaining('روی تلگرام وب'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('gozar-mtproto-confirm')));
    await tester.pump(const Duration(milliseconds: 140));
    expect(calls.where((call) =>
        call.method == 'openMtprotoInTelegram'), isEmpty);
    await tester.enterText(find.byKey(
      const ValueKey('gozar-mtproto-server')), 'proxy.example.org');
    await tester.enterText(find.byKey(
      const ValueKey('gozar-mtproto-secret')), '0123456789abcdef0123456789abcdef');
    await tester.tap(find.byKey(const ValueKey('gozar-mtproto-confirm')));
    await tester.pumpAndSettle();
    final linked = calls.where((call) =>
        call.method == 'openMtprotoInTelegram').toList();
    expect(linked.length, 1);
    expect((linked.single.arguments as Map)['server'], 'proxy.example.org');
    expect((linked.single.arguments as Map)['port'], 443);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('MTProto link import accepts only valid official proxy URLs', () {
    const secret = '0123456789abcdef0123456789abcdef';
    expect(gozarValidMtprotoLink(
      'tg://proxy?server=proxy.example.org&port=443&secret=$secret'), isTrue);
    expect(gozarValidMtprotoLink(
      'https://t.me/proxy?server=proxy.example.org&port=443&secret=$secret'),
      isTrue);
    expect(gozarValidMtprotoLink(
      'https://t.me.evil.example/proxy?server=proxy.example.org&port=443&secret=$secret'),
      isFalse);
    expect(gozarValidMtprotoLink('https://t.me/proxy?server=x&port=0&secret=$secret'),
      isFalse);
    expect(gozarValidMtprotoLink('tg://proxy?server=x&port=443&secret=invalid'),
      isFalse);
  });

  testWidgets('channel proxy link handoff validates input and opens native Telegram',
      (tester) async {
    final calls = <MethodCall>[];
    const native = MethodChannel(
        'ir.channel.telegram_tdnews/gozar_telegram_controls');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(native, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(native, null));
    await tester.pumpWidget(const MaterialApp(home: Scaffold(
      body: GozarTelegramWeb(active: true, testWebPage: SizedBox.expand()),
    )));
    await tester.pump(const Duration(milliseconds: 130));
    await tester.tap(find.byKey(const ValueKey('gozar-telegram-options')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('افزودن MTProto از لینک کانال'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('gozar-mtproto-link-confirm')));
    await tester.pump();
    expect(find.text('لینک MTProto معتبر وارد کنید.'), findsOneWidget);
    expect(calls.where((call) => call.method == 'openMtprotoLink'), isEmpty);
    const link = 'https://t.me/proxy?server=proxy.example.org&port=443'
        '&secret=0123456789abcdef0123456789abcdef';
    await tester.enterText(find.byKey(const ValueKey('gozar-mtproto-link')), link);
    await tester.tap(find.byKey(const ValueKey('gozar-mtproto-link-confirm')));
    await tester.pumpAndSettle();
    final linked = calls.where((call) => call.method == 'openMtprotoLink').toList();
    expect(linked.length, 1);
    expect((linked.single.arguments as Map)['url'], link);
    await tester.pumpWidget(const SizedBox.shrink());
  });

}
