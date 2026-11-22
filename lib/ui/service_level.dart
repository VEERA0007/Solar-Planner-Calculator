import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'theme.dart';

/// Bubble level for checking the tilt of panels and mounting structures with
/// the phone's accelerometer. Drag the bubble if the device has no sensor.
class LevelTab extends StatefulWidget {
  /// Set in tests: skips the platform sensor channel.
  static bool disableSensor = false;
  const LevelTab({super.key});
  @override
  State<LevelTab> createState() => _LevelTabState();
}

class _LevelTabState extends State<LevelTab> {
  StreamSubscription<AccelerometerEvent>? _sub;
  double _gx = 0, _gy = 0, _gz = 9.81;
  double _offP = 0, _offR = 0; // calibration (zero)
  double _manP = 0, _manR = 0; // drag fallback
  bool _live = false, _locked = false, _muted = false;
  double _frozenP = 0, _frozenR = 0;
  double target = 0;
  DateTime _lastBeep = DateTime(2000);
  Timer? _noSensor;
  bool _showNoSensor = false;

  @override
  void initState() {
    super.initState();
    final hasSensor = !LevelTab.disableSensor && !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
    if (hasSensor) {
      try {
      _sub = accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval).listen(_onEvent, onError: (_) {}, cancelOnError: false);
      } catch (_) {}
    }
    _noSensor = Timer(const Duration(milliseconds: 1800), () {
      if (mounted && !_live) setState(() => _showNoSensor = true);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _noSensor?.cancel();
    super.dispose();
  }

  void _onEvent(AccelerometerEvent e) {
    if (!mounted) return;
    _live = true;
    _gx = _gx * .8 + e.x * .2;
    _gy = _gy * .8 + e.y * .2;
    _gz = _gz * .8 + e.z * .2;
    if (!_locked) setState(() => _showNoSensor = false);
  }

  double get _rawPitch => _live ? math.atan2(_gy, _gz) * 180 / math.pi : _manP;
  double get _rawRoll => _live ? math.atan2(_gx, _gz) * 180 / math.pi : _manR;
  double get pitch => _locked ? _frozenP : _rawPitch - _offP;
  double get roll => _locked ? _frozenR : _rawRoll - _offR;
  double get off => math.sqrt(math.pow(pitch - target, 2) + math.pow(roll, 2));
  bool get onTarget => off < 0.6;

  void _maybeBeep() {
    if (_muted || !onTarget) return;
    final now = DateTime.now();
    if (now.difference(_lastBeep).inMilliseconds > 900) {
      _lastBeep = now;
      HapticFeedback.mediumImpact();
      SystemSound.play(SystemSoundType.click);
    }
  }

  @override
  Widget build(BuildContext context) {
    _maybeBeep();
    final good = onTarget;
    final col = good ? C.green : (off < 3 ? C.amber : C.sky);
    return ListView(padding: const EdgeInsets.fromLTRB(14, 4, 14, 24), children: [
      Panel(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          InkWell(
            onTap: () => setState(() {
              _locked = !_locked;
              _frozenP = _rawPitch - _offP;
              _frozenR = _rawRoll - _offR;
            }),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: _locked ? C.amber.withValues(alpha: .18) : C.card2, borderRadius: BorderRadius.circular(16)),
              child: Icon(_locked ? Icons.lock : Icons.lock_open, color: _locked ? C.amber : C.mute, size: 28),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(good ? 'ON TARGET · LEVEL' : 'TILT OFF TARGET BY ${off.toStringAsFixed(1)}°', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, color: good ? C.green : C.text)),
              const SizedBox(height: 2),
              Text(_locked ? 'Reading locked' : (_live ? 'Real-time tilt sensor' : 'Drag the bubble to simulate'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: C.mute, fontSize: 13.5)),
            ]),
          ),
          InkWell(
            onTap: () => setState(() => _muted = !_muted),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(14)),
              child: Icon(_muted ? Icons.volume_off_outlined : Icons.volume_up_outlined, color: C.mute),
            ),
          ),
          const SizedBox(width: 8),
          Text('${off.toStringAsFixed(1)}°', style: TextStyle(fontFamilyFallback: kMono, fontSize: 28, fontWeight: FontWeight.w700, color: good ? C.green : C.text)),
        ]),
      ),
      const SizedBox(height: 12),
      Panel(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Column(children: [
          LayoutBuilder(builder: (context, box) {
            final d = math.min(box.maxWidth - 24, 380.0);
            return GestureDetector(
              onPanUpdate: _live
                  ? null
                  : (u) => setState(() {
                        _manR = (_manR + u.delta.dx * .15).clamp(-12, 12);
                        _manP = (_manP - u.delta.dy * .15).clamp(-12, 40);
                      }),
              child: SizedBox(width: d, height: d, child: CustomPaint(painter: _VialPainter(roll, pitch - target, off, col, good))),
            );
          }),
          if (_showNoSensor && !_live)
            Padding(padding: const EdgeInsets.only(top: 10), child: Text('No tilt sensor found on this device. Drag the bubble to try it.', textAlign: TextAlign.center, style: TextStyle(color: C.mute, fontSize: 13))),
          const SizedBox(height: 14),
          Divider(color: C.line, height: 1),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _reading('Pitch (Front/Back)', pitch)),
            const SizedBox(width: 12),
            Expanded(child: _reading('Roll (Left/Right)', roll)),
          ]),
        ]),
      ),
      const SizedBox(height: 12),
      Panel(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('SOLAR ANGLE PRESETS', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, letterSpacing: .4))),
            TextButton.icon(
              onPressed: () => setState(() {
                _offP = _rawPitch;
                _offR = _rawRoll;
                _locked = false;
              }),
              icon: Icon(Icons.refresh, color: C.blue, size: 20),
              label: Text('Calibrate / Zero', style: TextStyle(color: C.blue, fontWeight: FontWeight.w800)),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            for (final p in const [(0.0, 'Level'), (15.0, 'Flat'), (18.0, 'Solar'), (25.0, 'Pitch')])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () => setState(() => target = p.$1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
                        color: target == p.$1 ? const Color(0xFF0A84D8) : C.card2,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: target == p.$1 ? Colors.transparent : C.line),
                      ),
                      child: FittedBox(fit: BoxFit.scaleDown, child: Text('${p.$1.toStringAsFixed(1)}° ${p.$2}', maxLines: 1, style: TextStyle(fontWeight: FontWeight.w800, color: target == p.$1 ? Colors.white : C.text))),
                    ),
                  ),
                ),
              ),
          ]),
        ]),
      ),
    ]);
  }

  Widget _reading(String label, double v) => Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(18)),
        child: Column(children: [
          FittedBox(fit: BoxFit.scaleDown, child: Text(label.toUpperCase(), maxLines: 1, style: TextStyle(color: C.mute, fontWeight: FontWeight.w800, fontSize: 13.5))),
          const SizedBox(height: 6),
          Text('${v >= 0 ? '+' : '-'}${v.abs().toStringAsFixed(1)}°', style: TextStyle(fontFamilyFallback: kMono, fontSize: 28, fontWeight: FontWeight.w700, color: C.text)),
        ]),
      );
}

class _VialPainter extends CustomPainter {
  final double roll, pitchErr, off;
  final Color color;
  final bool good;
  _VialPainter(this.roll, this.pitchErr, this.off, this.color, this.good);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(c, r, Paint()..shader = RadialGradient(colors: [C.card2, C.chip]).createShader(Rect.fromCircle(center: c, radius: r)));
    canvas.drawCircle(c, r, Paint()..style = PaintingStyle.stroke..strokeWidth = 10..color = C.line.withValues(alpha: .8));
    final inner = r * .9;
    canvas.drawCircle(c, inner, Paint()..color = C.dark ? const Color(0xFF0B1730) : const Color(0xFFEAF3FE));
    final ring = Paint()..style = PaintingStyle.stroke..strokeWidth = 1.2..color = C.sky.withValues(alpha: .35);
    for (final f in const [.25, .5, .75, 1.0]) {
      canvas.drawCircle(c, inner * f, ring);
    }
    canvas.drawLine(c - Offset(inner, 0), c + Offset(inner, 0), ring);
    canvas.drawLine(c - Offset(0, inner), c + Offset(0, inner), ring);
    // target ring
    canvas.drawCircle(c, inner * .16, Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = good ? C.green : C.mute.withValues(alpha: .6));
    // bubble: 10 degrees reaches the rim
    const maxDeg = 10.0;
    var o = Offset(roll, -pitchErr) / maxDeg * inner;
    if (o.distance > inner * .8) o = o / o.distance * inner * .8;
    final br = inner * .17;
    final b = c + o;
    canvas.drawCircle(b + const Offset(0, 4), br, Paint()..color = Colors.black.withValues(alpha: .18)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
    canvas.drawCircle(b, br, Paint()..shader = RadialGradient(center: const Alignment(-.3, -.4), colors: [Color.lerp(color, Colors.white, .35)!, color]).createShader(Rect.fromCircle(center: b, radius: br)));
    canvas.drawCircle(b + Offset(-br * .35, -br * .4), br * .22, Paint()..color = Colors.white.withValues(alpha: .6));
    final tp = TextPainter(
      text: TextSpan(text: '${off.toStringAsFixed(1)}°', style: TextStyle(color: Colors.black.withValues(alpha: .85), fontWeight: FontWeight.w800, fontSize: br * .6, fontFamilyFallback: kMono)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, b - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _VialPainter o) => o.roll != roll || o.pitchErr != pitchErr || o.color != color;
}
