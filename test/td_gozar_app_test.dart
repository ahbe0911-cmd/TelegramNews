import 'dart:async';

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
    // The requested live neon animation continuously ticks by design.
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('گذر'), findsWidgets);
    expect(find.byKey(const ValueKey('gozar-power')), findsOneWidget);
    expect(find.byKey(const ValueKey('gozar-config')), findsNothing);
    expect(find.byKey(const ValueKey('gozar-choose-apps')), findsNothing);
    expect(find.text('خانه'), findsOneWidget);
    expect(find.text('سرورها'), findsOneWidget);
    expect(find.text('تنظیمات'), findsOneWidget);
    await tester.tap(find.text('سرورها'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const ValueKey('gozar-config')), findsOneWidget);
    await tester.tap(find.text('تنظیمات'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const ValueKey('gozar-choose-apps')), findsOneWidget);
    expect(find.byKey(const ValueKey('gozar-vpn-settings')), findsWidgets);
    await tester.tap(find.text('خانه'));
    await tester.pump(const Duration(milliseconds: 250));
    // Home uses the large animated power button; manual config and action
    // row live on the Servers page rather than cluttering the home view.
    expect(find.byKey(const ValueKey('gozar-power')), findsOneWidget);
    expect(find.byKey(const ValueKey('gozar-config')), findsNothing);
    expect(find.text('پیام‌های من'), findsNothing);
    expect(find.text('افزودن کانال عمومی'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('real proxy probe is separate from VPN service state',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    var nativeStage = 'running';
    var probeCalls = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemVpnBridge.channel, (call) async {
      if (call.method == 'status') {
        return {'stage': nativeStage, 'detail': nativeStage};
      }
      if (call.method == 'measureConnection') {
        probeCalls++;
        return {'ok': true, 'latencyMs': 63};
      }
      if (call.method == 'stop') {
        nativeStage = 'off';
        return null;
      }
      if (call.method == 'networkCounters') return {'rx': 100, 'tx': 100};
      return null;
    });
    addTearDown(() =>
        messenger.setMockMethodCallHandler(SystemVpnBridge.channel, null));
    await tester.pumpWidget(GozarApp(
        preferences: await SharedPreferences.getInstance()));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const ValueKey('gozar-real-connection-result')),
        findsNothing);
    await tester.tap(find.byKey(const ValueKey('gozar-test-real-connection')));
    await tester.pump(const Duration(milliseconds: 250));
    expect(probeCalls, 1);
    expect(find.textContaining('63 ms'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('gozar-power')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('gozar-real-connection-result')),
        findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('failed proxy probe never reports verified connectivity',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemVpnBridge.channel, (call) async {
      if (call.method == 'status') {
        return {'stage': 'running', 'detail': 'tunnel active'};
      }
      if (call.method == 'measureConnection') {
        return {'ok': false, 'latencyMs': null};
      }
      if (call.method == 'networkCounters') return {'rx': 100, 'tx': 100};
      return null;
    });
    addTearDown(() =>
        messenger.setMockMethodCallHandler(SystemVpnBridge.channel, null));
    await tester.pumpWidget(GozarApp(
        preferences: await SharedPreferences.getInstance()));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.byKey(const ValueKey('gozar-test-real-connection')));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.textContaining('آزمون اتصال موفق نبود'), findsOneWidget);
    expect(find.textContaining('آزمون اتصال سرور موفق'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a late native status cannot revive a stopped VPN',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final stale = Completer<Map<String, String>>();
    var nativeStage = 'running';
    var reads = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemVpnBridge.channel, (call) async {
      if (call.method == 'status') {
        reads++;
        if (reads == 2) return stale.future;
        return {'stage': nativeStage, 'detail': nativeStage};
      }
      if (call.method == 'stop') {
        nativeStage = 'off';
        return null;
      }
      if (call.method == 'networkCounters') return {'rx': 100, 'tx': 100};
      return null;
    });
    addTearDown(() =>
        messenger.setMockMethodCallHandler(SystemVpnBridge.channel, null));
    await tester.pumpWidget(GozarApp(
        preferences: await SharedPreferences.getInstance()));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('برای قطع اتصال لمس کنید'), findsOneWidget);
    await tester.tap(find.byTooltip('به‌روزرسانی وضعیت'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(const ValueKey('gozar-power')));
    await tester.pump(const Duration(milliseconds: 400));
    stale.complete({'stage': 'running', 'detail': 'outdated'});
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('VPN خاموش است.'), findsWidgets);
    expect(find.text('برای اتصال لمس کنید'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final initialStage in ['starting', 'running']) {
    testWidgets('power button stops native VPN while $initialStage',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      var nativeStage = initialStage;
      var stopCalls = 0;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemVpnBridge.channel, (call) async {
        if (call.method == 'status') {
          return {'stage': nativeStage, 'detail': nativeStage};
        }
        if (call.method == 'stop') {
          stopCalls++;
          nativeStage = 'off';
          return null;
        }
        if (call.method == 'networkCounters') return {'rx': 100, 'tx': 100};
        return null;
      });
      addTearDown(() =>
          messenger.setMockMethodCallHandler(SystemVpnBridge.channel, null));
      await tester.pumpWidget(GozarApp(
          preferences: await SharedPreferences.getInstance()));
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('برای قطع اتصال لمس کنید'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('gozar-power')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(stopCalls, 1);
      expect(find.text('VPN خاموش است.'), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

}
