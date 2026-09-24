import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_news/gozar_social.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('web messenger order and trusted HTTPS domains are fixed', () {
    expect(gozarSocialSites.map((s) => s.name).toList(),
      ['تلگرام', 'بله', 'روبیکا', 'ایتا']);
    expect(gozarSocialSites.map((s) => s.domain).toList(),
      ['web.telegram.org', 'web.bale.ai',
       'web.rubika.ir', 'web.eitaa.com']);
    expect(gozarSocialSites.map((s) => s.domain).toSet().length, 4);
  });

  testWidgets('social swipe is RTL, lazy, and keeps all four pages',
      (tester) async {
    final controls = <String>[];
    final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel =
      MethodChannel('ir.channel.telegram_tdnews/gozar_social_controls');
    messenger.setMockMethodCallHandler(channel, (call) async {
      controls.add(call.method);
      return null;
    });
    addTearDown(() =>
      messenger.setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: GozarSocialTab(
        active: true,
        pageBuilder: (index) => Container(
          key: ValueKey('mock-social-page-' + index.toString()),
          alignment: Alignment.center,
          child: Text('صفحهٔ وب ' + index.toString()),
        ),
      ),
    )));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('gozar-social-pages')), findsOneWidget);
    expect(find.byKey(const ValueKey('gozar-social-header')), findsOneWidget);
    expect(find.text('شبکه‌های اجتماعی'), findsNothing);
    expect(find.textContaining('صفحه را افقی'), findsNothing);
    expect(find.byKey(const ValueKey('gozar-social-options')), findsOneWidget);
    final header = tester.getRect(
        find.byKey(const ValueKey('gozar-social-header')));
    final content = tester.getRect(
        find.byKey(const ValueKey('gozar-social-content')));
    expect(header.height, 53);
    expect(content.top, header.bottom);
    expect(content.bottom,
        tester.getRect(find.byType(Scaffold)).bottom);
    expect(content.left, 0);
    expect(find.byKey(const ValueKey('mock-social-page-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('mock-social-page-2')), findsNothing);
    expect(tester.widget<Directionality>(
      find.ancestor(
        of: find.byKey(const ValueKey('gozar-social-pages')),
        matching: find.byType(Directionality),
      ).first,
    ).textDirection, TextDirection.rtl);
    final telegram =
      find.byKey(const ValueKey('gozar-social-select-0'));
    final eitaa =
      find.byKey(const ValueKey('gozar-social-select-3'));
    expect(tester.getCenter(telegram).dx,
        greaterThan(tester.getCenter(eitaa).dx));
    await tester.tap(find.byKey(
      const ValueKey('gozar-social-select-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('gozar-social-select-1')), findsOneWidget);
    expect(tester.widget<AnimatedContainer>(find.descendant(
      of: find.byKey(const ValueKey('gozar-social-select-1')),
      matching: find.byType(AnimatedContainer),
    )).decoration, isNotNull);
    expect(find.byKey(const ValueKey('mock-social-page-1')), findsOneWidget);
    // In a right-to-left PageView, the next page sits to the LEFT
    // of the current one; drag right to bring it into view.
    await tester.drag(
      find.byKey(const ValueKey('gozar-social-pages')),
      const Offset(500, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('روبیکا'), findsOneWidget);
    expect(find.byKey(const ValueKey('mock-social-page-2')), findsOneWidget);
    await tester.tap(find.byKey(
      const ValueKey('gozar-social-select-3')));
    await tester.pumpAndSettle();
    expect(find.text('ایتا'), findsOneWidget);
    expect(find.byKey(const ValueKey('mock-social-page-3')), findsOneWidget);
    expect(controls, contains('setActive'));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
