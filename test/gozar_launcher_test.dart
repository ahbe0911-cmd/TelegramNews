import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegram_news/gozar_launcher.dart';
import 'package:telegram_news/gozar_shortcuts.dart';
import 'package:telegram_news/td_system_vpn.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const instagram = GozarShortcut(
    kind: 'app', target: 'com.instagram.android',
    title: 'Instagram', component: 'com.instagram.android.MainActivity');
  const editor = GozarShortcut(
    kind: 'app', target: 'com.example.editor',
    title: 'ویرایشگر', component: 'com.example.editor.Launcher');

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('first install creates one editable, empty launcher section', () async {
    final prefs = await SharedPreferences.getInstance();
    final sections = GozarLauncherStore.load(prefs);
    expect(sections.length, 1);
    expect(sections.single.apps, isEmpty);
    expect(sections.single.columns, 4);
    expect(sections.single.iconSize, 72);
    expect(GozarShortcutStore.load(prefs), isEmpty);
  });

  test('section title, grid columns, icon size and Android aliases persist',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final sections = [
      const GozarLauncherSection(id: 'editing', title: 'ساخت ویدئو',
        columns: 4, iconSize: 54, apps: [instagram, editor]),
      const GozarLauncherSection(id: 'social', title: 'شبکه‌های اجتماعی',
        columns: 6, iconSize: 36, apps: [instagram]),
    ];
    expect(await GozarLauncherStore.save(prefs, sections), isTrue);
    final restored = GozarLauncherStore.load(prefs);
    expect(restored.map((s) => s.title).toList(),
        ['ساخت ویدئو', 'شبکه‌های اجتماعی']);
    expect(restored.first.columns, 4);
    expect(restored.last.columns, 4);
    expect(restored.first.iconSize, 72);
    expect(restored.last.iconSize, 72);
    expect(restored.first.apps.first.component, instagram.component);
    expect(restored.first.apps.last.target, editor.target);
    expect(GozarShortcutStore.load(prefs), isEmpty);
  });

  test('renaming launcher app preserves native package and component', () async {
    final prefs = await SharedPreferences.getInstance();
    const original = GozarLauncherSection(id: 'apps',
      title: 'برنامه‌های من', apps: [instagram, editor]);
    final renamed = original.copyWith(
      apps: [instagram.renamed('اینستاگرام شخصی'), editor]);
    expect(await GozarLauncherStore.save(prefs, [renamed]), isTrue);
    final saved = GozarLauncherStore.load(prefs).single.apps.first;
    expect(saved.title, 'اینستاگرام شخصی');
    expect(saved.target, instagram.target);
    expect(saved.component, instagram.component);
    expect(saved.key, instagram.key);
  });

  test('drag reorder saves new icon order without altering launcher target',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final moved = GozarLauncherStore.moveApp(
        [instagram, editor], editor.key, instagram.key);
    expect(moved.map((app) => app.key).toList(),
        [editor.key, instagram.key]);
    expect(moved.first.component, editor.component);
    expect(await GozarLauncherStore.save(prefs, [
      GozarLauncherSection(id: 'order', title: 'ویرایش',
        apps: moved)]), isTrue);
    expect(GozarLauncherStore.load(prefs).single.apps
        .map((app) => app.key).toList(),
        [editor.key, instagram.key]);
    expect(GozarLauncherStore.moveApp(
      moved, 'missing-app', editor.key), moved);
  });

  test('deleting the final section remains empty after app restart',
      () async {
    final prefs = await SharedPreferences.getInstance();
    expect(await GozarLauncherStore.save(prefs, []), isTrue);
    expect(GozarLauncherStore.load(prefs), isEmpty);
  });

  test('invalid section settings and duplicate apps never overwrite data',
      () async {
    final prefs = await SharedPreferences.getInstance();
    const good = GozarLauncherSection(id: 'good',
      title: 'ساخت ویدئو', apps: [instagram]);
    expect(await GozarLauncherStore.save(prefs, [good]), isTrue);
    final invalid = good.copyWith(columns: 9);
    expect(await GozarLauncherStore.save(prefs, [invalid]), isFalse);
    expect(await GozarLauncherStore.save(prefs, [
      good.copyWith(apps: [instagram, instagram]),
    ]), isFalse);
    expect(GozarLauncherStore.load(prefs).single.columns, 4);
  });

  test('malformed saved apps cannot inject nonlaunchable targets', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(GozarLauncherStore.key, jsonEncode([
      {
        'id': 'valid', 'title': 'من', 'columns': 5, 'iconSize': 60,
        'apps': [
          instagram.toJson(),
          instagram.toJson(),
          {'kind': 'web', 'target': 'https://example.org',
            'title': 'not an app'},
          {'kind': 'app', 'target': '../unsafe', 'title': 'unsafe'},
        ],
      },
    ]));
    final apps = GozarLauncherStore.load(prefs).single.apps;
    expect(apps.length, 1);
    expect(apps.single.component, instagram.component);
  });

  testWidgets('long press opens edit sheet without any three-dot button',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    const section = GozarLauncherSection(id: 'apps', title: 'برنامه‌های من',
        apps: [instagram, editor]);
    expect(await GozarLauncherStore.save(prefs, [section]), isTrue);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemVpnBridge.channel, (call) async {
      if (call.method == 'appIcon') return null;
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(
        SystemVpnBridge.channel, null));
    GozarShortcut? launched;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: GozarLauncher(preferences: prefs,
        onOpenApp: (app) async { launched = app; }),
    )));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byIcon(Icons.more_horiz_rounded), findsNothing);
    final instagramTile = find.byKey(
        ValueKey('gozar-launcher-open-' + instagram.key));
    final editorTile = find.byKey(
        ValueKey('gozar-launcher-open-' + editor.key));
    expect(instagramTile, findsOneWidget);
    await tester.longPress(instagramTile);
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('gozar-launcher-app-options-' +
        instagram.key)), findsOneWidget);
    await tester.tap(find.byKey(
        const ValueKey('gozar-launcher-action-rename')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(
        const ValueKey('gozar-launcher-app-name')), 'اینستاگرام شخصی');
    await tester.tap(find.byKey(
        const ValueKey('gozar-launcher-save-app-name')));
    await tester.pump(const Duration(milliseconds: 450));
    final savedName = GozarLauncherStore.load(prefs).single.apps.first;
    expect(savedName.title, 'اینستاگرام شخصی');
    expect(savedName.component, instagram.component);

    await tester.longPress(editorTile);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(
        const ValueKey('gozar-launcher-action-move')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('gozar-launcher-finish-reorder')),
        findsOneWidget);

    // Drag the second app onto the first app, then verify disk persistence.
    final start = tester.getCenter(find.byKey(
        ValueKey('gozar-launcher-drag-' + editor.key)));
    final destination = tester.getCenter(instagramTile);
    final drag = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 450));
    await drag.moveTo(destination);
    await tester.pump(const Duration(milliseconds: 300));
    await drag.up();
    await tester.pump(const Duration(milliseconds: 500));
    expect(GozarLauncherStore.load(prefs).single.apps
        .map((app) => app.key).toList(), [editor.key, instagram.key]);

    await tester.tap(find.byKey(
        const ValueKey('gozar-launcher-finish-reorder')));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(instagramTile);
    await tester.pump(const Duration(milliseconds: 100));
    expect(launched?.title, 'اینستاگرام شخصی');
    expect(launched?.target, instagram.target);
    expect(launched?.component, instagram.component);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('four-column launcher uses large icons and suppresses rapid double launch',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    const section = GozarLauncherSection(
      id: 'samsung-grid', title: 'برنامه‌های من', apps: [instagram]);
    expect(await GozarLauncherStore.save(prefs, [section]), isTrue);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemVpnBridge.channel, (call) async {
      if (call.method == 'appIcon') return null;
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(
        SystemVpnBridge.channel, null));
    var launches = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: SizedBox(width: 400, child: GozarLauncher(
        preferences: prefs,
        onOpenApp: (app) async {
          launches++;
          await Future<void>.delayed(const Duration(milliseconds: 80));
        },
      )),
    )));
    await tester.pump(const Duration(milliseconds: 250));
    final tile = find.byKey(
        ValueKey('gozar-launcher-open-' + instagram.key));
    final icon = find.byKey(
        ValueKey('gozar-launcher-icon-' + instagram.key));
    expect(tile, findsOneWidget);
    expect(icon, findsOneWidget);
    // The mock returns no Android artwork: the fallback glyph intentionally
    // uses 78% of the real icon width. Check the grid's four-column layout
    // separately instead of expecting the fallback glyph to fill the cell.
    final grid = tester.widget<GridView>(
        find.byKey(const ValueKey('gozar-launcher-grid-samsung-grid')));
    final delegate = grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 4);
    expect(tester.getSize(icon).width, greaterThanOrEqualTo(58));
    await tester.tap(tile);
    await tester.tap(tile);
    await tester.pump(const Duration(milliseconds: 100));
    expect(launches, 1);
    expect(find.byIcon(Icons.more_horiz_rounded), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('launcher page still adds another app after five icons',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final originalApps = List<GozarShortcut>.generate(5, (i) =>
      GozarShortcut(kind: 'app', target: 'com.example.app$i',
        title: 'App $i', component: 'com.example.app$i.Main'));
    const id = 'many-apps';
    expect(await GozarLauncherStore.save(prefs, [
      GozarLauncherSection(id: id, title: 'برنامه‌های من',
        apps: originalApps),
    ]), isTrue);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemVpnBridge.channel, (call) async {
      if (call.method == 'appIcon') return null;
      if (call.method == 'installedApps') {
        return [
          for (var i = 0; i < 6; i++) {
            'package': 'com.example.app$i',
            'label': 'App $i',
            'component': 'com.example.app$i.Main',
          },
        ];
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(
        SystemVpnBridge.channel, null));
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: GozarLauncher(
        preferences: prefs, onOpenApp: (app) async {}),
    )));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const ValueKey('gozar-launcher-add-apps')),
        findsNothing);
    expect(find.byKey(const ValueKey('gozar-launcher-grid-add-many-apps')),
        findsOneWidget);
    await tester.tap(find.byKey(
        const ValueKey('gozar-launcher-grid-add-many-apps')));
    await tester.pump(const Duration(milliseconds: 300));
    final pickSix = find.byKey(const ValueKey(
        'gozar-launcher-pick-app:com.example.app5:com.example.app5.Main'));
    await tester.enterText(find.byKey(
        const ValueKey('gozar-launcher-app-search')), 'App 5');
    await tester.pump(const Duration(milliseconds: 100));
    expect(pickSix, findsOneWidget);
    await tester.tap(pickSix);
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(find.byKey(
        const ValueKey('gozar-launcher-save-apps')));
    await tester.pump(const Duration(milliseconds: 450));
    final saved = GozarLauncherStore.load(prefs).single.apps;
    expect(saved.length, 6);
    expect(saved.last.target, 'com.example.app5');
    expect(saved.last.component, 'com.example.app5.Main');
    expect(find.byKey(const ValueKey('gozar-launcher-add-apps')),
        findsNothing);
    expect(find.byKey(const ValueKey('gozar-launcher-grid-add-many-apps')),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('launcher tab opens section dialog and saved native app',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    const section = GozarLauncherSection(
      id: 'movies', title: 'ساخت ویدئو', apps: [editor]);
    expect(await GozarLauncherStore.save(prefs, [section]), isTrue);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemVpnBridge.channel, (call) async {
      if (call.method == 'appIcon') return null;
      return null;
    });
    addTearDown(() =>
      messenger.setMockMethodCallHandler(SystemVpnBridge.channel, null));
    GozarShortcut? launched;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: GozarLauncher(preferences: prefs,
        onOpenApp: (app) async { launched = app; })),
    ));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('ساخت ویدئو'), findsOneWidget);
    expect(find.byKey(const ValueKey('gozar-launcher-pages')), findsOneWidget);
    final app = find.byKey(ValueKey('gozar-launcher-open-' + editor.key));
    await tester.tap(app);
    await tester.pump(const Duration(milliseconds: 100));
    expect(launched?.component, editor.component);
    await tester.tap(find.byKey(
        const ValueKey('gozar-launcher-section-settings')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(
        const ValueKey('gozar-launcher-inline-settings')), findsOneWidget);
    expect(find.text('چیدمان ۴ ستونه · آیکون‌های بزرگ'), findsOneWidget);
    await tester.enterText(find.byKey(
        const ValueKey('gozar-launcher-inline-name-movies')), 'گرافیک');
    await tester.tap(find.byKey(
        const ValueKey('gozar-launcher-save-inline-name')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(GozarLauncherStore.load(prefs).single.title, 'گرافیک');
    expect(GozarLauncherStore.load(prefs).single.columns, 4);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
