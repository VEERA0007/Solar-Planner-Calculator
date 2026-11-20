import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Scenic sun card art. [t] is progress along the arc (0 = left horizon,
/// 1 = right horizon): the sun's progress between sunrise and sunset by day,
/// or the night path (sunset to next sunrise) by night.
class SunArtPainter extends CustomPainter {
  final bool night;
  final double t;
  final bool dark; // app theme, affects only the outer frame
  const SunArtPainter({required this.night, required this.t, required this.dark});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final r = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(w * 0.06));
    canvas.save();
    canvas.clipRRect(r);

    // ----- sky -----
    final skyRect = Offset.zero & size;
    final sky = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: night
            ? const [Color(0xFF050B24), Color(0xFF0B1A44), Color(0xFF16275E)]
            : const [Color(0xFF3D9BF0), Color(0xFF8CCBFA), Color(0xFFD7EEFF)],
      ).createShader(skyRect);
    canvas.drawRect(skyRect, sky);

    final horizon = h * 0.70;
    final arcL = w * 0.10, arcR = w * 0.90, arcTop = h * 0.14;

    if (night) {
      final rnd = math.Random(7);
      final star = Paint()..color = Colors.white;
      for (var i = 0; i < 46; i++) {
        final x = rnd.nextDouble() * w, y = rnd.nextDouble() * horizon * 0.95;
        star.color = Colors.white.withValues(alpha: 0.35 + rnd.nextDouble() * 0.65);
        canvas.drawCircle(Offset(x, y), 0.5 + rnd.nextDouble() * 1.1, star);
      }
      // two small constellations
      final line = Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..strokeWidth = 0.8;
      final c1 = [Offset(w * .12, h * .20), Offset(w * .20, h * .13), Offset(w * .27, h * .22), Offset(w * .22, h * .32)];
      for (var i = 0; i < c1.length - 1; i++) {
        canvas.drawLine(c1[i], c1[i + 1], line);
      }
      final c2 = [Offset(w * .70, h * .10), Offset(w * .78, h * .16), Offset(w * .85, h * .08)];
      for (var i = 0; i < c2.length - 1; i++) {
        canvas.drawLine(c2[i], c2[i + 1], line);
      }
      for (final o in [...c1, ...c2]) {
        canvas.drawCircle(o, 1.8, Paint()..color = Colors.white);
      }
    } else {
      // soft clouds
      final cloud = Paint()..color = Colors.white.withValues(alpha: 0.55);
      for (final c in [Offset(w * .18, h * .22), Offset(w * .72, h * .30)]) {
        canvas.drawOval(Rect.fromCenter(center: c, width: w * .16, height: h * .06), cloud);
        canvas.drawOval(Rect.fromCenter(center: c + Offset(w * .04, -h * .02), width: w * .11, height: h * .06), cloud);
      }
    }

    // ----- dashed arc -----
    final arc = Path();
    const steps = 60;
    Offset onArc(double u) => Offset(
          arcL + (arcR - arcL) * u,
          horizon - math.sin(math.pi * u) * (horizon - arcTop),
        );
    for (var i = 0; i <= steps; i++) {
      final p = onArc(i / steps);
      i == 0 ? arc.moveTo(p.dx, p.dy) : arc.lineTo(p.dx, p.dy);
    }
    final dash = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = (night ? Colors.white : const Color(0xFFFFFFFF)).withValues(alpha: night ? 0.45 : 0.85);
    for (final m in arc.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + 5, m.length)), dash);
        d += 10;
      }
    }

    // ----- far mountains, near hills, meadow -----
    Path ridge(List<Offset> pts) {
      final p = Path()..moveTo(0, h);
      for (final o in pts) {
        p.lineTo(o.dx, o.dy);
      }
      p.lineTo(w, h);
      p.close();
      return p;
    }

    canvas.drawPath(
      ridge([Offset(0, h * .66), Offset(w * .10, h * .52), Offset(w * .22, h * .64), Offset(w * .36, h * .48), Offset(w * .50, h * .66), Offset(w * .64, h * .55), Offset(w * .80, h * .67), Offset(w * .92, h * .56), Offset(w, h * .64)]),
      Paint()..color = night ? const Color(0xFF14204A) : const Color(0xFF7FA6C9),
    );
    canvas.drawPath(
      ridge([Offset(0, h * .74), Offset(w * .15, h * .64), Offset(w * .30, h * .73), Offset(w * .55, h * .70), Offset(w * .75, h * .74), Offset(w * .90, h * .66), Offset(w, h * .72)]),
      Paint()..color = night ? const Color(0xFF0C1736) : const Color(0xFF5F9C6B),
    );
    final meadow = Path()
      ..moveTo(0, h * .80)
      ..quadraticBezierTo(w * .30, h * .74, w * .60, h * .80)
      ..quadraticBezierTo(w * .85, h * .85, w, h * .79)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
      meadow,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: night ? const [Color(0xFF0A1A24), Color(0xFF060E18)] : const [Color(0xFF58B368), Color(0xFF3F9A55)],
        ).createShader(Rect.fromLTWH(0, h * .74, w, h * .26)),
    );

    // ----- beam from the marker down to the array -----
    final pos = onArc(t.clamp(0.0, 1.0));
    final arrayCx = w * .52, arrayTop = h * .66;
    final above = pos.dy < horizon - 2;
    if (above) {
      final beam = Path()
        ..moveTo(pos.dx, pos.dy)
        ..lineTo(arrayCx - w * .12, arrayTop)
        ..lineTo(arrayCx + w * .12, arrayTop)
        ..close();
      canvas.drawPath(
        beam,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: night
                ? [const Color(0xFFBFD4FF).withValues(alpha: .28), const Color(0x00BFD4FF)]
                : [const Color(0xFFFFE08A).withValues(alpha: .55), const Color(0x00FFE08A)],
          ).createShader(Rect.fromPoints(pos, Offset(arrayCx, arrayTop))),
      );
    }

    // ----- trees -----
    void tree(double x, double base, double s) {
      canvas.drawRect(Rect.fromLTWH(x - s * .06, base - s * .22, s * .12, s * .22), Paint()..color = night ? const Color(0xFF2A1F1A) : const Color(0xFF7A5230));
      final p = Paint()..color = night ? const Color(0xFF0E2B22) : const Color(0xFF2F8A4A);
      canvas.drawCircle(Offset(x, base - s * .42), s * .22, p);
      canvas.drawCircle(Offset(x - s * .14, base - s * .32), s * .16, p);
      canvas.drawCircle(Offset(x + s * .14, base - s * .32), s * .16, p);
    }

    tree(w * .08, h * .90, h * .32);
    tree(w * .17, h * .86, h * .24);
    tree(w * .93, h * .90, h * .30);

    // ----- tilted solar array -----
    final panelPaint = Paint()..color = night ? const Color(0xFF1B3A7A) : const Color(0xFF1E4FA8);
    final frame = Paint()
      ..color = night ? const Color(0xFF9FB6E8) : const Color(0xFFE5EEF9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final a0 = Offset(arrayCx - w * .17, h * .86), a1 = Offset(arrayCx - w * .02, h * .66);
    final a2 = Offset(arrayCx + w * .17, h * .70), a3 = Offset(arrayCx + w * .06, h * .90);
    final panel = Path()
      ..moveTo(a0.dx, a0.dy)
      ..lineTo(a1.dx, a1.dy)
      ..lineTo(a2.dx, a2.dy)
      ..lineTo(a3.dx, a3.dy)
      ..close();
    canvas.drawPath(panel, panelPaint);
    for (var i = 1; i < 4; i++) {
      final k = i / 4;
      canvas.drawLine(Offset.lerp(a0, a1, k)!, Offset.lerp(a3, a2, k)!, frame);
    }
    for (var i = 1; i < 3; i++) {
      final k = i / 3;
      canvas.drawLine(Offset.lerp(a0, a3, k)!, Offset.lerp(a1, a2, k)!, frame);
    }
    canvas.drawPath(panel, frame);
    // sun glint on panel
    if (above && !night) {
      canvas.drawPath(panel, Paint()..color = Colors.white.withValues(alpha: 0.10));
    }
    // legs
    canvas.drawLine(Offset(arrayCx - w * .06, h * .78), Offset(arrayCx - w * .06, h * .93), Paint()..color = const Color(0xFF8A94A6)..strokeWidth = 1.6);
    // battery cabinet
    final cab = RRect.fromRectAndRadius(Rect.fromLTWH(w * .73, h * .72, w * .09, h * .19), const Radius.circular(3));
    canvas.drawRRect(cab, Paint()..color = night ? const Color(0xFFDCE4F2) : Colors.white);
    canvas.drawRRect(cab, Paint()..color = const Color(0xFF8A94A6)..style = PaintingStyle.stroke..strokeWidth = .8);
    canvas.drawRect(Rect.fromLTWH(w * .745, h * .75, w * .06, h * .02), Paint()..color = const Color(0xFF22C55E));
    canvas.drawRect(Rect.fromLTWH(w * .745, h * .79, w * .06, h * .008), Paint()..color = const Color(0xFFB4BFD3));

    // ----- marker -----
    if (night) {
      // crescent moon
      final c = pos;
      final rad = w * .045;
      final glow = Paint()
        ..color = const Color(0xFFEFF4FF).withValues(alpha: .25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawCircle(c, rad * 1.7, glow);
      canvas.saveLayer(Rect.fromCircle(center: c, radius: rad * 2), Paint());
      canvas.drawCircle(c, rad, Paint()..color = const Color(0xFFF4F7FF));
      canvas.drawCircle(c + Offset(rad * .55, -rad * .2), rad * .92, Paint()..blendMode = BlendMode.clear);
      canvas.restore();
    } else {
      final c = pos;
      final rad = w * .04;
      canvas.drawCircle(
        c,
        rad * 2.4,
        Paint()
          ..color = const Color(0xFFFFD54A).withValues(alpha: .45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
      final ray = Paint()
        ..color = const Color(0xFFFFC107)
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 12; i++) {
        final a = i * math.pi / 6;
        canvas.drawLine(c + Offset(math.cos(a), math.sin(a)) * rad * 1.35, c + Offset(math.cos(a), math.sin(a)) * rad * 1.8, ray);
      }
      canvas.drawCircle(c, rad, Paint()..color = const Color(0xFFFFB300));
      canvas.drawCircle(c, rad * .72, Paint()..color = const Color(0xFFFFD54A));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant SunArtPainter old) => old.t != t || old.night != night || old.dark != dark;
}

/// Progress 0..1 for the marker in the chosen art mode. Day art follows the
/// sun between sunrise and sunset (parked at the horizon when the sun is down);
/// night art follows the night from sunset to the next sunrise (parked at the
/// start of the arc during daytime).
double arcProgress(DateTime now, DateTime? rise, DateTime? set, {required bool night}) {
  if (rise == null || set == null) return .5;
  final up = now.isAfter(rise) && now.isBefore(set);
  if (!night) {
    if (up) return now.difference(rise).inSeconds / math.max(1, set.difference(rise).inSeconds);
    return now.isBefore(rise) ? 0.0 : 1.0;
  }
  if (up) return 0.0;
  DateTime start, end;
  if (now.isBefore(rise)) {
    start = set.subtract(const Duration(days: 1));
    end = rise;
  } else {
    start = set;
    end = rise.add(const Duration(days: 1));
  }
  return (now.difference(start).inSeconds / math.max(1, end.difference(start).inSeconds)).clamp(0.0, 1.0);
}
