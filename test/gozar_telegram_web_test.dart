import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
