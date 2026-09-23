import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Purely decorative home-only landscape, inspired by the supplied bright
/// sky/green hill reference. No images, permissions, network or app state.
class GozarDaylightBackdrop extends StatelessWidget {
  const GozarDaylightBackdrop({super.key});

  @override
  Widget build(BuildContext context) => const Positioned.fill(
    child: IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(painter: _LandscapePainter()),
      ),
    ),
  );
}

class _LandscapePainter extends CustomPainter {
  const _LandscapePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.drawRect(Offset.zero & size,
      Paint()..shader = const LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Color(0xff5db7fb), Color(0xffbfefff),
          Color(0xffe8faff), Color(0xffb6e7a0)],
        stops: [0, .45, .7, 1],
      ).createShader(Offset.zero & size));

    final sun = Offset(w * .91, h * .09);
    canvas.drawCircle(sun, w * .115,
      Paint()..color = const Color(0x7afff1ae)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 23));
    canvas.drawCircle(sun, w * .058,
      Paint()..color = const Color(0xfffff4ce));

    final cloud = Paint()..color = const Color(0xfaffffff);
    void cloudAt(double x, double y, double scale) {
      final r = w * scale;
      for (final item in [
        Offset(-.85, .14), Offset(-.47, -.1),
        Offset(0, -.2), Offset(.5, 0), Offset(.92, .2),
      ]) {
        canvas.drawOval(Rect.fromCenter(
          center: Offset(x + item.dx * r, y + item.dy * r),
          width: r * 1.25, height: r * .72), cloud);
      }
    }
    cloudAt(w * .12, h * .13, .16);
    cloudAt(w * .75, h * .29, .12);
    cloudAt(w * .2, h * .67, .16);

    void ridge(List<double> heights, Color color, double bottom) {
      final path = Path()..moveTo(0, heights.first * h);
      for (var i = 1; i < heights.length; i++) {
        path.lineTo(w * i / (heights.length - 1), heights[i] * h);
      }
      path..lineTo(w, bottom)..lineTo(0, bottom)..close();
      canvas.drawPath(path, Paint()..color = color);
    }
    ridge(const [.78, .72, .77, .68, .74, .66, .73, .7, .77],
        const Color(0xff9ccde3), h);
    ridge(const [.88, .81, .87, .79, .84, .78, .86, .82, .88],
        const Color(0xff83bc78), h);
    ridge(const [.93, .9, .96, .87, .91, .88, .95],
        const Color(0xffa4db5b), h);
    final lake = Path()
      ..moveTo(w * .72, h)
      ..quadraticBezierTo(w * .6, h * .945, w * .8, h * .906)
      ..quadraticBezierTo(w * .91, h * .89, w, h * .895)
      ..lineTo(w, h)..close();
    canvas.drawPath(lake, Paint()..color = const Color(0xff6ec9e7));
    final grass = Path()
      ..moveTo(0, h * .945)
      ..quadraticBezierTo(w * .25, h * .92, w * .47, h)
      ..lineTo(0, h)..close();
    canvas.drawPath(grass, Paint()..color = const Color(0xff81c93e));

    final trunk = Paint()..color = const Color(0xff527d3b)
      ..strokeWidth = math.max(2, w * .008)
      ..strokeCap = StrokeCap.round;
    for (final tree in const [
      [0.07, .88, .052], [.18, .92, .035],
      [.38, .925, .027], [.93, .93, .04],
    ]) {
      final x = w * tree[0], y = h * tree[1], r = w * tree[2];
      canvas.drawLine(Offset(x, y + r * .75),
        Offset(x, y - r * 1.4), trunk);
      canvas.drawOval(Rect.fromCenter(
        center: Offset(x, y - r * 1.05),
        width: r * 1.6, height: r * 2.7),
        Paint()..color = const Color(0xff4ca84c));
      canvas.drawOval(Rect.fromCenter(
        center: Offset(x - r * .28, y - r * 1.35),
        width: r * .7, height: r * 1.5),
        Paint()..color = const Color(0xff78c85a));
    }
  }

  @override
  bool shouldRepaint(covariant _LandscapePainter oldDelegate) => false;
}
