import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegram_news/gozar_main.dart';
import 'package:telegram_news/gozar_notes_store.dart';
import 'package:telegram_news/gozar_shortcuts.dart';
import 'package:telegram_news/td_system_vpn.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Gozar keeps standalone VPN, notes and settings with new social tab',
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
    expect(find.text('شبکه‌های اجتماعی'), findsOneWidget);
    expect(find.byKey(const ValueKey('gozar-social-pages')), findsNothing);
    expect(find.text('یادداشت'), findsOneWidget);
    expect(find.text('تنظیمات'), findsOneWidget);
    expect(find.byKey(const ValueKey('gozar-home-notes-widget')),
        findsNothing);
    expect(find.byKey(const ValueKey('gozar-user-shortcut-grid')),
        findsNothing);
    await tester.tap(find.text('یادداشت'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const ValueKey('gozar-notes-calendar')),
        findsOneWidget);
    await tester.tap(find.text('تنظیمات'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const ValueKey('gozar-choose-apps')), findsOneWidget);
    expect(find.byKey(const ValueKey('gozar-open-servers-settings')),
        findsOneWidget);
    await tester.tap(find.byKey(
        const ValueKey('gozar-open-servers-settings')));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const ValueKey('gozar-config')), findsOneWidget);
    await tester.tap(find.byKey(
        const ValueKey('gozar-back-to-settings')));
    await tester.pump(const Duration(milliseconds: 250));
    // VPN options remain in Settings; server management is a nested card.
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
  testWidgets('home displays only notes due on this date, not future alarms',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final today = gozarDayKey(now);
    final tomorrow = gozarDayKey(now.add(const Duration(days: 1)));
    expect(await GozarNotesStore.save(preferences, [
      GozarNote(id: 'due', day: today,
        title: 'یادآوری رسیده', body: '',
        reminderAt: now.subtract(const Duration(minutes: 5))
            .millisecondsSinceEpoch),
      GozarNote(id: 'future', day: today,
        title: 'یادآوری بعدی', body: '',
        reminderAt: now.add(const Duration(minutes: 25))
            .millisecondsSinceEpoch),
      GozarNote(id: 'tomorrow', day: tomorrow,
        title: 'فردا', body: ''),
    ]), isTrue);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemVpnBridge.channel, (call) async {
      if (call.method == 'status') {
        return {'stage': 'off', 'detail': 'off'};
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(
        SystemVpnBridge.channel, null));
    await tester.pumpWidget(GozarApp(preferences: preferences));
    await tester.pump(const Duration(milliseconds: 350));
    final card = find.byKey(const ValueKey('gozar-home-due-notes'));
    await tester.scrollUntilVisible(card, 150,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('gozar-home')),
        matching: find.byType(Scrollable),
      ).first,
    );
    expect(card, findsOneWidget);
    expect(find.text('یادآوری رسیده'), findsOneWidget);
    expect(find.text('یادآوری بعدی'), findsNothing);
    expect(find.text('فردا'), findsNothing);
    expect(find.byKey(const ValueKey('gozar-user-shortcut-grid')),
        findsNothing);
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
    expect(find.byKey(const ValueKey('gozar-user-shortcut-grid')),
        findsNothing);
    await tester.tap(find.text('تنظیمات'));
    await tester.pump(const Duration(milliseconds: 250));
    final shortcut = find.byKey(ValueKey('gozar-manage-shortcut-' +
        selected.key));
    await tester.ensureVisible(shortcut);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.tap(find.text('برنامه من').last);
    await tester.pump(const Duration(milliseconds: 150));
    expect(launchArgs?['package'], 'com.example.installed');
    expect(launchArgs?['component'], 'com.example.installed.LauncherAlias');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('editing a saved shortcut preserves its Android launcher',
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
    // Shortcut management is first in Settings, above the fixed bottom bar.
    await tester.ensureVisible(rename);
    await tester.pump(const Duration(milliseconds: 250));
    expect(rename, findsOneWidget);
    await tester.tap(rename);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(
        find.byKey(const ValueKey('gozar-edit-shortcut-name')), 'اینستاگرام من');
    await tester.tap(find.byKey(const ValueKey('gozar-apply-shortcut-name')));
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.text('اینستاگرام من'), findsOneWidget);
    final shortcut = find.byKey(ValueKey('gozar-manage-shortcut-' +
        selected.key));
    await tester.ensureVisible(shortcut);
    await tester.pump(const Duration(milliseconds: 220));
    await tester.tap(find.text('اینستاگرام من').last);
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
