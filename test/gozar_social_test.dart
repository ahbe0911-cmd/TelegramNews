import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_news/gozar_social.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Network contains only Rubika, Shad and Eitaa, in requested order', () {
    expect(gozarSocialSites.map((s) => s.name).toList(),
      ['روبیکا', 'شاد', 'ایتا']);
    expect(gozarSocialSites.map((s) => s.domain).toList(),
      ['web.rubika.ir', 'my.shad.ir', 'web.eitaa.com']);
    expect(gozarSocialSites.map((s) => s.domain).toSet().length, 3);
  });

  testWidgets('Network switches without horizontal swipe or recreating pages',
      (tester) async {
    final calls = <MethodCall>[];
    final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel =
      MethodChannel('ir.channel.telegram_tdnews/gozar_social_controls');
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: GozarSocialTab(
        active: true,
        pageBuilder: (index) => Container(
          key: ValueKey('mock-network-page-' + index.toString()),
          alignment: Alignment.center,
          child: Text('صفحهٔ وب ' + index.toString()),
        ),
      ),
    )));
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byKey(const ValueKey('gozar-social-header')), findsOneWidget);
    expect(find.byKey(const ValueKey('gozar-social-pages')), findsOneWidget);
    expect(find.byType(PageView), findsNothing);
    expect(find.byKey(const ValueKey('mock-network-page-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('mock-network-page-2')), findsNothing);
    expect(find.text('تلگرام'), findsNothing);
    final header = tester.getRect(find.byKey(const ValueKey('gozar-social-header')));
    final body = tester.getRect(find.byKey(const ValueKey('gozar-social-content')));
    expect(header.height, 53);
    expect((body.top - header.bottom).abs(), lessThan(1));
    final first = find.byKey(const ValueKey('gozar-social-select-0'));
    final last = find.byKey(const ValueKey('gozar-social-select-2'));
    expect(tester.getCenter(first).dx, greaterThan(tester.getCenter(last).dx));
    await tester.tap(find.byKey(const ValueKey('gozar-social-select-1')));
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byKey(const ValueKey('mock-network-page-1')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('gozar-social-select-2')));
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byKey(const ValueKey('mock-network-page-2')), findsOneWidget);
    await tester.tap(first);
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byKey(const ValueKey('mock-network-page-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('mock-network-page-1'),
      skipOffstage: false), findsOneWidget);
    expect(find.byKey(const ValueKey('mock-network-page-2'),
      skipOffstage: false), findsOneWidget);
    expect(calls.any((c) => c.method == 'setActive' &&
      (c.arguments as Map)['index'] == 1), isTrue);
    await tester.tap(find.byKey(const ValueKey('gozar-social-options')));
    await tester.pumpAndSettle();
    expect(find.text('افزودن MTProto'), findsNothing);
    expect(find.text('اتصال خودکار و VPN گوشی'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
