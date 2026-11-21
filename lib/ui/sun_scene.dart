import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Marker progress 0..1 along the arc: sunrise to sunset; parked at the ends
/// (sun below the horizon) outside daylight.
double arcProgress(DateTime now, DateTime? rise, DateTime? set, {bool night = false}) {
  if (rise == null || set == null) return .5;
  final up = now.isAfter(rise) && now.isBefore(set);
  if (up) return now.difference(rise).inSeconds / math.max(1, set.difference(rise).inSeconds);
  return now.isBefore(rise) ? 0.0 : 1.0;
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
      for (final m in path.computeMetrics()) {
        var d = 0.0;
        while (d < m.length) {
          canvas.drawPath(m.extractPath(d, math.min(d + dash, m.length)), paint);
          d += dash + gap;
        }
      }
    }

    dashed(1.045, night ? .22 : .45, 1.0, 5, 6);
    dashed(1.0, night ? .95 : .95, 2.4, 6, 7);

    // sunset marker (half sun) where the arc meets the ground, right side
    final hs = P(.94, .60);
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(hs.dx - 30, hs.dy - 30, 60, 30));
    final ray = Paint()..color = const Color(0xFFFFB020)..strokeWidth = 1.6..strokeCap = StrokeCap.round;
    for (var i = 0; i < 9; i++) {
      final a = math.pi + i * math.pi / 8;
      canvas.drawLine(hs + Offset(math.cos(a), math.sin(a)) * (w * .028), hs + Offset(math.cos(a), math.sin(a)) * (w * .042), ray);
    }
    canvas.drawCircle(hs, w * .024, Paint()..color = const Color(0xFFFFB020));
    canvas.restore();

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
          colors: [Color(0xFF2B7FF5), Color(0xFF5FA8F6), Color(0xFFA9D3F8), Color(0xFFE3F1FD)],
          stops: [0, .35, .62, 1],
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
    // drifting clouds
    final soft = Paint()..color = Colors.white.withValues(alpha: .55)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    for (var i = 0; i < 4; i++) {
      final x = (((i * .27 + phase * .6) % 1.3) - .15);
      final c = P(x, .16 + (i % 2) * .13);
      canvas.drawOval(Rect.fromCenter(center: c, width: w * .17, height: h * .07), soft);
      canvas.drawOval(Rect.fromCenter(center: c + Offset(w * .04, -h * .02), width: w * .11, height: h * .07), soft);
    }
    // hazy mountains (two layers)
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
      ridge([[0, .52], [.08, .43], [.17, .36], [.26, .45], [.36, .38], [.46, .48], [.58, .40], [.70, .33], [.80, .42], [.90, .36], [1, .46]], .6),
      Paint()..color = const Color(0xFF9DBEE0).withValues(alpha: .75),
    );
    canvas.drawPath(
      ridge([[0, .56], [.12, .49], [.24, .53], [.38, .47], [.52, .55], [.66, .48], [.82, .54], [1, .50]], .62),
      Paint()..color = const Color(0xFF7FA9D6).withValues(alpha: .8),
    );
    // meadow
    final ground = Path()
      ..moveTo(0, horizon)
      ..quadraticBezierTo(w * .4, horizon - h * .02, w * .7, horizon + h * .005)
      ..quadraticBezierTo(w * .9, horizon + h * .015, w, horizon)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
      ground,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF8CC356), Color(0xFF76B84B), Color(0xFFA9D37A)],
          stops: [0, .5, 1],
        ).createShader(Rect.fromLTWH(0, horizon, w, h - horizon)),
    );
    // grass strokes
    final blade = Paint()..color = const Color(0xFF5E9E3E).withValues(alpha: .35)..strokeWidth = 1;
    final rnd = math.Random(5);
    for (var i = 0; i < 70; i++) {
      final x = w * (.3 + rnd.nextDouble() * .72), y = horizon + h * (.08 + rnd.nextDouble() * .4);
      canvas.drawLine(Offset(x, y), Offset(x + 2, y - 5), blade);
    }
    // trees
    void tree(Offset base, double s) {
      canvas.drawRect(Rect.fromLTWH(base.dx - s * .05, base.dy - s * .25, s * .1, s * .25), Paint()..color = const Color(0xFF7A5A3A));
      final g = Paint()..color = const Color(0xFF4E9A45);
      canvas.drawCircle(base + Offset(0, -s * .45), s * .22, g);
      canvas.drawCircle(base + Offset(-s * .15, -s * .34), s * .17, g);
      canvas.drawCircle(base + Offset(s * .15, -s * .34), s * .17, g);
      canvas.drawCircle(base + Offset(0, -s * .52), s * .14, Paint()..color = const Color(0xFF6BB35B));
    }
    tree(P(.14, .57), h * .30);
    tree(P(.07, .54), h * .20);
    tree(P(.96, .56), h * .30);

    // solar array (tilted, steel frame)
    final fl = P(.293, .545), bl = P(.496, .417), br = P(.793, .393), fr = P(.728, .50);
    // shadow on the grass
    canvas.drawPath(
      Path()..moveTo(fl.dx, fl.dy + h * .07)..lineTo(fr.dx, fr.dy + h * .07)..lineTo(fr.dx + w * .05, fr.dy + h * .09)..lineTo(fl.dx + w * .02, fl.dy + h * .09)..close(),
      Paint()..color = const Color(0xFF2E6B2A).withValues(alpha: .35)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    _legs(canvas, fl, fr, h * .13, const Color(0xFF8E98A8));
    _array(canvas, fl, bl, br, fr, rows: 2, cols: 4, top: const Color(0xFF1E57C6), bottom: const Color(0xFF0E2E85), frame: const Color(0xFFEAF1FB));
    // battery cabinet
    final cabF = Rect.fromPoints(P(.744, .60), P(.862, .47));
    final side = Path()
      ..moveTo(cabF.right, cabF.top)
      ..lineTo(cabF.right + w * .014, cabF.top - h * .02)
      ..lineTo(cabF.right + w * .014, cabF.bottom - h * .02)
      ..lineTo(cabF.right, cabF.bottom)
      ..close();
    canvas.drawPath(side, Paint()..color = const Color(0xFFC9D2DE));
    final topFace = Path()
      ..moveTo(cabF.left, cabF.top)
      ..lineTo(cabF.left + w * .014, cabF.top - h * .02)
      ..lineTo(cabF.right + w * .014, cabF.top - h * .02)
      ..lineTo(cabF.right, cabF.top)
      ..close();
    canvas.drawPath(topFace, Paint()..color = const Color(0xFFF1F5FA));
    final body = RRect.fromRectAndRadius(cabF, const Radius.circular(2));
    canvas.drawRRect(body, Paint()..color = const Color(0xFFF8FAFD));
    canvas.drawRRect(body, Paint()..color = const Color(0xFFB4BFCD)..style = PaintingStyle.stroke..strokeWidth = .9);
    final bolt = Path();
    final bc = cabF.center;
    final bs = cabF.height * .22;
    bolt
      ..moveTo(bc.dx + bs * .15, bc.dy - bs)
      ..lineTo(bc.dx - bs * .55, bc.dy + bs * .12)
      ..lineTo(bc.dx - bs * .05, bc.dy + bs * .12)
      ..lineTo(bc.dx - bs * .2, bc.dy + bs)
      ..lineTo(bc.dx + bs * .55, bc.dy - bs * .2)
      ..lineTo(bc.dx + bs * .05, bc.dy - bs * .2)
      ..close();
    canvas.drawPath(bolt, Paint()..color = const Color(0xFF2F7BFF));
    // reflection glint sweeping across the panels
    final g = (phase * 3) % 1.0;
    final gx = fl.dx + (fr.dx - fl.dx) * g;
    canvas.drawLine(Offset(gx, fl.dy), Offset(gx + (bl.dx - fl.dx), bl.dy), Paint()..color = Colors.white.withValues(alpha: .10 * math.sin(g * math.pi))..strokeWidth = w * .03);
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
    // back array
    _legs(canvas, P(.48, .66), P(.84, .64), h * .1, const Color(0xFF6F7C92));
    _array(canvas, P(.46, .66), P(.52, .52), P(.92, .53), P(.84, .67), rows: 2, cols: 4, top: const Color(0xFF1B3274), bottom: const Color(0xFF0E1D4C), frame: const Color(0xFF9FB6E8));
    // front array
    _legs(canvas, P(.22, .80), P(.62, .83), h * .12, const Color(0xFF8795AB));
    _array(canvas, P(.21, .79), P(.33, .62), P(.68, .63), P(.61, .84), rows: 2, cols: 3, top: const Color(0xFF223B85), bottom: const Color(0xFF0F2058), frame: const Color(0xFFB7C8F0));
    // conduits
    final pipe = Paint()..color = const Color(0xFFB9C3D6).withValues(alpha: .8)..style = PaintingStyle.stroke..strokeWidth = 1.4;
    canvas.drawPath(Path()..moveTo(P(.46, .84).dx, P(.46, .84).dy)..quadraticBezierTo(P(.55, .90).dx, P(.55, .90).dy, P(.69, .87).dx, P(.69, .87).dy), pipe);
    // battery unit
    final bat = RRect.fromRectAndRadius(Rect.fromPoints(P(.675, .86), P(.785, .60)), Radius.circular(w * .012));
    canvas.drawRRect(bat, Paint()..shader = const LinearGradient(colors: [Color(0xFFDCE4F2), Color(0xFFF8FAFF), Color(0xFFC6D0E2)]).createShader(bat.outerRect));
    canvas.drawCircle(Offset(bat.center.dx, bat.top + bat.height * .17), w * .007, Paint()..color = const Color(0xFF38BDF8));
    canvas.drawCircle(Offset(bat.center.dx, bat.top + bat.height * .27), w * .005, Paint()..color = const Color(0xFF34D399));
    canvas.drawRect(Rect.fromLTWH(bat.left, bat.bottom - bat.height * .18, bat.width, bat.height * .18), Paint()..color = const Color(0xFF273244));
    // inverter with glow
    final inv = Rect.fromPoints(P(.83, .74), P(.88, .66));
    canvas.drawCircle(inv.center, w * .035, Paint()..color = const Color(0xFF38BDF8).withValues(alpha: .22 + .08 * math.sin(phase * math.pi * 2 * 8))..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7));
    canvas.drawRRect(RRect.fromRectAndRadius(inv, const Radius.circular(2)), Paint()..color = const Color(0xFFE6ECF6));
    canvas.drawRect(Rect.fromLTWH(inv.left + 3, inv.top + 3, inv.width - 6, 2.5), Paint()..color = const Color(0xFF22C55E));
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

  void _array(Canvas canvas, Offset fl, Offset bl, Offset br, Offset fr,
      {required int rows, required int cols, required Color top, required Color bottom, required Color frame}) {
    Offset bil(double a, double b) {
      final l = Offset.lerp(fl, bl, a)!, r = Offset.lerp(fr, br, a)!;
      return Offset.lerp(l, r, b)!;
    }
    final outline = Path()..moveTo(fl.dx, fl.dy)..lineTo(bl.dx, bl.dy)..lineTo(br.dx, br.dy)..lineTo(fr.dx, fr.dy)..close();
    canvas.drawPath(
      outline,
      Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [top, bottom]).createShader(outline.getBounds()),
    );
    // cell lines
    final cell = Paint()..color = Colors.white.withValues(alpha: .13)..strokeWidth = .6;
    for (var c = 0; c <= cols * 5; c++) {
      final b = c / (cols * 5);
      canvas.drawLine(bil(0, b), bil(1, b), cell);
    }
    for (var r = 0; r <= rows * 3; r++) {
      final a = r / (rows * 3);
      canvas.drawLine(bil(a, 0), bil(a, 1), cell);
    }
    // module frames
    final f = Paint()..color = frame.withValues(alpha: .95)..strokeWidth = 1.3..style = PaintingStyle.stroke;
    for (var c = 0; c <= cols; c++) {
      canvas.drawLine(bil(0, c / cols), bil(1, c / cols), f);
    }
    for (var r = 0; r <= rows; r++) {
      canvas.drawLine(bil(r / rows, 0), bil(r / rows, 1), f);
    }
    canvas.drawPath(outline, f..strokeWidth = 1.6);
  }

  @override
  bool shouldRepaint(covariant SunScenePainter old) => old.t != t || old.night != night || old.phase != phase;
}
