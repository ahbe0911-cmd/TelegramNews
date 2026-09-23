import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamsi_date/shamsi_date.dart';
import 'package:telegram_news/gozar_notes_store.dart';
import 'package:telegram_news/gozar_notes_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Persian month navigation keeps valid days including Esfand', () {
    final end = Jalali(1404, 12);
    expect(end.monthLength == 29 || end.monthLength == 30, isTrue);
    final next = end.addMonths(1);
    expect(next.month, 1);
    expect(next.year, 1405);
    final day = gozarGregorianDay(end);
    expect(Jalali.fromDateTime(day).month, 12);
    expect(gozarDayKey(day), matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
  });

  test('multiple daily notes, reminder times and checked state survive restart',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final day = gozarDayKey(DateTime.now());
    final future = DateTime.now()
        .add(const Duration(days: 2)).millisecondsSinceEpoch;
    final notes = [
      GozarNote(id: '1', day: day, title: 'کار اول',
        body: 'متن', reminderAt: future),
      GozarNote(id: '2', day: day, title: 'کار دوم',
        body: '', done: true),
    ];
    expect(await GozarNotesStore.save(prefs, notes), isTrue);
    final saved = GozarNotesStore.load(prefs);
    expect(saved.length, 2);
    expect(saved.first.reminderAt, future);
    expect(saved.first.body, 'متن');
    expect(GozarNotesStore.forDay(saved, DateTime.now()).last.done, isTrue);
    final modified = saved.first.copyWith(title: 'کار ویرایش شد',
        removeReminder: true);
    expect(modified.id, saved.first.id);
    expect(modified.reminderAt, isNull);
    expect(await GozarNotesStore.save(prefs, [modified, saved.last]), isTrue);
    expect(GozarNotesStore.load(prefs).first.title, 'کار ویرایش شد');
  });

  test('invalid and malformed notes never overwrite valid saved data',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final date = gozarDayKey(DateTime.now());
    const good = GozarNote(id: 'safe', day: '2026-09-23',
      title: 'یادداشت', body: '');
    expect(await GozarNotesStore.save(prefs, [good]), isTrue);
    expect(await GozarNotesStore.save(prefs, [
      good, good,
    ]), isFalse);
    expect(await GozarNotesStore.save(prefs, [
      GozarNote(id: 'bad', day: date, title: '', body: ''),
    ]), isFalse);
    expect(GozarNotesStore.load(prefs).single.title, good.title);
    expect(GozarNote.fromJson({
      'id': 'bad', 'day': '2026-02-31', 'title': 'bad', 'body': '',
    }), isNull);
  });

  testWidgets('select Persian day, write a note, edit and check completion',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    var revisions = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: GozarNotesScreen(preferences: prefs,
        onChanged: () { revisions++; }),
    )));
    await tester.pump(const Duration(milliseconds: 180));
    expect(find.byKey(const ValueKey('gozar-notes-calendar')), findsOneWidget);
    expect(find.byKey(const ValueKey('gozar-notes-add')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('gozar-notes-add')));
    await tester.pump(const Duration(milliseconds: 320));
    await tester.enterText(find.byKey(
        const ValueKey('gozar-note-title')), 'قرار کتابخانه');
    await tester.enterText(find.byKey(
        const ValueKey('gozar-note-body')), 'تحویل کتاب');
    await tester.tap(find.byKey(const ValueKey('gozar-note-save')));
    await tester.pump(const Duration(milliseconds: 450));
    expect(GozarNotesStore.load(prefs).single.title, 'قرار کتابخانه');
    expect(revisions, 1);
    final saved = GozarNotesStore.load(prefs).single;
    await tester.ensureVisible(find.byKey(
        ValueKey('gozar-note-done-' + saved.id)));
    await tester.tap(find.byKey(
        ValueKey('gozar-note-done-' + saved.id)));
    await tester.pump(const Duration(milliseconds: 250));
    expect(GozarNotesStore.load(prefs).single.done, isTrue);
    expect(revisions, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
