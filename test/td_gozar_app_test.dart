import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:telegram_news/gozar_main.dart';
import 'package:telegram_news/gozar_notes_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> configureChannels() async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        GozarReminderBridge.channel, (call) async {
      if (call.method == 'takeOpenedReminder') return false;
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(
          GozarReminderBridge.channel, null);
    });
  }

  testWidgets('Rosha starts on Home and has exactly three main tabs',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await configureChannels();

    await tester.pumpWidget(GozarApp(
      preferences: await SharedPreferences.getInstance(),
    ));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byKey(const ValueKey('gozar-home-motivation')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('gozar-home-motivation-text')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('gozar-launcher-top-toolbar')),
        findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(3));

    final navigation =
        tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(
      navigation.destinations
          .map((item) => (item as NavigationDestination).label)
          .toList(),
      <String>['خانه', 'یادداشت', 'تنظیمات'],
    );

    expect(find.text('VPN'), findsNothing);
    expect(find.textContaining('Xray'), findsNothing);
    expect(find.textContaining('WireGuard'), findsNothing);
    expect(find.byKey(const ValueKey('gozar-settings-vpn-card')),
        findsNothing);
  });

  testWidgets('Notes and Settings remain available with VPN removed',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await configureChannels();

    await tester.pumpWidget(GozarApp(
      preferences: await SharedPreferences.getInstance(),
    ));
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.text('یادداشت'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const ValueKey('gozar-notes-calendar')),
        findsOneWidget);

    await tester.tap(find.text('تنظیمات'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const ValueKey('gozar-settings-page')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('gozar-settings-open-home')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('gozar-settings-exact-alarm')),
        findsOneWidget);

    expect(find.text('VPN'), findsNothing);
    expect(find.textContaining('Xray'), findsNothing);
    expect(find.textContaining('WireGuard'), findsNothing);
  });

  testWidgets('Reminder launch opens Notes tab', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var first = true;
    messenger.setMockMethodCallHandler(
        GozarReminderBridge.channel, (call) async {
      if (call.method == 'takeOpenedReminder') {
        final value = first;
        first = false;
        return value;
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(
          GozarReminderBridge.channel, null);
    });

    await tester.pumpWidget(GozarApp(
      preferences: await SharedPreferences.getInstance(),
    ));
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byKey(const ValueKey('gozar-notes-calendar')),
        findsOneWidget);
  });
}
