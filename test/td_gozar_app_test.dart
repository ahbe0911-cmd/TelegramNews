import 'dart:async';

import 'package:flutter/material.dart';
import 'package:telegram_news/gozar_visuals.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegram_news/gozar_main.dart';
import 'package:telegram_news/td_system_vpn.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Gozar is a standalone VPN screen without news or Telegram', (
    tester,
  ) async {
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
    await tester.pumpWidget(
      GozarApp(preferences: await SharedPreferences.getInstance()),
    );
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

  const secureChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  const link =
      'vless://11111111-1111-1111-1111-111111111111@example.com:443?security=tls';

  for (final pending in ['storage', 'start']) {
    testWidgets('cancel remains available during pending $pending', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final gate = Completer<void>();
      var starts = 0;
      var stops = 0;
      var nativeStage = 'off';
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(secureChannel, (call) async {
        if (call.method == 'write' && pending == 'storage') await gate.future;
        return null;
      });
      messenger.setMockMethodCallHandler(SystemVpnBridge.channel, (call) async {
        if (call.method == 'status') return {'stage': nativeStage};
        if (call.method == 'start') {
          starts++;
          nativeStage = 'starting';
          if (pending == 'start') await gate.future;
        }
        if (call.method == 'stop') {
          stops++;
          nativeStage = 'off';
        }
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(secureChannel, null);
        messenger.setMockMethodCallHandler(SystemVpnBridge.channel, null);
      });
      await tester.pumpWidget(
        GozarApp(preferences: await SharedPreferences.getInstance()),
      );
      await tester.pump();
      await tester.tap(find.text('سرورها'));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('gozar-config')), link);
      await tester.tap(find.text('خانه'));
      await tester.pump();
      GozarPowerButton power() =>
          tester.widget(find.byKey(const ValueKey('gozar-power')));
      power().onPressed!();
      await tester.pump();
      expect(power().onPressed, isNotNull);
      power().onPressed!();
      await tester.pump();
      expect(stops, 1);
      gate.complete();
      await tester.pump();
      expect(starts, pending == 'storage' ? 0 : 1);
      expect(power().busy, isFalse);
      expect(power().connected, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'native state is followed after startup and external disconnect',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      var nativeStage = 'consent';
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemVpnBridge.channel, (call) async {
        if (call.method == 'status') return {'stage': nativeStage};
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemVpnBridge.channel, null),
      );
      await tester.pumpWidget(
        GozarApp(preferences: await SharedPreferences.getInstance()),
      );
      await tester.pump();
      GozarPowerButton power() =>
          tester.widget(find.byKey(const ValueKey('gozar-power')));
      expect(power().onPressed, isNotNull);
      nativeStage = 'running';
      await tester.pump(const Duration(seconds: 20));
      await tester.pump();
      expect(power().connected, isTrue);
      nativeStage = 'off';
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(power().connected, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final size in [
    const Size(393, 852),
    const Size(360, 640),
    const Size(852, 393),
  ]) {
    testWidgets('home fits $size with no scroll or overflow', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        GozarApp(preferences: await SharedPreferences.getInstance()),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('gozar-home')),
          matching: find.byType(Scrollable),
        ),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('gozar-power')), findsOneWidget);
      expect(find.byKey(const ValueKey('gozar-tcp-latency')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
