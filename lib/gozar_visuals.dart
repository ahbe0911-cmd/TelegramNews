import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Purely decorative visuals: real VPN state and traffic are supplied by the
/// native bridge, never inferred from the design.
abstract final class GozarPalette {
  static const base = Color(0xff050d22);
  static const navy = Color(0xff091c37);
  static const panel = Color(0xff112544);
  static const cyan = Color(0xff36eaff);
  static const blue = Color(0xff2798fa);
  static const purple = Color(0xff9c6bff);
  static const green = Color(0xff38e087);
  static const red = Color(0xffff5268);
  static const text = Color(0xfff3f8ff);
  static const muted = Color(0xffabbdd7);
  static const daylightInk = Color(0xff153754);
  static const daylightMuted = Color(0xff587792);
  static const daylightAccent = Color(0xff2367c4);
  static const daylightCard = Color(0xfff8fcff);
}

class AuroraBackdrop extends StatefulWidget {
  const AuroraBackdrop({super.key});

  @override
  State<AuroraBackdrop> createState() => _AuroraBackdropState();
}

class _AuroraBackdropState extends State<AuroraBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController drift;

  @override
  void initState() {
    super.initState();
    drift = AnimationController(vsync: this,
        duration: const Duration(seconds: 11))..repeat(reverse: true);
  }

  @override
  void dispose() {
    drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: IgnorePointer(
      child: RepaintBoundary(child: AnimatedBuilder(
        animation: drift,
        builder: (_, __) => CustomPaint(
          painter: _AuroraPainter(drift.value),
        ),
      )),
    ),
  );
}

class _AuroraPainter extends CustomPainter {
  final double phase;
  _AuroraPainter(this.phase);
  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [Color(0xff07122d), Color(0xff122b59),
          Color(0xff0a1334), Color(0xff020917)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, background);

    for (var i = 0; i < 5; i++) {
      final x = size.width * (.04 + i * .23 + phase * (i.isEven ? .07 : -.05));
      final halo = Paint()
        ..shader = RadialGradient(
          colors: [
            (i.isEven ? GozarPalette.cyan : GozarPalette.purple)
                .withOpacity(.20),
            Colors.transparent,
          ],
        ).createShader(Rect.fromCircle(
            center: Offset(x, size.height * (.16 + phase * .06)),
            radius: size.width * .52));
      canvas.drawCircle(Offset(x, size.height * .19),
          size.width * .52, halo);
    }

    final line = Paint()..style = PaintingStyle.stroke
      ..strokeWidth = 28
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 34)
      ..color = GozarPalette.cyan.withOpacity(.16);
    final sweep = Path()
      ..moveTo(-30, size.height * .20)
      ..quadraticBezierTo(size.width * .4, size.height * .04,
          size.width + 30, size.height * .12);
    canvas.drawPath(sweep, line);

    final star = Paint()..color = const Color(0xffd9ebff);
    for (var i = 0; i < 95; i++) {
      final x = ((i * 73 + 19) % 101) / 101 * size.width;
      final y = ((i * 41 + 7) % 97) / 97 * math.min(size.height, 820);
      canvas.drawCircle(Offset(x, y),
          i % 9 == 0 ? 1.2 : .45, star..color =
          const Color(0xffb4eaff).withOpacity(i % 4 == 0 ? .60 : .24));
    }

    final ridgeA = Path()..moveTo(0, size.height * .55);
    const a = [0.62, 0.51, 0.56, 0.41, 0.52, 0.45,
      0.57, 0.39, 0.54, 0.47, 0.58, 0.51, 0.63];
    for (var i = 0; i < a.length; i++) {
      ridgeA.lineTo(size.width * i / (a.length - 1),
          size.height * a[i]);
    }
    ridgeA..lineTo(size.width, size.height)..lineTo(0, size.height)
      ..close();
    canvas.drawPath(ridgeA, Paint()
      ..color = const Color(0xff061328).withOpacity(.76));

    final ridgeB = Path()..moveTo(0, size.height * .79);
    const b = [0.81, 0.73, 0.78, 0.67, 0.78, 0.70,
      0.81, 0.71, 0.75, 0.65, 0.81, 0.72, 0.79];
    for (var i = 0; i < b.length; i++) {
      ridgeB.lineTo(size.width * i / (b.length - 1),
          size.height * b[i]);
    }
    ridgeB..lineTo(size.width, size.height)..lineTo(0, size.height)
      ..close();
    canvas.drawPath(ridgeB, Paint()
      ..color = const Color(0xff020916).withOpacity(.62));
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter oldDelegate) => oldDelegate.phase != phase;
}

class GozarPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color glow;
  final bool daylight;
  const GozarPanel({
    super.key, required this.child,
    this.padding = const EdgeInsets.all(16),
    this.glow = GozarPalette.cyan,
    this.daylight = false,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(22),
      gradient: LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: daylight
          ? const [Color(0xffffffff), Color(0xfff1f8ff)]
          : [
              const Color(0xff18335a).withOpacity(.89),
              const Color(0xff09172e).withOpacity(.94),
            ],
      ),
      border: Border.all(color: daylight
          ? const Color(0xffe1ecfa) : glow.withOpacity(.29)),
      boxShadow: [
        BoxShadow(color: daylight
            ? const Color(0xff257bc1).withOpacity(.12)
            : glow.withOpacity(.08),
            blurRadius: 24, offset: const Offset(0, 7)),
      ],
    ),
    child: child,
  );
}

class GozarPowerButton extends StatefulWidget {
  final bool connected;
  final bool busy;
  final VoidCallback? onPressed;
  final String label;
  const GozarPowerButton({
    super.key, required this.connected, required this.busy,
    required this.onPressed, required this.label,
  });

  @override
  State<GozarPowerButton> createState() => _GozarPowerButtonState();
}

class _GozarPowerButtonState extends State<GozarPowerButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController glow;

  @override
  void initState() {
    super.initState();
    glow = AnimationController(vsync: this,
      duration: const Duration(milliseconds: 2400))
        ..repeat(reverse: true);
  }

  @override
  void dispose() {
    glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.connected ? GozarPalette.green : GozarPalette.red;
    return AnimatedBuilder(
      animation: glow,
      builder: (context, _) => Center(child: Semantics(
      button: true, label: widget.label,
      child: InkWell(
        onTap: widget.onPressed,
        customBorder: const CircleBorder(),
        child: Container(
          width: 154, height: 154,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color.withOpacity(.36 + glow.value * .48), width: 2),
            boxShadow: [BoxShadow(
              color: color.withOpacity((widget.connected ? .14 : .08) + glow.value * .18),
              blurRadius: 24 + glow.value * 26,
              spreadRadius: 1 + glow.value * 7,
            )],
          ),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 3),
              gradient: const RadialGradient(
                colors: [Color(0xff0e4260), Color(0xff07162f)],
              ),
              boxShadow: [
                BoxShadow(color: color.withOpacity(.30 + glow.value * .42),
                    blurRadius: 9 + glow.value * 15, spreadRadius: 1 + glow.value * 2),
                const BoxShadow(color: Color(0xbb000818),
                    blurRadius: 14, offset: Offset(0, 7)),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Transform.scale(
                  scale: 1.0 + (widget.connected ? .04 : .018) * glow.value,
                  child: Icon(Icons.power_settings_new_rounded, size: 45,
                    color: color),
                ),
                const SizedBox(height: 3),
                Text(widget.busy ? 'در حال انجام…' :
                    widget.connected ? 'متصل' : 'اتصال',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: GozarPalette.text)),
                const SizedBox(height: 3),
                Text(widget.label,
                  maxLines: 1, softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 9,
                      color: GozarPalette.muted)),
              ],
            ),
          ),
        ),
      ),
    )),
    );
  }
}

class GozarLineChart extends StatelessWidget {
  final List<double> incoming;
  final List<double> outgoing;
  const GozarLineChart({
    super.key, required this.incoming, required this.outgoing,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 99, width: double.infinity,
    child: CustomPaint(
      painter: _GozarChartPainter(incoming, outgoing),
    ),
  );
}

class _GozarChartPainter extends CustomPainter {
  final List<double> incoming;
  final List<double> outgoing;
  _GozarChartPainter(this.incoming, this.outgoing);

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()..color = Colors.white.withOpacity(.085)
      ..strokeWidth = 1;
    for (var n = 1; n <= 3; n++) {
      final y = size.height * n / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final maxValue = math.max(1.0,
        [...incoming, ...outgoing].fold<double>(
            0.0, (previous, value) => math.max(previous, value)));
    void draw(List<double> points, Color color) {
      if (points.length < 2) return;
      final path = Path();
      for (var n = 0; n < points.length; n++) {
        final x = size.width * n / (points.length - 1);
        final y = size.height * (.92 - .80 * points[n] / maxValue);
        if (n == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, Paint()
        ..color = color.withOpacity(.20)
        ..strokeWidth = 7
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
      canvas.drawPath(path, Paint()
        ..color = color
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke);
    }
    draw(incoming, GozarPalette.cyan);
    draw(outgoing, GozarPalette.purple);
  }

  @override
  bool shouldRepaint(covariant _GozarChartPainter old) =>
      old.incoming != incoming || old.outgoing != outgoing;
}

class GozarMetric extends StatelessWidget {
  final IconData icon;
  final String caption;
  final String value;
  final Color accent;
  const GozarMetric({
    super.key, required this.icon, required this.caption,
    required this.value, this.accent = GozarPalette.cyan,
  });

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      constraints: const BoxConstraints(minHeight: 82),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: const Color(0xff193359).withOpacity(.62),
        border: Border.all(color: accent.withOpacity(.23)),
      ),
      child: Row(children: [
        CircleAvatar(
          backgroundColor: accent.withOpacity(.15),
          radius: 17, child: Icon(icon, color: accent, size: 17),
        ),
        const SizedBox(width: 8),
        Expanded(child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(caption,
              style: const TextStyle(color: GozarPalette.muted,
                  fontSize: 10)),
            Text(value, overflow: TextOverflow.ellipsis,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.right,
              style: const TextStyle(color: GozarPalette.text,
                fontSize: 13, fontWeight: FontWeight.w700)),
          ],
        )),
      ]),
    ),
  );
}
