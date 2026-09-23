import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamsi_date/shamsi_date.dart';

import 'gozar_dashboard_clock.dart';
import 'gozar_notes_store.dart';
import 'gozar_visuals.dart';

const _weekdays = <String>['ش', 'ی', 'د', 'س', 'چ', 'پ', 'ج'];

class GozarNotesScreen extends StatefulWidget {
  final SharedPreferences preferences;
  final VoidCallback onChanged;
  const GozarNotesScreen({
    super.key, required this.preferences, required this.onChanged,
  });

  @override
  State<GozarNotesScreen> createState() => _GozarNotesScreenState();
}

class _GozarNotesScreenState extends State<GozarNotesScreen> {
  late List<GozarNote> notes;
  late Jalali selected;
  late Jalali month;
  String alarmHint = '';
  int serial = 0;

  @override
  void initState() {
    super.initState();
    notes = GozarNotesStore.load(widget.preferences);
    selected = Jalali.fromDateTime(DateTime.now());
    month = Jalali(selected.year, selected.month);
  }

  void notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)));
  }

  Future<bool> save(List<GozarNote> updated) async {
    final ok = await GozarNotesStore.save(widget.preferences, updated);
    if (!mounted) return false;
    if (!ok) {
      notice('ذخیره یادداشت انجام نشد؛ دوباره امتحان کنید.');
      return false;
    }
    setState(() { notes = updated; });
    widget.onChanged();
    return true;
  }

  void goToToday() {
    final now = Jalali.fromDateTime(DateTime.now());
    setState(() {
      selected = now;
      month = Jalali(now.year, now.month);
    });
  }

  void shiftMonth(int difference) {
    final next = month.addMonths(difference);
    setState(() {
      month = Jalali(next.year, next.month);
      selected = Jalali(next.year, next.month,
        selected.day.clamp(1, next.monthLength));
    });
  }

  Future<void> configureNote({GozarNote? existing}) async {
    if (existing == null && notes.length >= GozarNotesStore.maxNotes) {
      notice('حداکثر ۴۰۰ یادداشت می‌توان ذخیره کرد.');
      return;
    }
    // Let Flutter own both form controllers until the sheet transition ends.
    var title = existing?.title ?? '';
    var body = existing?.body ?? '';
    var withAlarm = existing?.reminderAt != null;
    final original = existing?.reminderAt == null ? null :
        DateTime.fromMillisecondsSinceEpoch(existing!.reminderAt!);
    var time = original == null ? TimeOfDay.now() :
        TimeOfDay(hour: original.hour, minute: original.minute);
    final confirmed = await showModalBottomSheet<bool>(
      context: context, backgroundColor: GozarPalette.navy,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, update) => SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(17, 12, 17,
                MediaQuery.viewInsetsOf(sheetContext).bottom + 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  const Icon(Icons.edit_note_rounded,
                      color: GozarPalette.cyan, size: 26),
                  const SizedBox(width: 7),
                  Expanded(child: Text(existing == null
                      ? 'یادداشت تازه' : 'ویرایش یادداشت',
                    style: const TextStyle(color: GozarPalette.text,
                      fontSize: 18, fontWeight: FontWeight.bold))),
                  IconButton(onPressed: () =>
                      Navigator.pop(sheetContext, false),
                    icon: const Icon(Icons.close_rounded)),
                ]),
                Text(gozarJalaliLabel(selected),
                  style: const TextStyle(color: GozarPalette.muted)),
                const SizedBox(height: 11),
                TextFormField(
                  key: const ValueKey('gozar-note-title'),
                  initialValue: title,
                  autofocus: true, maxLength: 80,
                  onChanged: (value) { title = value; },
                  decoration: const InputDecoration(
                    labelText: 'عنوان یادداشت',
                    hintText: 'برای این روز چه برنامه‌ای داری؟'),
                ),
                TextFormField(
                  key: const ValueKey('gozar-note-body'),
                  initialValue: body, minLines: 2, maxLines: 5,
                  maxLength: 5000,
                  onChanged: (value) { body = value; },
                  decoration: const InputDecoration(
                    labelText: 'متن یادداشت', alignLabelWithHint: true),
                ),
                SwitchListTile(
                  key: const ValueKey('gozar-note-reminder-switch'),
                  title: const Text('یادآوری با اعلان گوشی'),
                  subtitle: const Text('حتی وقتی گذر بسته است'),
                  value: withAlarm,
                  onChanged: (value) =>
                      update(() { withAlarm = value; }),
                ),
                if (withAlarm)
                  OutlinedButton.icon(
                    key: const ValueKey('gozar-note-pick-time'),
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: sheetContext, initialTime: time);
                      if (picked != null) {
                        update(() { time = picked; });
                      }
                    },
                    icon: const Icon(Icons.alarm_rounded),
                    label: Text('ساعت ' +
                      persianDigits(time.hour.toString().padLeft(2, '0')) +
                      ':' +
                      persianDigits(time.minute.toString().padLeft(2, '0'))),
                  ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  key: const ValueKey('gozar-note-save'),
                  onPressed: () {
                    if (title.trim().isEmpty) {
                      ScaffoldMessenger.of(sheetContext).showSnackBar(
                        const SnackBar(content: Text(
                            'عنوان یادداشت را وارد کنید.')));
                      return;
                    }
                    if (withAlarm) {
                      final day = gozarGregorianDay(selected);
                      final at = DateTime(day.year, day.month, day.day,
                          time.hour, time.minute);
                      if (!at.isAfter(DateTime.now())) {
                        ScaffoldMessenger.of(sheetContext).showSnackBar(
                          const SnackBar(content: Text(
                              'زمان یادآوری باید در آینده باشد.')));
                        return;
                      }
                    }
                    Navigator.pop(sheetContext, true);
                  },
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('ذخیره یادداشت'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted || confirmed != true) return;
    final day = gozarGregorianDay(selected);
    final newAlarm = withAlarm ?
        DateTime(day.year, day.month, day.day, time.hour, time.minute)
            .millisecondsSinceEpoch : null;
    final note = GozarNote(
      id: existing?.id ??
          DateTime.now().microsecondsSinceEpoch.toString() +
          '-' + (serial++).toString(),
      day: existing?.day ?? gozarDayKey(day),
      title: title.trim(), body: body.trim(),
      reminderAt: newAlarm, done: existing?.done ?? false,
    );
    final updated = [...notes];
    final index = updated.indexWhere((item) => item.id == note.id);
    if (index < 0) { updated.add(note); }
    else { updated[index] = note; }
    if (!await save(updated)) return;
    if (existing?.reminderAt != null &&
        existing!.reminderAt != newAlarm) {
      try { await GozarReminderBridge.cancel(note.id); } catch (_) {}
    }
    if (newAlarm != null && !note.done) {
      try {
        var granted = await GozarReminderBridge.notificationsGranted();
        if (!granted) granted = await GozarReminderBridge.requestNotifications();
        if (!granted) {
          notice('یادداشت ذخیره شد، ولی مجوز اعلان خاموش است. '
              'برای زنگ یادآوری، اجازه اعلان گذر را فعال کنید.');
          setState(() { alarmHint = 'مجوز اعلان گوشی غیرفعال است'; });
        } else {
          final mode = await GozarReminderBridge.schedule(note);
          if (!mounted) return;
          setState(() {
            alarmHint = mode == 'exact'
                ? 'زنگ دقیق فعال است' : 'اعلان با زمان تقریبی فعال است';
          });
          if (mode != 'exact') {
            notice('یادداشت ذخیره شد؛ برای زنگ دقیق، مجوز «هشدارها و '
                'یادآوری‌ها» را از تنظیمات اندروید فعال کنید.');
          }
        }
      } catch (_) {
        notice('یادداشت ذخیره شد، اما زمان‌بندی اعلان انجام نشد. '
            'مجوزهای اعلان را بررسی کنید و دوباره ذخیره کنید.');
      }
    }
  }

  Future<void> deleteNote(GozarNote note) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('حذف یادداشت'),
        content: Text('«' + note.title + '» حذف شود؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false),
              child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true),
              child: const Text('حذف')),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    if (!await save(
        notes.where((n) => n.id != note.id).toList())) return;
    try { await GozarReminderBridge.cancel(note.id); } catch (_) {
      notice('یادداشت حذف شد اما لغو زنگ گوشی تأیید نشد.');
    }
  }

  Future<void> toggleDone(GozarNote note, bool done) async {
    final updated = [
      for (final item in notes)
        if (item.id == note.id) item.copyWith(done: done)
        else item,
    ];
    if (!await save(updated)) return;
    if (done && note.reminderAt != null) {
      try { await GozarReminderBridge.cancel(note.id); } catch (_) {}
    } else if (!done && note.reminderAt != null &&
        note.reminderAt! > DateTime.now().millisecondsSinceEpoch) {
      try { await GozarReminderBridge.schedule(note); } catch (_) {
        notice('برای فعال‌کردن دوباره یادآور، یادداشت را ویرایش و ذخیره کنید.');
      }
    }
  }

  Widget calendar() {
    final start = Jalali(month.year, month.month);
    final weekdayOffset = start.weekDay - 1; // Saturday = 1.
    final count = start.monthLength;
    final currentKey = gozarDayKey(DateTime.now());
    final daysWithNotes = notes.map((note) => note.day).toSet();
    return Container(
      key: const ValueKey('gozar-notes-calendar'),
      margin: const EdgeInsets.fromLTRB(11, 8, 11, 7),
      padding: const EdgeInsets.fromLTRB(9, 9, 9, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [
          Color(0xff173c5f), Color(0xff0b1f3a)]),
        border: Border.all(color: GozarPalette.cyan.withOpacity(.35)),
        borderRadius: BorderRadius.circular(23),
      ),
      child: Column(children: [
        Row(children: [
          IconButton(
            key: const ValueKey('gozar-notes-prev-month'),
            onPressed: () => shiftMonth(-1),
            icon: const Icon(Icons.chevron_right_rounded,
              color: GozarPalette.cyan)),
          Expanded(child: Column(children: [
            Text(gozarMonthNames[month.month - 1] + ' ' +
                persianDigits(month.year),
              style: const TextStyle(color: GozarPalette.text,
                fontWeight: FontWeight.w800, fontSize: 18)),
            const Text('تقویم هجری شمسی',
              style: TextStyle(color: GozarPalette.muted, fontSize: 10)),
          ])),
          TextButton(
            key: const ValueKey('gozar-notes-today'),
            onPressed: goToToday, child: const Text('امروز')),
          IconButton(
            key: const ValueKey('gozar-notes-next-month'),
            onPressed: () => shiftMonth(1),
            icon: const Icon(Icons.chevron_left_rounded,
              color: GozarPalette.cyan)),
        ]),
        const SizedBox(height: 7),
        Row(children: [
          for (final day in _weekdays)
            Expanded(child: Center(child: Text(day,
              style: TextStyle(color: day == 'ج'
                  ? GozarPalette.red : GozarPalette.muted,
                fontSize: 12, fontWeight: FontWeight.bold)))),
        ]),
        for (var row = 0; row < (weekdayOffset + count + 6) ~/ 7; row++)
          Row(children: [
            for (var column = 0; column < 7; column++)
              Expanded(child: Builder(builder: (context) {
                final day = row * 7 + column - weekdayOffset + 1;
                if (day < 1 || day > count) {
                  return const SizedBox(height: 47);
                }
                final date = Jalali(month.year, month.month, day);
                final key = gozarDayKey(gozarGregorianDay(date));
                final chosen = selected.year == date.year &&
                    selected.month == date.month && selected.day == day;
                final today = key == currentKey;
                return InkWell(
                  key: ValueKey('gozar-notes-day-' + key),
                  onTap: () => setState(() { selected = date; }),
                  borderRadius: BorderRadius.circular(13),
                  child: Container(
                    height: 47,
                    decoration: BoxDecoration(
                      color: chosen ? GozarPalette.cyan :
                          today ? const Color(0xff214d6b) : null,
                      border: today && !chosen ?
                          Border.all(color: GozarPalette.cyan) : null,
                      borderRadius: BorderRadius.circular(13)),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(persianDigits(day),
                          style: TextStyle(
                            color: chosen ? const Color(0xff071a2c) :
                                column == 6 ? GozarPalette.red :
                                GozarPalette.text,
                            fontSize: 13,
                            fontWeight: chosen ? FontWeight.w900 :
                                FontWeight.w500)),
                        if (daysWithNotes.contains(key))
                          Container(width: 5, height: 5,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: chosen ? const Color(0xff071a2c) :
                                  GozarPalette.cyan)),
                      ],
                    ),
                  ),
                );
              })),
          ]),
      ]),
    );
  }

  Widget dailyList() {
    final dayNotes = GozarNotesStore.forDay(
        notes, gozarGregorianDay(selected));
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.event_note_rounded,
              color: GozarPalette.cyan, size: 22),
          const SizedBox(width: 7),
          Expanded(child: Text(gozarJalaliLabel(selected),
            style: const TextStyle(color: GozarPalette.text,
              fontWeight: FontWeight.w800))),
          FilledButton.icon(
            key: const ValueKey('gozar-notes-add'),
            onPressed: () => configureNote(),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('یادداشت'),
          ),
        ]),
        if (alarmHint.isNotEmpty)
          Text(alarmHint, style: const TextStyle(
            color: GozarPalette.muted, fontSize: 10)),
        if (dayNotes.isEmpty) Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(19),
          decoration: BoxDecoration(
            color: const Color(0xff102c49),
            borderRadius: BorderRadius.circular(20)),
          child: const Column(children: [
            Icon(Icons.edit_calendar_rounded,
              color: GozarPalette.cyan, size: 36),
            SizedBox(height: 7),
            Text('برای این روز هنوز یادداشتی نداری.',
              style: TextStyle(color: GozarPalette.muted)),
          ]),
        ),
        for (final note in dayNotes)
          Container(
            key: ValueKey('gozar-note-' + note.id),
            margin: const EdgeInsets.only(top: 9),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xff153450),
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color:
                  GozarPalette.blue.withOpacity(.36))),
            child: Row(children: [
              Checkbox(
                key: ValueKey('gozar-note-done-' + note.id),
                value: note.done,
                onChanged: (value) => toggleDone(note, value == true)),
              Expanded(child: InkWell(
                onTap: () => configureNote(existing: note),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(note.title,
                      style: TextStyle(color: GozarPalette.text,
                        decoration: note.done ?
                            TextDecoration.lineThrough : null,
                        fontWeight: FontWeight.w700)),
                    if (note.body.isNotEmpty)
                      Text(note.body, maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: GozarPalette.muted, fontSize: 11)),
                    if (note.reminderAt != null)
                      Text('⏰ ' + persianDigits(
                            DateTime.fromMillisecondsSinceEpoch(
                              note.reminderAt!).hour.toString()
                                .padLeft(2, '0')) + ':' +
                          persianDigits(DateTime.fromMillisecondsSinceEpoch(
                            note.reminderAt!).minute.toString()
                                .padLeft(2, '0')),
                        style: const TextStyle(
                          color: GozarPalette.cyan, fontSize: 11)),
                  ],
                ),
              )),
              IconButton(
                key: ValueKey('gozar-note-edit-' + note.id),
                tooltip: 'ویرایش یادداشت',
                onPressed: () => configureNote(existing: note),
                icon: const Icon(Icons.edit_outlined,
                    color: GozarPalette.cyan, size: 19)),
              IconButton(
                key: ValueKey('gozar-note-delete-' + note.id),
                tooltip: 'حذف یادداشت',
                onPressed: () => deleteNote(note),
                icon: const Icon(Icons.delete_outline_rounded,
                    color: GozarPalette.red, size: 19)),
            ]),
          ),
        const SizedBox(height: 11),
        OutlinedButton.icon(
          key: const ValueKey('gozar-notes-exact-alarm-settings'),
          onPressed: () async {
            try {
              await GozarReminderBridge.openExactAlarmSettings();
            } catch (_) {
              notice('صفحه مجوز یادآورهای دقیق در گوشی پیدا نشد.');
            }
          },
          icon: const Icon(Icons.alarm_on_rounded, size: 18),
          label: const Text('مجوز زنگ دقیق در تنظیمات گوشی'),
        ),
        const Text('یادداشت‌ها فقط روی گوشی ذخیره می‌شوند؛ '
            'اعلان‌ها به مجوزها و محدودیت باتری اندروید وابسته‌اند.',
          style: TextStyle(color: GozarPalette.muted, fontSize: 10)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => ListView(
    key: const ValueKey('gozar-notes-page'),
    padding: EdgeInsets.zero,
    children: [calendar(), dailyList()],
  );
}

class GozarTodayNotesWidget extends StatelessWidget {
  final SharedPreferences preferences;
  final VoidCallback onOpen;
  final ValueListenable<int> refresh;
  const GozarTodayNotesWidget({
    super.key, required this.preferences,
    required this.onOpen, required this.refresh,
  });

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: refresh,
    builder: (context, revision, child) {
      final today = DateTime.now();
      final notes = GozarNotesStore.forDay(
          GozarNotesStore.load(preferences), today);
      final remaining = notes.where((note) => !note.done).toList();
      final upcoming = remaining.where((note) =>
          note.reminderAt != null &&
          note.reminderAt! > today.millisecondsSinceEpoch).toList()
        ..sort((a, b) => a.reminderAt!.compareTo(b.reminderAt!));
      final jalali = Jalali.fromDateTime(today);
      return InkWell(
        key: const ValueKey('gozar-home-notes-widget'),
        onTap: onOpen,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          margin: const EdgeInsets.only(bottom: 11),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [
              Color(0xff173a5b), Color(0xff10233d)]),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: GozarPalette.cyan.withOpacity(.38))),
          child: Row(children: [
            Container(
              width: 51, height: 59,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                color: const Color(0xff235978)),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(persianDigits(jalali.day),
                    style: const TextStyle(
                      color: GozarPalette.text,
                      fontSize: 21, fontWeight: FontWeight.w900)),
                  Text(gozarMonthNames[jalali.month - 1],
                    style: const TextStyle(
                      color: GozarPalette.cyan, fontSize: 9)),
                ]),
            ),
            const SizedBox(width: 11),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('یادداشت‌های امروز',
                  style: TextStyle(color: GozarPalette.text,
                    fontSize: 14, fontWeight: FontWeight.w800)),
                Text(remaining.isEmpty
                    ? 'برای امروز یادداشتی نداری'
                    : persianDigits(remaining.length) + ' کار باقی‌مانده · ' +
                      remaining.first.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: GozarPalette.muted, fontSize: 11)),
                if (upcoming.isNotEmpty)
                  Text('یادآوری بعدی: ' + persianDigits(
                    DateTime.fromMillisecondsSinceEpoch(
                        upcoming.first.reminderAt!).hour
                          .toString().padLeft(2, '0')) + ':' +
                    persianDigits(DateTime.fromMillisecondsSinceEpoch(
                        upcoming.first.reminderAt!).minute
                          .toString().padLeft(2, '0')),
                    style: const TextStyle(
                      color: GozarPalette.cyan, fontSize: 10)),
              ],
            )),
            const Icon(Icons.chevron_left_rounded,
                color: GozarPalette.cyan),
          ]),
        ),
      );
    },
  );
}
