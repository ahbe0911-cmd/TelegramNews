import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegram_news/gozar_shortcuts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const app = GozarShortcut(
    kind: 'app', target: 'org.telegram.messenger', title: 'تلگرام');
  const site = GozarShortcut(
    kind: 'web', target: 'https://example.org/', title: 'سایت من');

  setUp(() { SharedPreferences.setMockInitialValues({}); });

  test('starts empty: no demo or unwanted app shortcuts', () async {
    final preferences = await SharedPreferences.getInstance();
    expect(GozarShortcutStore.load(preferences), isEmpty);
  });

  test('persists actual user-selected apps and HTTPS sites in order',
      () async {
    final preferences = await SharedPreferences.getInstance();
    expect(await GozarShortcutStore.save(preferences, [site, app]), isTrue);
    final restored = GozarShortcutStore.load(preferences);
    expect(restored.map((s) => s.title).toList(), ['سایت من', 'تلگرام']);
    expect(restored.map((s) => s.kind).toList(), ['web', 'app']);
    expect(restored.last.target, 'org.telegram.messenger');
  });

  test('keeps separate Android launcher aliases and migrates old shortcuts',
      () async {
    final preferences = await SharedPreferences.getInstance();
    const main = GozarShortcut(
      kind: 'app', target: 'com.example.launcher',
      component: 'com.example.launcher.MainActivity', title: 'اصلی');
    const alias = GozarShortcut(
      kind: 'app', target: 'com.example.launcher',
      component: 'com.example.launcher.SecondActivity', title: 'دوم');
    expect(await GozarShortcutStore.save(preferences, [main, alias]), isTrue);
    final restored = GozarShortcutStore.load(preferences);
    expect(restored.length, 2);
    expect(restored.first.component, main.component);
    expect(restored.last.component, alias.component);
    await preferences.setString(GozarShortcutStore.key, jsonEncode([
      {'kind': 'app', 'target': 'com.example.legacy', 'title': 'قبلی'},
    ]));
    final legacy = GozarShortcutStore.load(preferences).single;
    expect(legacy.component, isEmpty);
    expect(legacy.target, 'com.example.legacy');
  });

  test('renaming changes only the label, retaining real app launcher', () async {
    final preferences = await SharedPreferences.getInstance();
    const original = GozarShortcut(
      kind: 'app', target: 'com.example.instagram',
      title: 'Instagram',
      component: 'com.example.instagram.LauncherAlias',
    );
    final renamed = original.renamed('  اینستاگرام من  ');
    expect(renamed.title, 'اینستاگرام من');
    expect(renamed.key, original.key);
    expect(renamed.target, original.target);
    expect(renamed.component, original.component);
    expect(await GozarShortcutStore.save(preferences, [renamed]), isTrue);
    final restored = GozarShortcutStore.load(preferences).single;
    expect(restored.title, 'اینستاگرام من');
    expect(restored.component, original.component);
  });

  test('drag reorder persists list order without changing shortcut targets',
      () async {
    final preferences = await SharedPreferences.getInstance();
    const secondApp = GozarShortcut(kind: 'app',
        target: 'com.example.second', title: 'برنامه دوم',
        component: 'com.example.second.MainActivity');
    final ordered = GozarShortcutStore.reordered([app, site, secondApp], 0, 3);
    expect(ordered.map((item) => item.key).toList(),
        [site.key, secondApp.key, app.key]);
    expect(await GozarShortcutStore.save(preferences, ordered), isTrue);
    expect(GozarShortcutStore.load(preferences)
        .map((item) => item.key).toList(),
        [site.key, secondApp.key, app.key]);
    final movedBack = GozarShortcutStore.reordered(ordered, 2, 0);
    expect(movedBack.map((item) => item.key).toList(),
        [app.key, site.key, secondApp.key]);
  });

  test('only HTTPS without embedded user credentials is accepted', () {
    expect(GozarShortcut.validWebUrl('https://example.org/search?q=test'),
        isNotNull);
    expect(GozarShortcut.validWebUrl('http://example.org'), isNull);
    expect(GozarShortcut.validWebUrl('javascript:alert(1)'), isNull);
    expect(GozarShortcut.validWebUrl('file:///etc/passwd'), isNull);
    expect(GozarShortcut.validWebUrl('https://user:secret@example.org'),
        isNull);
    expect(GozarShortcut.validWebUrl('https://'), isNull);
  });

  test('rejects duplicates and more than ten shortcuts without overwriting',
      () async {
    final preferences = await SharedPreferences.getInstance();
    expect(await GozarShortcutStore.save(preferences, [app]), isTrue);
    expect(await GozarShortcutStore.save(preferences, [app, app]), isFalse);
    final eleven = List<GozarShortcut>.generate(11, (i) =>
        GozarShortcut(kind: 'app',
          target: 'org.example.app' + i.toString(),
          title: 'برنامه ' + i.toString()));
    expect(await GozarShortcutStore.save(preferences, eleven), isFalse);
    expect(GozarShortcutStore.load(preferences).single.title, 'تلگرام');
  });

  test('malformed saved entries cannot inject unsafe shortcut targets',
      () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(GozarShortcutStore.key, jsonEncode([
      site.toJson(),
      site.toJson(),
      {'kind': 'web', 'target': 'file:///secrets', 'title': 'unsafe'},
      {'kind': 'app', 'target': '../private', 'title': 'unsafe'},
      app.toJson(),
    ]));
    final shortcuts = GozarShortcutStore.load(preferences);
    expect(shortcuts.length, 2);
    expect(shortcuts.first.title, 'سایت من');
    expect(shortcuts.last.title, 'تلگرام');
  });
}
