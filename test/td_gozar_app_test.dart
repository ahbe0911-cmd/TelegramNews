import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegram_news/gozar_main.dart';
import 'package:telegram_news/gozar_shortcuts.dart';
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
    final dial = find.byKey(const ValueKey('gozar-clock-dial'));
    expect(dial, findsOneWidget);
    final dialRect = tester.getRect(dial);
    final powerRect = tester.getRect(
        find.byKey(const ValueKey('gozar-power')));
    expect((dialRect.width - powerRect.width).abs(), lessThan(1.0));
    expect((dialRect.top - powerRect.top).abs(), lessThan(1.0));
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
    // Settings is a lazy, scrollable page: the Android VPN section may
    // initially be below the fold now that shortcut management is above it.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('gozar-vpn-settings')),
      220,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('gozar-settings-page')),
        matching: find.byType(Scrollable),
      ).first,
    );
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
  testWidgets('tap user shortcut launches selected Android alias',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    const selected = GozarShortcut(
      kind: 'app', target: 'com.example.installed',
      title: 'برنامه من',
      component: 'com.example.installed.LauncherAlias');
    expect(await GozarShortcutStore.save(preferences, [selected]), isTrue);
    Map<dynamic, dynamic>? launchArgs;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemVpnBridge.channel, (call) async {
      if (call.method == 'status') {
        return {'stage': 'off', 'detail': 'off'};
      }
      if (call.method == 'appIcon') return null;
      if (call.method == 'openShortcutApp') {
        launchArgs = Map<dynamic, dynamic>.from(call.arguments as Map);
        return null;
      }
      return null;
    });
    addTearDown(() =>
        messenger.setMockMethodCallHandler(SystemVpnBridge.channel, null));
    await tester.pumpWidget(GozarApp(preferences: preferences));
    await tester.pump(const Duration(milliseconds: 350));
    final shortcut = find.byKey(
        const ValueKey('gozar-shortcut-app:com.example.installed:com.example.installed.LauncherAlias'));
    await tester.ensureVisible(shortcut);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.tap(shortcut);
    await tester.pump(const Duration(milliseconds: 150));
    expect(launchArgs?['package'], 'com.example.installed');
    expect(launchArgs?['component'], 'com.example.installed.LauncherAlias');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('editing a shortcut name updates home without changing launcher',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    const selected = GozarShortcut(
      kind: 'app', target: 'com.example.installed',
      title: 'Instagram',
      component: 'com.example.installed.LauncherAlias');
    expect(await GozarShortcutStore.save(preferences, [selected]), isTrue);
    Map<dynamic, dynamic>? opened;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemVpnBridge.channel, (call) async {
      if (call.method == 'status') {
        return {'stage': 'off', 'detail': 'off'};
      }
      if (call.method == 'appIcon') return null;
      if (call.method == 'openShortcutApp') {
        opened = Map<dynamic, dynamic>.from(call.arguments as Map);
      }
      return null;
    });
    addTearDown(() =>
        messenger.setMockMethodCallHandler(SystemVpnBridge.channel, null));
    await tester.pumpWidget(GozarApp(preferences: preferences));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byKey(const ValueKey('gozar-shortcut-search')), findsNothing);
    expect(find.textContaining('با گذر، فراتر'), findsNothing);
    await tester.tap(find.text('تنظیمات'));
    await tester.pump(const Duration(milliseconds: 250));
    final rename = find.byKey(ValueKey('gozar-rename-' + selected.key));
    await tester.scrollUntilVisible(rename, 180,
      // Position controls above the fixed bottom navigation bar: merely
      // revealing them at the viewport bottom makes taps hit the nav bar.
      alignment: 0.25,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('gozar-settings-page')),
        matching: find.byType(Scrollable),
      ).first,
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(rename);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(
        find.byKey(const ValueKey('gozar-edit-shortcut-name')), 'اینستاگرام من');
    await tester.tap(find.byKey(const ValueKey('gozar-apply-shortcut-name')));
    await tester.pump(const Duration(milliseconds: 450));
    await tester.tap(find.text('خانه'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('اینستاگرام من'), findsOneWidget);
    final shortcut = find.byKey(ValueKey('gozar-shortcut-' + selected.key));
    await tester.ensureVisible(shortcut);
    await tester.tap(shortcut);
    await tester.pump(const Duration(milliseconds: 150));
    expect(opened?['package'], selected.target);
    expect(opened?['component'], selected.component);
    expect(GozarShortcutStore.load(preferences).single.title,
        'اینستاگرام من');
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
    await tester.ensureVisible(find.byKey(const ValueKey('gozar-test-real-connection')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const ValueKey('gozar-test-real-connection')));
    await tester.pump(const Duration(milliseconds: 250));
    expect(probeCalls, 1);
    expect(find.textContaining('63 ms'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('gozar-power')));
    await tester.pump(const Duration(milliseconds: 100));
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
    await tester.ensureVisible(find.byKey(const ValueKey('gozar-test-real-connection')));
    await tester.pump(const Duration(milliseconds: 100));
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
