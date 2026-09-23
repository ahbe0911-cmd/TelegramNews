import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamsi_date/shamsi_date.dart';

import 'gozar_dashboard_clock.dart';

const gozarMonthNames = <String>[
  'فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور',
  'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند',
];

String gozarDayKey(DateTime date) =>
    date.year.toString().padLeft(4, '0') + '-' +
    date.month.toString().padLeft(2, '0') + '-' +
    date.day.toString().padLeft(2, '0');

DateTime gozarGregorianDay(Jalali value) {
  final date = value.toGregorian();
  return DateTime(date.year, date.month, date.day);
}

String gozarJalaliLabel(Jalali day) =>
    persianDigits(day.day) + ' ' + gozarMonthNames[day.month - 1] +
    ' ' + persianDigits(day.year);

class GozarNote {
  final String id;
  final String day;
  final String title;
  final String body;
  final int? reminderAt;
  final bool done;

  const GozarNote({
    required this.id, required this.day, required this.title,
    required this.body, this.reminderAt, this.done = false,
  });

  GozarNote copyWith({
    String? title, String? body, bool? done, int? reminderAt,
    bool removeReminder = false,
  }) => GozarNote(
    id: id, day: day,
    title: title ?? this.title, body: body ?? this.body,
    done: done ?? this.done,
    reminderAt: removeReminder ? null : reminderAt ?? this.reminderAt,
  );

  Map<String, Object?> toJson() => {
    'id': id, 'day': day, 'title': title, 'body': body,
    'reminderAt': reminderAt, 'done': done,
  };

  static GozarNote? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id']?.toString() ?? '';
    final day = raw['day']?.toString() ?? '';
    final title = raw['title']?.toString() ?? '';
    final body = raw['body']?.toString() ?? '';
    final time = raw['reminderAt'];
    final done = raw['done'];
    if (id.isEmpty || id.length > 60 ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day) ||
        title.trim().isEmpty || title.length > 80 ||
        body.length > 5000 ||
        (time != null && (time is! int || time < 0)) ||
        (done != null && done is! bool)) return null;
    final parts = day.split('-').map(int.parse).toList();
    final parsed = DateTime(parts[0], parts[1], parts[2]);
    if (gozarDayKey(parsed) != day) return null;
    return GozarNote(
      id: id, day: day, title: title, body: body,
      reminderAt: time as int?, done: done == true,
    );
  }
}

class GozarNotesStore {
  static const key = 'gozar_local_notes_v1';
  static const maxNotes = 400;

  static List<GozarNote> load(SharedPreferences prefs) {
    try {
      final raw = prefs.getString(key);
      if (raw == null) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final result = <GozarNote>[];
      final ids = <String>{};
      for (final item in decoded) {
        final note = GozarNote.fromJson(item);
        if (note != null && ids.add(note.id)) {
          result.add(note);
          if (result.length == maxNotes) break;
        }
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  static Future<bool> save(
      SharedPreferences prefs, List<GozarNote> notes) {
    if (notes.length > maxNotes ||
        notes.map((n) => n.id).toSet().length != notes.length ||
        notes.any((n) => GozarNote.fromJson(n.toJson()) == null)) {
      return Future<bool>.value(false);
    }
    return prefs.setString(
        key, jsonEncode(notes.map((n) => n.toJson()).toList()));
  }

  static List<GozarNote> forDay(List<GozarNote> notes, DateTime date) =>
      notes.where((n) => n.day == gozarDayKey(date)).toList()
        ..sort((a, b) {
          if (a.done != b.done) return a.done ? 1 : -1;
          return (a.reminderAt ?? 0).compareTo(b.reminderAt ?? 0);
        });

  /// Home only displays today's unfinished notes. Timed notes become visible
  /// when their scheduled phone-local time arrives; future-day notes must
  /// never appear early. Untimed notes are visible throughout their date.
  static List<GozarNote> dueForHome(
      List<GozarNote> notes, DateTime now) {
    final timestamp = now.millisecondsSinceEpoch;
    return forDay(notes, now).where((note) =>
      !note.done &&
      (note.reminderAt == null || note.reminderAt! <= timestamp)
    ).toList();
  }
}

/// Android AlarmManager + NotificationManager. Independent of VPN lifecycle.
class GozarReminderBridge {
  static const channel =
      MethodChannel('ir.channel.telegram_tdnews/reminders');

  static Future<bool> notificationsGranted() async =>
      await channel.invokeMethod<bool>('notificationsGranted') ?? false;

  static Future<bool> requestNotifications() async =>
      await channel.invokeMethod<bool>('requestNotifications') ?? false;

  static Future<bool> exactAlarmsAllowed() async =>
      await channel.invokeMethod<bool>('exactAlarmsAllowed') ?? false;

  static Future<void> openExactAlarmSettings() =>
      channel.invokeMethod<void>('openExactAlarmSettings');

  /// Returns 'exact' or 'approximate'. Never assert exact if permission denied.
  static Future<String> schedule(GozarNote note) async =>
      await channel.invokeMethod<String>('schedule', {
        'id': note.id, 'title': note.title, 'atMillis': note.reminderAt,
      }) ?? 'unavailable';

  static Future<void> cancel(String id) =>
      channel.invokeMethod<void>('cancel', {'id': id});
}
