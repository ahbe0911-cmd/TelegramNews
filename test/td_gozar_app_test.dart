import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:telegram_news/gozar_main.dart';
import 'package:telegram_news/gozar_notes_store.dart';
import 'package:telegram_news/gozar_vpn.dart';

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
    messenger.setMockMethodCallHandler(
        GozarVpnBridge.channel, (call) async {
      if (call.method == 'status') {
        return <String, dynamic>{
          'stage': 'off',
          'detail': 'VPN خاموش است.',
        };
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(
          GozarReminderBridge.channel, null);
      messenger.setMockMethodCallHandler(
          GozarVpnBridge.channel, null);
    });
  }

  testWidgets('Gozar starts on Home and has exactly three main tabs',
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
    expect(
      navigation.destinations
          .map((item) => (item as NavigationDestination).label),
      isNot(contains('VPN')),
    );
  });

  testWidgets('VPN exists only inside Settings with a circular power control',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await configureChannels();

    await tester.pumpWidget(GozarApp(
      preferences: await SharedPreferences.getInstance(),
    ));
    await tester.pump(const Duration(milliseconds: 250));

    await tester.tap(find.text('تنظیمات'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const ValueKey('gozar-settings-page')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('gozar-settings-vpn-card')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('gozar-settings-vpn-power')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('gozar-vpn-status-dot')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('gozar-vpn-add-account')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('gozar-vpn-add-subscription')),
        findsOneWidget);
    expect(find.text('Xray-core 26.9.9'), findsOneWidget);
    expect(find.textContaining('WireGuard'), findsNothing);

    final navigation =
        tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(
      navigation.destinations
          .map((item) => (item as NavigationDestination).label)
          .toList(),
      <String>['خانه', 'یادداشت', 'تنظیمات'],
    );
  });

  testWidgets('Notes remain available beside Settings VPN', (tester) async {
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
    expect(find.byKey(const ValueKey('gozar-settings-open-home')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('gozar-settings-vpn-card')),
        findsOneWidget);
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
    messenger.setMockMethodCallHandler(
        GozarVpnBridge.channel, (call) async {
      if (call.method == 'status') {
        return <String, dynamic>{
          'stage': 'off',
          'detail': 'VPN خاموش است.',
        };
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(
          GozarReminderBridge.channel, null);
      messenger.setMockMethodCallHandler(
          GozarVpnBridge.channel, null);
    });

    await tester.pumpWidget(GozarApp(
      preferences: await SharedPreferences.getInstance(),
    ));
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byKey(const ValueKey('gozar-notes-calendar')),
        findsOneWidget);
  });
}
