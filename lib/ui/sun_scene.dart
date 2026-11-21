import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Marker progress 0..1 along the arc. By day: sunrise to sunset. After dark
/// (night = true) the marker keeps travelling the arc from sunset to the next
/// sunrise so the card is never frozen; otherwise it parks at the ends.
double arcProgress(DateTime now, DateTime? rise, DateTime? set, {bool night = false}) {
  if (rise == null || set == null) return .5;
  final up = now.isAfter(rise) && now.isBefore(set);
  if (up) return now.difference(rise).inSeconds / math.max(1, set.difference(rise).inSeconds);
  if (!night) return now.isBefore(rise) ? 0.0 : 1.0;
  late DateTime from, to;
  if (now.isBefore(rise)) {
    from = set.subtract(const Duration(days: 1));
    to = rise;
  } else {
    from = set;
    to = rise.add(const Duration(days: 1));
  }
  return (now.difference(from).inSeconds / math.max(1, to.difference(from).inSeconds)).clamp(0.0, 1.0);
}

double _smooth(double a, double b, double x) {
  final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

final List<List<double>> _stars = () {
  final r = math.Random(11);
  return [for (var i = 0; i < 150; i++) [r.nextDouble(), r.nextDouble() * .62, .5 + r.nextDouble() * 1.2, r.nextDouble(), 1 + r.nextInt(3).toDouble()]];
}();

/// Animated sun card scene. The sun glides along the arc and sinks at the ends;
/// tap replays a whole day. Stars twinkle at night and clouds drift by day.
class SunScene extends StatefulWidget {
  /// Disable ambient animation (used by tests so pumpAndSettle can finish).
  static bool animate = true;
  final bool night;
  final double t;
  const SunScene({super.key, required this.night, required this.t});
  @override
  State<SunScene> createState() => _SunSceneState();
}

class _SunSceneState extends State<SunScene> with TickerProviderStateMixin {
  late final AnimationController _ambient = AnimationController(vsync: this, duration: const Duration(seconds: 24));
  late final AnimationController _move = AnimationController(vsync: this);
  bool _busy = false;
  double _from = 0, _to = 0;
  bool _replaying = false;

  @override
  void initState() {
    super.initState();
    if (SunScene.animate) {
      _ambient.repeat();
      _glide(widget.t, 2600); // the sun rises into place when the screen opens
    }
  }

  Future<void> _glide(double to, int ms, {Curve curve = Curves.easeInOutCubic}) async {
    _from = _shown(curve);
    _to = to;
    _busy = true;
    _curve = curve;
    _move.duration = Duration(milliseconds: ms);
    try {
      await _move.forward(from: 0).orCancel;
    } catch (_) {}
    if (mounted && !_replaying) _busy = false;
  }

  Curve _curve = Curves.easeInOutCubic;
  double _shown([Curve? c]) => _busy ? _from + (_to - _from) * (c ?? _curve).transform(_move.value) : widget.t;

  Future<void> _replay() async {
    if (!SunScene.animate || _replaying) return;
    _replaying = true;
    await _glide(0, 500);
    if (!mounted) return;
    await _glide(1, 6000, curve: Curves.easeInOut);
    if (!mounted) return;
    await _glide(widget.t, 1600);
    _replaying = false;
    if (mounted) setState(() => _busy = false);
  }

  @override
  void dispose() {
    _ambient.dispose();
    _move.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _replay,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: Listenable.merge([_ambient, _move]),
          builder: (context, _) => CustomPaint(
            painter: SunScenePainter(night: widget.night, t: _shown(), phase: _ambient.value),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

class SunScenePainter extends CustomPainter {
  final bool night;
  final double t; // 0 = sunrise end of the arc, 1 = sunset end
  final double phase; // 0..1 ambient loop
  const SunScenePainter({required this.night, required this.t, this.phase = 0});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    // scene coordinates (u, v in 0..1) -> card pixels; the scene covers the right ~70% of the card
    Offset P(double u, double v) => Offset(w * (0.30 + 0.71 * u), h * (-0.03 + 1.03 * v));
    final full = Offset.zero & size;

    // arc geometry (semicircle whose feet are the sunrise and sunset points)
    final cx = w * .675, cy = h * .80, rx = w * .29, ry = h * .71;
    Offset onArc(double u) => Offset(cx - rx * math.cos(math.pi * u), cy - ry * math.sin(math.pi * u));
    final tt = t.clamp(0.0, 1.0);
    final sun = onArc(tt);
    final height = math.sin(math.pi * tt); // 0 at the horizon, 1 at noon
    final dusk = 1 - _smooth(0.0, 0.22, height);

    // ============ scene layer (masked so it fades into the card) ============
    canvas.saveLayer(full, Paint());
    night ? _night(canvas, size, P, sun, height) : _day(canvas, size, P, sun, dusk);
    // fade the left edge and the bottom into the card colour
    canvas.drawRect(
      full,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = const LinearGradient(colors: [Color(0x00000000), Color(0xFF000000)])
            .createShader(Rect.fromLTWH(w * .27, 0, w * .21, h)),
    );
    canvas.drawRect(
      full,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF000000), Color(0xFF000000), Color(0x55000000)],
          stops: [0, .78, 1],
        ).createShader(full),
    );
    canvas.restore();

    // ============ light beam ============
    if (height > .04) {
      final tip = P(.62, .43);
      final beam = Path()
        ..moveTo(sun.dx, sun.dy)
        ..lineTo(tip.dx - w * .09, tip.dy)
        ..lineTo(tip.dx + w * .10, tip.dy)
        ..close();
      final warm = night ? const Color(0xFFFFB84D) : const Color(0xFFFFE9A8);
      canvas.drawPath(
        beam,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [warm.withValues(alpha: night ? .30 : .38), warm.withValues(alpha: 0)],
          ).createShader(Rect.fromPoints(sun, tip))
          ..color = warm,
      );
    }

    // ============ dashed arc (outer faint + main) ============
    void dashed(double scale, double alpha, double width, double dash, double gap) {
      final path = Path();
      for (var i = 0; i <= 80; i++) {
        final u = i / 80;
        final p = Offset(cx - rx * scale * math.cos(math.pi * u), cy - ry * scale * math.sin(math.pi * u));
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.butt
        ..color = Colors.white.withValues(alpha: alpha);
      final under = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width + 1.6
        ..color = const Color(0xFF0B3A86).withValues(alpha: night ? 0 : .22);
      for (final m in path.computeMetrics()) {
        var d = 0.0;
        while (d < m.length) {
          final seg = m.extractPath(d, math.min(d + dash, m.length));
          if (!night) canvas.drawPath(seg, under);
          canvas.drawPath(seg, paint);
          d += dash + gap;
        }
      }
    }

    dashed(1.0, .95, 2.6, 6, 7);

    // ============ sun ============
    final pulse = 1 + .08 * math.sin(phase * math.pi * 2 * 6);
    final rad = w * .024;
    if (height <= .015) {
      // below the horizon: dim disc parked at the end of the arc
      canvas.drawCircle(sun, rad * 1.1, Paint()..color = const Color(0xFF8A5A3C).withValues(alpha: .55));
    } else {
      final warmth = Color.lerp(const Color(0xFFFF8A00), const Color(0xFFFF5A1F), dusk * .8)!;
      canvas.drawCircle(
        sun,
        rad * 3.2 * pulse,
        Paint()
          ..shader = RadialGradient(colors: [warmth.withValues(alpha: .55), warmth.withValues(alpha: 0)])
              .createShader(Rect.fromCircle(center: sun, radius: rad * 3.2 * pulse)),
      );
      canvas.drawCircle(sun, rad * 1.18, Paint()..color = warmth);
      canvas.drawCircle(sun, rad * .82, Paint()..color = Colors.white);
      canvas.drawCircle(sun, rad * .5, Paint()..color = warmth);
    }
  }

  // ------------------------------------------------------------------ day
  void _day(Canvas canvas, Size size, Offset Function(double, double) P, Offset sun, double dusk) {
    final w = size.width, h = size.height;
    final full = Offset.zero & size;
    final horizon = h * .56;
    canvas.drawRect(
      full,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1E74F0), Color(0xFF4F9CF5), Color(0xFF9CCDF8), Color(0xFFDDEEFC)],
          stops: [0, .38, .66, 1],
        ).createShader(Rect.fromLTWH(0, 0, w, horizon + 4)),
    );
    // warm sunrise / sunset wash
    if (dusk > .01) {
      canvas.drawRect(
        full,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [const Color(0x00FF9A3C), const Color(0xFFFF8A3C).withValues(alpha: .45 * dusk)],
          ).createShader(Rect.fromLTWH(0, 0, w, horizon)),
      );
    }
    // soft light around the moving sun
    canvas.drawCircle(
      sun,
      w * .24,
      Paint()
        ..shader = RadialGradient(colors: [const Color(0xFFFFF3C4).withValues(alpha: .55 * (1 - dusk * .5)), const Color(0x00FFF3C4)])
            .createShader(Rect.fromCircle(center: sun, radius: w * .24)),
    );
    // fluffy drifting clouds
    void cloud(Offset c, double s) {
      final shade = Paint()..color = const Color(0xFFD5E6F7).withValues(alpha: .8)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
      final white = Paint()..color = Colors.white.withValues(alpha: .95)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2);
      for (final b in const [[-.9, .15, .55], [-.35, -.1, .75], [.3, -.2, .85], [.95, .1, .6], [0.0, .22, 1.0]]) {
        canvas.drawCircle(c + Offset(b[0] * s, (b[1] + .12) * s), b[2] * s * .55, shade);
      }
      for (final b in const [[-.9, .15, .55], [-.35, -.1, .75], [.3, -.2, .85], [.95, .1, .6], [0.0, .22, 1.0]]) {
        canvas.drawCircle(c + Offset(b[0] * s, b[1] * s), b[2] * s * .55, white);
      }
    }
    for (var i = 0; i < 3; i++) {
      final x = (((i * .38 + phase * .5) % 1.4) - .2);
      cloud(P(x, .15 + (i % 2) * .15), h * (.075 + (i % 3) * .015));
    }
    // hazy mountains
    Path ridge(List<List<double>> pts, double base) {
      final p = Path()..moveTo(P(0, base).dx, P(0, base).dy);
      for (final q in pts) {
        final o = P(q[0], q[1]);
        p.lineTo(o.dx, o.dy);
      }
      p.lineTo(P(1.02, base).dx, P(1.02, base).dy);
      p.close();
      return p;
    }
    canvas.drawPath(
      ridge([[0, .52], [.08, .43], [.17, .34], [.26, .45], [.36, .37], [.46, .48], [.58, .39], [.70, .31], [.80, .42], [.90, .35], [1, .46]], .6),
      Paint()..color = const Color(0xFFA9C6E6).withValues(alpha: .8),
    );
    canvas.drawPath(
      ridge([[0, .56], [.12, .49], [.24, .53], [.38, .47], [.52, .55], [.66, .48], [.82, .54], [1, .50]], .62),
      Paint()..color = const Color(0xFF86AEDA).withValues(alpha: .85),
    );
    // far rolling hill
    final far = Path()
      ..moveTo(0, horizon + h * .01)
      ..cubicTo(w * .3, horizon - h * .09, w * .55, horizon - h * .03, w * .8, horizon - h * .07)
      ..cubicTo(w * .9, horizon - h * .08, w * .96, horizon - h * .05, w, horizon - h * .04)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(far, Paint()..color = const Color(0xFF9ACB6A));
    // meadow
    final ground = Path()
      ..moveTo(0, horizon + h * .04)
      ..cubicTo(w * .35, horizon - h * .03, w * .65, horizon + h * .07, w, horizon + h * .01)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
      ground,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF7CC04E), Color(0xFF63AE3F), Color(0xFF9CD36B)],
          stops: [0, .55, 1],
        ).createShader(Rect.fromLTWH(0, horizon, w, h - horizon)),
    );
    // mowing stripes for depth
    for (var i = 0; i < 6; i++) {
      final y = horizon + h * (.12 + i * .075);
      canvas.drawRect(Rect.fromLTWH(0, y, w, h * .035), Paint()..color = Colors.white.withValues(alpha: .05));
    }
    // grass strokes and flowers
    final blade = Paint()..color = const Color(0xFF4E8F34).withValues(alpha: .4)..strokeWidth = 1;
    final rnd = math.Random(5);
    for (var i = 0; i < 80; i++) {
      final x = w * (.3 + rnd.nextDouble() * .72), y = horizon + h * (.1 + rnd.nextDouble() * .38);
      canvas.drawLine(Offset(x, y), Offset(x + 2, y - 5), blade);
    }
    const petals = [Color(0xFFFFFFFF), Color(0xFFFFD84D), Color(0xFFFF8FB1)];
    for (var i = 0; i < 16; i++) {
      final x = w * (.34 + rnd.nextDouble() * .66), y = horizon + h * (.2 + rnd.nextDouble() * .3);
      canvas.drawCircle(Offset(x, y), 1.6, Paint()..color = petals[i % 3]);
    }
    // trees: layered, with a soft shade side
    void tree(Offset base, double s) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(base.dx - s * .045, base.dy - s * .3, s * .09, s * .3), const Radius.circular(1.5)),
        Paint()..color = const Color(0xFF7A5634),
      );
      canvas.drawCircle(base + Offset(s * .03, -s * .4), s * .27, Paint()..color = const Color(0xFF3F8A3C));
      canvas.drawCircle(base + Offset(-s * .12, -s * .52), s * .2, Paint()..color = const Color(0xFF55A24A));
      canvas.drawCircle(base + Offset(s * .12, -s * .56), s * .2, Paint()..color = const Color(0xFF55A24A));
      canvas.drawCircle(base + Offset(0, -s * .66), s * .17, Paint()..color = const Color(0xFF72BE5F));
      canvas.drawCircle(base + Offset(-s * .05, -s * .7), s * .07, Paint()..color = Colors.white.withValues(alpha: .18));
    }
    tree(P(.13, .60), h * .34);
    tree(P(.05, .57), h * .22);
    tree(P(.985, .58), h * .34);

    // solar array: large tilted panels on a steel frame
    final fl = P(.255, .67), bl = P(.435, .40), br = P(.80, .385), fr = P(.70, .655);
    canvas.drawPath(
      Path()..moveTo(fl.dx, fl.dy + h * .10)..lineTo(fr.dx, fr.dy + h * .10)..lineTo(fr.dx + w * .06, fr.dy + h * .13)..lineTo(fl.dx + w * .03, fl.dy + h * .13)..close(),
      Paint()..color = const Color(0xFF2B6126).withValues(alpha: .38)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    _legs(canvas, fl, fr, h * .10, const Color(0xFF8E98A8));
    _array(canvas, fl, bl, br, fr, rows: 3, cols: 5, top: const Color(0xFF2A66D8), bottom: const Color(0xFF0C2A7E), frame: const Color(0xFFEFF5FC));
    // glossy sheen: a bright band sweeping across the panels, stronger with the sun high
    final lit = (1 - dusk).clamp(0.0, 1.0);
    final g = (phase * 3) % 1.0;
    Offset bil(double a, double b) => Offset.lerp(Offset.lerp(fl, bl, a)!, Offset.lerp(fr, br, a)!, b)!;
    final sheen = Path()
      ..moveTo(bil(0, g * .8).dx, bil(0, g * .8).dy)
      ..lineTo(bil(1, g * .8 + .1).dx, bil(1, g * .8 + .1).dy)
      ..lineTo(bil(1, g * .8 + .22).dx, bil(1, g * .8 + .22).dy)
      ..lineTo(bil(0, g * .8 + .12).dx, bil(0, g * .8 + .12).dy)
      ..close();
    canvas.drawPath(sheen, Paint()..color = Colors.white.withValues(alpha: .16 * lit * math.sin(g * math.pi)));
    canvas.drawPath(
      Path()..moveTo(fl.dx, fl.dy)..lineTo(bl.dx, bl.dy)..lineTo(Offset.lerp(bl, br, .5)!.dx, Offset.lerp(bl, br, .5)!.dy)..lineTo(Offset.lerp(fl, fr, .5)!.dx, Offset.lerp(fl, fr, .5)!.dy)..close(),
      Paint()..color = Colors.white.withValues(alpha: .07 * lit),
    );

    // battery cabinet with side and top faces
    final cabF = Rect.fromPoints(P(.79, .75), P(.885, .56));
    final dx = w * .014, dy = h * .022;
    canvas.drawRect(Rect.fromLTWH(cabF.left, cabF.bottom - 1, cabF.width + dx, 4), Paint()..color = const Color(0xFF2E6B2A).withValues(alpha: .35));
    canvas.drawPath(
      Path()..moveTo(cabF.right, cabF.top)..lineTo(cabF.right + dx, cabF.top - dy)..lineTo(cabF.right + dx, cabF.bottom - dy)..lineTo(cabF.right, cabF.bottom)..close(),
      Paint()..color = const Color(0xFFC3CDDA),
    );
    canvas.drawPath(
      Path()..moveTo(cabF.left, cabF.top)..lineTo(cabF.left + dx, cabF.top - dy)..lineTo(cabF.right + dx, cabF.top - dy)..lineTo(cabF.right, cabF.top)..close(),
      Paint()..color = const Color(0xFFF4F7FB),
    );
    final body = RRect.fromRectAndRadius(cabF, const Radius.circular(2));
    canvas.drawRRect(body, Paint()..shader = const LinearGradient(colors: [Color(0xFFFFFFFF), Color(0xFFE9EEF5)]).createShader(cabF));
    canvas.drawRRect(body, Paint()..color = const Color(0xFFB4BFCD)..style = PaintingStyle.stroke..strokeWidth = .9);
    // charge level bars
    for (var i = 0; i < 4; i++) {
      canvas.drawRect(Rect.fromLTWH(cabF.left + cabF.width * .18, cabF.top + cabF.height * (.12 + i * .045), cabF.width * .64, cabF.height * .028), Paint()..color = const Color(0xFF34D399).withValues(alpha: i == 3 ? .5 + .4 * math.sin(phase * math.pi * 2 * 6) : .9));
    }
    final bc = Offset(cabF.center.dx, cabF.top + cabF.height * .66);
    final bs = cabF.height * .17;
    canvas.drawPath(
      Path()
        ..moveTo(bc.dx + bs * .15, bc.dy - bs)
        ..lineTo(bc.dx - bs * .55, bc.dy + bs * .12)
        ..lineTo(bc.dx - bs * .05, bc.dy + bs * .12)
        ..lineTo(bc.dx - bs * .2, bc.dy + bs)
        ..lineTo(bc.dx + bs * .55, bc.dy - bs * .2)
        ..lineTo(bc.dx + bs * .05, bc.dy - bs * .2)
        ..close(),
      Paint()..color = const Color(0xFF2F7BFF),
    );
    // cable from the array to the battery
    canvas.drawPath(
      Path()..moveTo(fr.dx, fr.dy + h * .08)..quadraticBezierTo((fr.dx + cabF.left) / 2, cabF.bottom + h * .09, cabF.left, cabF.bottom - h * .02),
      Paint()..color = const Color(0xFF3B4658)..style = PaintingStyle.stroke..strokeWidth = 1.4,
    );
  }

  // ---------------------------------------------------------------- night
  void _night(Canvas canvas, Size size, Offset Function(double, double) P, Offset sun, double height) {
    final w = size.width, h = size.height;
    final full = Offset.zero & size;
    final horizon = h * .58;
    canvas.drawRect(
      full,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF030918), Color(0xFF0A1A40), Color(0xFF16305E)],
          stops: [0, .55, 1],
        ).createShader(Rect.fromLTWH(0, 0, w, horizon + 4)),
    );
    // twinkling stars
    final sp = Paint();
    for (final s in _stars) {
      final tw = .55 + .45 * math.sin((phase * s[4] + s[3]) * math.pi * 2);
      sp.color = Colors.white.withValues(alpha: (.35 + .65 * s[3]) * tw);
      canvas.drawCircle(P(s[0], s[1]), s[2] * .7, sp);
    }
    // constellations
    final cl = Paint()..color = Colors.white.withValues(alpha: .28)..strokeWidth = .8;
    void constel(List<List<double>> pts) {
      for (var i = 0; i < pts.length - 1; i++) {
        canvas.drawLine(P(pts[i][0], pts[i][1]), P(pts[i + 1][0], pts[i + 1][1]), cl);
      }
      for (final q in pts) {
        canvas.drawCircle(P(q[0], q[1]), 1.6, Paint()..color = Colors.white.withValues(alpha: .95));
      }
    }
    constel([[.10, .30], [.17, .24], [.22, .33], [.30, .28], [.27, .40]]);
    constel([[.74, .12], [.82, .20], [.90, .14], [.95, .26], [.86, .32]]);
    // shooting star, loops with the ambient animation
    final ss = (phase * 3) % 1.0;
    if (ss < .16) {
      final k = ss / .16;
      final from = P(.88 - .5 * k, .05 + .22 * k), tail = P(.88 - .5 * k + .07, .05 + .22 * k - .045);
      canvas.drawLine(tail, from, Paint()..strokeWidth = 1.6..strokeCap = StrokeCap.round
        ..shader = LinearGradient(colors: [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: .9 * math.sin(k * math.pi))]).createShader(Rect.fromPoints(tail, from)));
    }
    // crescent moon
    final mc = P(.23, .19), mr = w * .026;
    canvas.drawCircle(mc, mr * 2, Paint()..color = const Color(0xFFDDE8FF).withValues(alpha: .18)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7));
    canvas.saveLayer(Rect.fromCircle(center: mc, radius: mr * 2), Paint());
    canvas.drawCircle(mc, mr, Paint()..color = const Color(0xFFF1F5FF));
    canvas.drawCircle(mc + Offset(mr * .6, -mr * .15), mr * .9, Paint()..blendMode = BlendMode.clear);
    canvas.restore();
    // hills
    Path hill(List<List<double>> pts, double base) {
      final p = Path()..moveTo(P(0, base).dx, P(0, base).dy);
      for (final q in pts) {
        final o = P(q[0], q[1]);
        p.lineTo(o.dx, o.dy);
      }
      p.lineTo(P(1.02, base).dx, P(1.02, base).dy);
      p.close();
      return p;
    }
    canvas.drawPath(hill([[0, .55], [.1, .46], [.22, .50], [.36, .43], [.5, .54], [.64, .49], [.78, .47], [.9, .42], [1, .5]], .7), Paint()..color = const Color(0xFF1B2D63));
    canvas.drawPath(hill([[0, .60], [.2, .55], [.4, .58], [.6, .54], [.8, .57], [1, .53]], .72), Paint()..color = const Color(0xFF12234E));
    // pine silhouettes
    void pine(Offset b, double s) {
      final p = Paint()..color = const Color(0xFF0A1730);
      final path = Path()
        ..moveTo(b.dx, b.dy - s)
        ..lineTo(b.dx - s * .25, b.dy - s * .35)
        ..lineTo(b.dx - s * .12, b.dy - s * .35)
        ..lineTo(b.dx - s * .32, b.dy)
        ..lineTo(b.dx + s * .32, b.dy)
        ..lineTo(b.dx + s * .12, b.dy - s * .35)
        ..lineTo(b.dx + s * .25, b.dy - s * .35)
        ..close();
      canvas.drawPath(path, p);
    }
    for (var i = 0; i < 9; i++) {
      pine(P(.02 + i * .035, .62 + (i % 3) * .008), h * (.16 + (i % 3) * .04));
    }
    for (var i = 0; i < 6; i++) {
      pine(P(.9 + i * .03, .62), h * (.18 + (i % 2) * .05));
    }
    // ground
    final ground = Path()
      ..moveTo(0, horizon + h * .02)
      ..quadraticBezierTo(w * .45, horizon - h * .01, w, horizon + h * .02)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
      ground,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1E3A33), Color(0xFF15291F), Color(0xFF0B1712)],
        ).createShader(Rect.fromLTWH(0, horizon, w, h - horizon)),
    );
    // winding path
    canvas.drawPath(
      Path()
        ..moveTo(P(.0, .78).dx, P(.0, .78).dy)
        ..quadraticBezierTo(P(.14, .66).dx, P(.14, .66).dy, P(.27, .70).dx, P(.27, .70).dy),
      Paint()..color = const Color(0xFF3B4A55).withValues(alpha: .6)..style = PaintingStyle.stroke..strokeWidth = h * .035..strokeCap = StrokeCap.round,
    );
    // large array, same layout as the day scene, with a faint moonlit sheen
    final fl = P(.255, .67), bl = P(.435, .40), br = P(.80, .385), fr = P(.70, .655);
    _legs(canvas, fl, fr, h * .10, const Color(0xFF7D8BA3));
    _array(canvas, fl, bl, br, fr, rows: 3, cols: 5, top: const Color(0xFF2A4694), bottom: const Color(0xFF0F2058), frame: const Color(0xFFB7C8F0));
    canvas.drawPath(
      Path()..moveTo(fl.dx, fl.dy)..lineTo(bl.dx, bl.dy)..lineTo(Offset.lerp(bl, br, .4)!.dx, Offset.lerp(bl, br, .4)!.dy)..lineTo(Offset.lerp(fl, fr, .4)!.dx, Offset.lerp(fl, fr, .4)!.dy)..close(),
      Paint()..color = const Color(0xFFBFD4FF).withValues(alpha: .08),
    );
    // battery cabinet with glowing status lights
    final cab = Rect.fromPoints(P(.79, .75), P(.885, .56));
    canvas.drawCircle(cab.center, w * .06, Paint()..color = const Color(0xFF34D399).withValues(alpha: .10 + .05 * math.sin(phase * math.pi * 2 * 8))..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9));
    final bat = RRect.fromRectAndRadius(cab, Radius.circular(w * .008));
    canvas.drawRRect(bat, Paint()..shader = const LinearGradient(colors: [Color(0xFFE3EAF5), Color(0xFFF8FAFF), Color(0xFFC6D0E2)]).createShader(cab));
    for (var i = 0; i < 4; i++) {
      canvas.drawRect(Rect.fromLTWH(cab.left + cab.width * .18, cab.top + cab.height * (.12 + i * .045), cab.width * .64, cab.height * .028), Paint()..color = const Color(0xFF34D399).withValues(alpha: i == 3 ? .5 + .4 * math.sin(phase * math.pi * 2 * 6) : .95));
    }
    final bc = Offset(cab.center.dx, cab.top + cab.height * .66);
    final bs = cab.height * .17;
    canvas.drawPath(
      Path()
        ..moveTo(bc.dx + bs * .15, bc.dy - bs)
        ..lineTo(bc.dx - bs * .55, bc.dy + bs * .12)
        ..lineTo(bc.dx - bs * .05, bc.dy + bs * .12)
        ..lineTo(bc.dx - bs * .2, bc.dy + bs)
        ..lineTo(bc.dx + bs * .55, bc.dy - bs * .2)
        ..lineTo(bc.dx + bs * .05, bc.dy - bs * .2)
        ..close(),
      Paint()..color = const Color(0xFF2F7BFF),
    );
    canvas.drawPath(
      Path()..moveTo(fr.dx, fr.dy + h * .08)..quadraticBezierTo((fr.dx + cab.left) / 2, cab.bottom + h * .09, cab.left, cab.bottom - h * .02),
      Paint()..color = const Color(0xFF9FB0C8).withValues(alpha: .7)..style = PaintingStyle.stroke..strokeWidth = 1.4,
    );
    // fireflies
    final ff = math.Random(11);
    for (var i = 0; i < 9; i++) {
      final bx = .30 + ff.nextDouble() * .7, by = .66 + ff.nextDouble() * .24;
      final o = P(bx + .02 * math.sin((phase * 4 + i) * math.pi * 2), by + .02 * math.cos((phase * 3 + i) * math.pi * 2));
      final a = .35 + .65 * math.max(0.0, math.sin((phase * 6 + i * .37) * math.pi * 2));
      canvas.drawCircle(o, 2.6, Paint()..color = const Color(0xFFFDE68A).withValues(alpha: .35 * a)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
      canvas.drawCircle(o, 1.1, Paint()..color = const Color(0xFFFEF3C7).withValues(alpha: a));
    }
    // foreground grass blades
    final gb = Paint()..color = const Color(0xFF070F0C)..strokeWidth = 2..strokeCap = StrokeCap.round;
    final rnd = math.Random(3);
    for (var i = 0; i < 40; i++) {
      final left = i < 22;
      final x = left ? w * (.30 + rnd.nextDouble() * .12) : w * (.88 + rnd.nextDouble() * .12);
      final y = h;
      final l = h * (.08 + rnd.nextDouble() * .1);
      canvas.drawLine(Offset(x, y), Offset(x + (rnd.nextDouble() - .5) * 8, y - l), gb);
    }
  }

  // --------------------------------------------------------------- shared
  void _legs(Canvas canvas, Offset fl, Offset fr, double len, Color c) {
    final p = Paint()..color = c..strokeWidth = 2.2..strokeCap = StrokeCap.round;
    for (var i = 0; i < 4; i++) {
      final a = Offset.lerp(fl, fr, .06 + i * .29)!;
      canvas.drawLine(a, a + Offset(0, len), p);
    }
    final brace = Paint()..color = c.withValues(alpha: .8)..strokeWidth = 1.2;
    for (var i = 0; i < 3; i++) {
      final a = Offset.lerp(fl, fr, .06 + i * .29)!, b = Offset.lerp(fl, fr, .06 + (i + 1) * .29)!;
      canvas.drawLine(a + Offset(0, len * .15), b + Offset(0, len * .85), brace);
      canvas.drawLine(b + Offset(0, len * .15), a + Offset(0, len * .85), brace);
    }
  }

  /// Realistic modules: silver frame, dark monocrystalline cells with busbars,
  /// a sky reflection, and thin gaps between modules.
  void _array(Canvas canvas, Offset fl, Offset bl, Offset br, Offset fr,
      {required int rows, required int cols, required Color top, required Color bottom, required Color frame}) {
    Offset bil(double a, double b) => Offset.lerp(Offset.lerp(fl, bl, a)!, Offset.lerp(fr, br, a)!, b)!;
    // mounting rails behind the modules
    final rail = Paint()..color = const Color(0xFF5B6678)..strokeWidth = 2.4..strokeCap = StrokeCap.round;
    for (final b in const [.2, .8]) {
      canvas.drawLine(bil(-.02, b), bil(1.02, b), rail);
    }
    const gap = .012;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final a0 = r / rows + gap, a1 = (r + 1) / rows - gap, b0 = c / cols + gap, b1 = (c + 1) / cols - gap;
        Offset m(double a, double b) => bil(a0 + (a1 - a0) * a, b0 + (b1 - b0) * b);
        Path quad(double inset) => Path()
          ..moveTo(m(inset, inset).dx, m(inset, inset).dy)
          ..lineTo(m(1 - inset, inset).dx, m(1 - inset, inset).dy)
          ..lineTo(m(1 - inset, 1 - inset).dx, m(1 - inset, 1 - inset).dy)
          ..lineTo(m(inset, 1 - inset).dx, m(inset, 1 - inset).dy)
          ..close();
        final outer = quad(0), inner = quad(.07);
        canvas.drawPath(outer, Paint()..color = frame);
        canvas.drawPath(
          inner,
          Paint()..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [top, bottom]).createShader(outer.getBounds()),
        );
        // cells: 6 across, 4 down, with two busbars per cell column
        final cell = Paint()..color = Colors.white.withValues(alpha: .20)..strokeWidth = .55;
        for (var i = 1; i < 6; i++) {
          canvas.drawLine(m(.07, .07 + .86 * i / 6), m(.93, .07 + .86 * i / 6), cell);
        }
        for (var j = 1; j < 4; j++) {
          canvas.drawLine(m(.07 + .86 * j / 4, .07), m(.07 + .86 * j / 4, .93), cell);
        }
        final bus = Paint()..color = const Color(0xFFD9E4F5).withValues(alpha: .38)..strokeWidth = .45;
        for (var i = 0; i < 6; i++) {
          final x = .07 + .86 * (i + .35) / 6, y = .07 + .86 * (i + .65) / 6;
          canvas.drawLine(m(.07, x), m(.93, x), bus);
          canvas.drawLine(m(.07, y), m(.93, y), bus);
        }
        // sky reflection across the glass
        canvas.save();
        canvas.clipPath(inner);
        canvas.drawRect(
          outer.getBounds(),
          Paint()..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.white.withValues(alpha: .26), Colors.white.withValues(alpha: 0)], stops: const [0, .55]).createShader(outer.getBounds()),
        );
        canvas.restore();
        canvas.drawPath(outer, Paint()..color = const Color(0xFF7D8AA0)..style = PaintingStyle.stroke..strokeWidth = .7);
      }
    }
  }

  @override
  bool shouldRepaint(covariant SunScenePainter old) => old.t != t || old.night != night || old.phase != phase;
}
