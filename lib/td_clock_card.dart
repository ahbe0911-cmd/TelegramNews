import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shamsi_date/shamsi_date.dart';

/// Lightweight twelve-hour clock; it does not rebuild the news feed.
class NewsClockCard extends StatefulWidget {
  const NewsClockCard({super.key});
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
    final ampm = now.hour < 12 ? 'قبل‌ازظهر' : 'بعدازظهر';
    final weekday = const ['دوشنبه', 'سه‌شنبه', 'چهارشنبه', 'پنج‌شنبه', 'جمعه', 'شنبه', 'یکشنبه'][now.weekday - 1];
    final date = shamsi.yyyy.toString() + '/' + shamsi.mm + '/' + shamsi.dd;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight, end: Alignment.bottomLeft,
          colors: [
            color.primaryContainer,
            color.primaryContainer.withValues(alpha: .6),
          ],
        ),
        borderRadius: BorderRadius.circular(19),
      ),
      child: Row(children: [
        Container(
          width: 43, height: 43,
          decoration: BoxDecoration(
            color: color.surface.withValues(alpha: .8),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(Icons.schedule_rounded, color: color.primary, size: 23),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(weekday + ' • ' + date,
              style: TextStyle(fontSize: 12, color: color.onPrimaryContainer)),
            const SizedBox(height: 3),
            const Text('آخرین اخبار کانال‌های شما',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
          ],
        )),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(hour.toString() + ':' + minute,
            textDirection: TextDirection.ltr,
            style: TextStyle(color: color.onPrimaryContainer,
              fontSize: 22, fontWeight: FontWeight.w800, fontFamily: 'CustomFont')),
          Text(ampm, style: TextStyle(
            fontSize: 10, color: color.onPrimaryContainer)),
        ]),
      ]),
    );
  }
}
