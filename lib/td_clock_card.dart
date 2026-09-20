import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shamsi_date/shamsi_date.dart';

/// Lightweight twelve-hour clock; it does not rebuild the news feed.
class NewsClockCard extends StatefulWidget {
  final VoidCallback? onSettings;
  final VoidCallback? onSearch;
  const NewsClockCard({super.key, this.onSettings, this.onSearch});
  @override
  State<NewsClockCard> createState() => _NewsClockCardState();
}

class _NewsClockCardState extends State<NewsClockCard> {
  DateTime now = DateTime.now();
  Timer? timer;

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 30), (_) {
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
    final color = Theme.of(context).colorScheme;
    final shamsi = Jalali.fromDateTime(now).formatter;
    final hour = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final minute = now.minute.toString().padLeft(2, '0');
    final weekday = const ['دوشنبه', 'سه‌شنبه', 'چهارشنبه', 'پنج‌شنبه', 'جمعه', 'شنبه', 'یکشنبه'][now.weekday - 1];
    final date = shamsi.yyyy.toString() + '/' + shamsi.mm + '/' + shamsi.dd;
    return SizedBox(height: 88, child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(children: [
        SizedBox(width: 100, child: Row(children: [
          Expanded(child: FittedBox(fit: BoxFit.scaleDown, child: Column(children: [
            Text('$hour:$minute', textDirection: TextDirection.ltr,
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
            Text(weekday, style: const TextStyle(fontSize: 11)),
            Text(date, textDirection: TextDirection.ltr,
              style: TextStyle(fontSize: 10, color: color.onSurfaceVariant)),
          ]))),
          const SizedBox(width: 6),
          const Icon(Icons.calendar_month_outlined, size: 23),
        ])),
        Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('نبض خبر', style: TextStyle(fontFamily: 'Rooznameh',
            fontSize: 25, fontWeight: FontWeight.w800)),
          SizedBox(width: 65, height: 10,
            child: CustomPaint(painter: _PulsePainter(color.primary))),
          const SizedBox(height: 3),
          FittedBox(fit: BoxFit.scaleDown, child: Text('اخبار سریع، مطمئن، به‌روز',
            style: TextStyle(fontSize: 10, color: color.onSurfaceVariant))),
        ])),
        SizedBox(width: 64, child: Row(children: [
          Expanded(child: IconButton(
            padding: EdgeInsets.zero, tooltip: 'جست‌وجوی خبر',
            icon: const Icon(Icons.search_rounded, size: 20), onPressed: widget.onSearch)),
          Expanded(child: IconButton(
            padding: EdgeInsets.zero, tooltip: 'تنظیمات',
            icon: const Icon(Icons.settings_outlined, size: 25), onPressed: widget.onSettings)),
        ])),
      ]),
    ));
  }
}

class _PulsePainter extends CustomPainter {
  final Color color;
  const _PulsePainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..moveTo(0, 5)..lineTo(24, 5)..lineTo(29, 1)
      ..lineTo(33, 9)..lineTo(37, 4)..lineTo(size.width, 4);
    canvas.drawPath(path, Paint()..color = color..strokeWidth = 1.7
      ..style = PaintingStyle.stroke..strokeCap = StrokeCap.round);
  }
  @override
  bool shouldRepaint(_PulsePainter oldDelegate) => oldDelegate.color != color;
}
