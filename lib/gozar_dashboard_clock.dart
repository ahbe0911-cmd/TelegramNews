import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shamsi_date/shamsi_date.dart';

import 'gozar_visuals.dart';

const _weekdays = <String>[
  'دوشنبه', 'سه‌شنبه', 'چهارشنبه', 'پنجشنبه',
  'جمعه', 'شنبه', 'یکشنبه',
];
const _months = <String>[
  'فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور',
  'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند',
];

String persianDigits(Object value) {
  const latin = '0123456789';
  const persian = '۰۱۲۳۴۵۶۷۸۹';
  return value.toString().split('').map((ch) {
    final index = latin.indexOf(ch);
    return index < 0 ? ch : persian[index];
  }).join();
}

/// Clock hands and solar Hijri date follow the phone's time and timezone.
class GozarLiveClock extends StatefulWidget {
  const GozarLiveClock({super.key});

  @override
  State<GozarLiveClock> createState() => _GozarLiveClockState();
}

class _GozarLiveClockState extends State<GozarLiveClock> {
  late DateTime now;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    now = DateTime.now();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() { now = DateTime.now(); });
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final jalali = Jalali.fromDateTime(now);
    final day = _weekdays[now.weekday - 1];
    final date = persianDigits(jalali.day) + ' ' +
        _months[jalali.month - 1] + ' ' + persianDigits(jalali.year);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: 162, height: 162,
        child: CustomPaint(
          painter: _ClockPainter(now),
          child: const Center(child: Padding(
            padding: EdgeInsets.only(top: 77),
            child: Text('تهران · ساعت دستگاه', style: TextStyle(
                color: GozarPalette.muted, fontSize: 8)),
          )),
        ),
      ),
      const SizedBox(height: 4),
      Text(day + '، ' + persianDigits(jalali.day),
        textAlign: TextAlign.center,
        style: const TextStyle(color: GozarPalette.text,
            fontSize: 15, fontWeight: FontWeight.w800)),
      Text(date, textAlign: TextAlign.center,
        style: const TextStyle(color: GozarPalette.muted, fontSize: 10)),
    ]);
  }
}

class _ClockPainter extends CustomPainter {
  final DateTime time;
  const _ClockPainter(this.time);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 4;
    canvas.drawCircle(center, radius + 2,
        Paint()..color = GozarPalette.cyan.withOpacity(.16)
          ..style = PaintingStyle.stroke ..strokeWidth = 6);
    canvas.drawCircle(center, radius,
        Paint()..color = const Color(0xff06152e));
    canvas.drawCircle(center, radius,
        Paint()..color = GozarPalette.blue.withOpacity(.86)
          ..style = PaintingStyle.stroke ..strokeWidth = 1.8);

    for (var n = 0; n < 60; n++) {
      final angle = n * math.pi / 30 - math.pi / 2;
      final major = n % 5 == 0;
      final p1 = center + Offset(math.cos(angle), math.sin(angle)) *
          (radius - (major ? 12 : 6));
      final p2 = center + Offset(math.cos(angle), math.sin(angle)) *
          (radius - 3);
      canvas.drawLine(p1, p2, Paint()
        ..color = major ? Colors.white : GozarPalette.muted
        ..strokeWidth = major ? 1.6 : .7);
    }
    for (var n = 1; n <= 12; n++) {
      final angle = n * math.pi / 6 - math.pi / 2;
      final position = center +
          Offset(math.cos(angle), math.sin(angle)) * (radius - 25);
      final label = TextPainter(
        text: TextSpan(text: persianDigits(n), style: const TextStyle(
          color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, position - Offset(label.width / 2, label.height / 2));
    }

    void hand(double degrees, double length, double width, Color color) {
      final angle = degrees * math.pi / 180 - math.pi / 2;
      canvas.drawLine(center,
          center + Offset(math.cos(angle), math.sin(angle)) * length,
          Paint()..color = color ..strokeCap = StrokeCap.round
            ..strokeWidth = width);
    }

    hand((time.hour % 12 + time.minute / 60) * 30, radius * .47,
        5, Colors.white);
    hand((time.minute + time.second / 60) * 6, radius * .72,
        3.5, Colors.white);
    hand(time.second * 6, radius * .79, 1.2, GozarPalette.cyan);
    canvas.drawCircle(center, 4, Paint()..color = GozarPalette.cyan);
  }

  @override
  bool shouldRepaint(covariant _ClockPainter oldDelegate) =>
      time.second != oldDelegate.time.second ||
      time.minute != oldDelegate.time.minute;
}
