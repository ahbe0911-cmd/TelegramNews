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

  test('home note card shows only this day and only once alarm time arrives',
      () {
    final now = DateTime(2026, 10, 17, 9, 30);
    final today = gozarDayKey(now);
    final tomorrow = gozarDayKey(now.add(const Duration(days: 1)));
    final yesterday = gozarDayKey(now.subtract(const Duration(days: 1)));
    final morning = DateTime(2026, 10, 17, 9, 0).millisecondsSinceEpoch;
    final future = DateTime(2026, 10, 17, 9, 45).millisecondsSinceEpoch;
    final notes = [
      GozarNote(id: 'done', day: today,
        title: 'انجام شده', body: '', done: true),
      GozarNote(id: 'untimed', day: today,
        title: 'کار روز', body: ''),
      GozarNote(id: 'due', day: today,
        title: 'زنگ امروز', body: '', reminderAt: morning),
      GozarNote(id: 'later', day: today,
        title: 'هنوز زود است', body: '', reminderAt: future),
      GozarNote(id: 'tomorrow', day: tomorrow,
        title: 'برنامه فردا', body: ''),
      GozarNote(id: 'old', day: yesterday,
        title: 'برنامه دیروز', body: ''),
    ];
    final visible = GozarNotesStore.dueForHome(notes, now);
    expect(visible.map((n) => n.id), containsAll(['untimed', 'due']));
    expect(visible.map((n) => n.id),
        isNot(contains(anyOf('done', 'later', 'tomorrow', 'old'))));
    expect(GozarNotesStore.dueForHome(notes,
        DateTime(2026, 10, 17, 9, 44))
        .any((n) => n.id == 'later'), isFalse);
    expect(GozarNotesStore.dueForHome(notes,
        DateTime(2026, 10, 17, 9, 45))
        .any((n) => n.id == 'later'), isTrue);
    expect(GozarNotesStore.dueForHome(notes,
        DateTime(2026, 10, 18, 0, 0))
        .any((n) => n.id == 'due'), isFalse);
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

  testWidgets('Saturday is rightmost, Friday leftmost on Persian calendar',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    // Use the normal LTR test host to guard against accidental locale flips.
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: GozarNotesScreen(
        preferences: prefs, onChanged: () {}),
    )));
    await tester.pump(const Duration(milliseconds: 200));
    final saturday =
        find.byKey(const ValueKey('gozar-notes-weekday-0'));
    final friday =
        find.byKey(const ValueKey('gozar-notes-weekday-6'));
    expect(saturday, findsOneWidget);
    expect(friday, findsOneWidget);
    expect(tester.getCenter(saturday).dx,
        greaterThan(tester.getCenter(friday).dx));
    final calendar = find.byKey(const ValueKey('gozar-notes-calendar'));
    expect(
      tester.widget<Directionality>(
        find.ancestor(of: calendar, matching: find.byType(Directionality)).first)
          .textDirection,
      TextDirection.rtl,
    );
    final jalali = Jalali.fromDateTime(DateTime.now());
    final first = Jalali(jalali.year, jalali.month, 1);
    final dayOne = find.byKey(ValueKey(
      'gozar-notes-day-' +
          gozarDayKey(gozarGregorianDay(first))));
    await tester.ensureVisible(dayOne);
    expect(dayOne, findsOneWidget);
    if (first.weekDay == 1) {
      expect(tester.getCenter(dayOne).dx,
          greaterThan(tester.getCenter(friday).dx));
    }
    await tester.tap(dayOne);
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text(gozarJalaliLabel(first)), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
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
    final saveButton = find.byKey(const ValueKey('gozar-note-save'));
    await tester.ensureVisible(saveButton);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(saveButton);
    await tester.pump(const Duration(milliseconds: 450));
    expect(GozarNotesStore.load(prefs).single.title, 'قرار کتابخانه');
    expect(revisions, 1);
    final saved = GozarNotesStore.load(prefs).single;
    final done = find.byKey(ValueKey('gozar-note-done-' + saved.id));
    // The redesigned calendar can push the day's notes below the viewport
    // on a small phone; scroll the outer list until the note is built.
    await tester.scrollUntilVisible(done, 175,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('gozar-notes-page')),
        matching: find.byType(Scrollable),
      ).first,
    );
    await tester.pump(const Duration(milliseconds: 170));
    await tester.tap(done);
    await tester.pump(const Duration(milliseconds: 250));
    expect(GozarNotesStore.load(prefs).single.done, isTrue);
    expect(revisions, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
