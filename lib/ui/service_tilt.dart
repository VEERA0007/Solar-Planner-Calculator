import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/service_data.dart';
import '../core/store.dart';
import '../core/sun.dart';
import 'service_page.dart';
import 'theme.dart';

class TiltTab extends StatefulWidget {
  final AppState state;
  const TiltTab({super.key, required this.state});
  @override
  State<TiltTab> createState() => _TiltTabState();
}

class _TiltTabState extends State<TiltTab> {
  int sub = 0;
  AppState get s => widget.state;

  @override
  Widget build(BuildContext context) {
    final lat = s.site.lat, lon = s.site.lon;
    final now = DateTime.now();
    final pos = solarPosition(now, lat, lon);
    final north = lat >= 0;
    final info = dayInfo(now, lat, lon);
    return ListView(padding: const EdgeInsets.fromLTRB(14, 4, 14, 24), children: [
      ServiceTabs(
        items: const [(null, 'Day Curve'), (null, 'Seasonal Tilt'), (null, 'Trackers (1X/2X)')],
        index: sub,
        accents: [C.blue, C.blue, C.blue],
        compact: true,
        onTap: (i) => setState(() => sub = i),
      ),
      const SizedBox(height: 14),
      if (sub == 0) ..._curve(now, pos, info, lat, lon, north),
      if (sub == 1) ..._seasonal(lat, north),
      if (sub == 2) ..._trackers(pos),
    ]);
  }

  // ------------------------------------------------------------- day curve
  List<Widget> _curve(DateTime now, SunPos pos, DayInfo info, double lat, double lon, bool north) {
    final day = DateTime(now.year, now.month, now.day);
    final pts = <double>[
      for (var m = 5 * 60; m <= 19 * 60; m += 15) math.max(0, solarPosition(day.add(Duration(minutes: m)), lat, lon).alt),
    ];
    final nowFrac = ((now.hour * 60 + now.minute) - 5 * 60) / (14 * 60);
    return [
      Panel(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const CapsLabel('Sun Altitude Curve (05:00 - 19:00)'),
                const SizedBox(height: 4),
                Text('Peak Elevation: ${info.maxAlt.toStringAsFixed(1)}° at Solar Noon', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, height: 1.2)),
              ]),
            ),
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: C.chipSun, shape: BoxShape.circle),
              child: Icon(Icons.wb_sunny_outlined, color: C.amber),
            ),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            height: 210,
            width: double.infinity,
            child: CustomPaint(painter: _CurvePainter(pts, nowFrac, pos.alt > 0), child: const SizedBox.expand()),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      Panel(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: IntrinsicHeight(
          child: Row(children: [
            _stat('Current Sun Alt', '${pos.alt.toStringAsFixed(1)}°', C.amber),
            VerticalDivider(color: C.line, width: 1),
            _stat('Sun Azimuth', '${pos.az.toStringAsFixed(1)}°', C.blue),
            VerticalDivider(color: C.line, width: 1),
            _stat('Optimal Azimuth', north ? '180°' : '0°', C.green),
          ]),
        ),
      ),
    ];
  }

  Widget _stat(String label, String value, Color c) => Expanded(
        child: Column(children: [
          FittedBox(fit: BoxFit.scaleDown, child: Text(label.toUpperCase(), maxLines: 1, style: TextStyle(color: C.mute, fontWeight: FontWeight.w800, fontSize: 12.5))),
          const SizedBox(height: 8),
          FittedBox(fit: BoxFit.scaleDown, child: Text(value, maxLines: 1, style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 30))),
        ]),
      );

  // ------------------------------------------------------------- seasonal
  List<Widget> _seasonal(double lat, bool north) {
    final t = seasonalTilts(lat);
    final alt = noonAltitudes(lat);
    return [
      Container(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: [Color(0xFF0A7BE0), Color(0xFF2D63E6), Color(0xFF5038F0)]),
          boxShadow: [BoxShadow(color: const Color(0xFF2D63E6).withValues(alpha: .35), blurRadius: 18, offset: const Offset(0, 8))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('OPTIMAL YEAR-ROUND FIXED TILT', style: TextStyle(color: Color(0xFFCFE0FF), fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: .6)),
          const SizedBox(height: 6),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${t.annual}°', style: const TextStyle(color: Colors.white, fontSize: 58, fontWeight: FontWeight.w800, height: 1.05)),
            const SizedBox(width: 12),
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(north ? 'Facing True South (180°)' : 'Facing True North (0°)', style: const TextStyle(color: Color(0xFFE3EDFF), fontSize: 18, fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 6),
          Text('Calibrated for latitude ${lat.abs().toStringAsFixed(2)}° to maximize annual kilowatt-hour energy generation.',
              style: const TextStyle(color: Color(0xFFE3EDFF), fontSize: 15.5, height: 1.45)),
        ]),
      ),
      const SizedBox(height: 12),
      IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: _season('Summer Tilt', t.summer, north ? 'Flatter angle (May - Jul)' : 'Flatter angle (Nov - Jan)', C.amber)),
        const SizedBox(width: 10),
        Expanded(child: _season('Equinox Tilt', t.equinox, 'Mar & Sep Equinox', C.green)),
        const SizedBox(width: 10),
        Expanded(child: _season('Winter Tilt', t.winter, north ? 'Steeper angle (Nov - Jan)' : 'Steeper angle (May - Jul)', C.blue)),
      ])),
      const SizedBox(height: 12),
      Panel(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const CapsLabel('Annual Solstice Solar Noon Altitudes'),
          const SizedBox(height: 12),
          _bar(north ? 'Summer Solstice (June 21)' : 'Summer Solstice (December 21)', alt.summer, C.amber),
          _bar('Equinox (March / September 21)', alt.equinox, C.green),
          _bar(north ? 'Winter Solstice (December 21)' : 'Winter Solstice (June 21)', alt.winter, C.blue),
        ]),
      ),
    ];
  }

  Widget _season(String label, int deg, String caption, Color c) => Panel(
        padding: const EdgeInsets.fromLTRB(10, 16, 10, 16),
        child: Column(children: [
          FittedBox(fit: BoxFit.scaleDown, child: Text(label.toUpperCase(), maxLines: 1, style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 13.5))),
          const SizedBox(height: 8),
          Text('$deg°', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(caption, textAlign: TextAlign.center, style: TextStyle(color: C.mute, fontSize: 13, height: 1.3)),
        ]),
      );

  Widget _bar(String label, double deg, Color c) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
            Text('${deg.toStringAsFixed(1)}°', style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 16)),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(value: (deg / 90).clamp(0.0, 1.0), minHeight: 11, color: c, backgroundColor: C.chip),
          ),
        ]),
      );

  // -------------------------------------------------------------- trackers
  List<Widget> _trackers(SunPos pos) {
    final up = pos.alt > 0;
    final a = singleAxisAngle(pos.alt, pos.az);
    return [
      Panel(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const CapsLabel('Single-Axis Tracker (Horizontal E-W)', color: null),
                const SizedBox(height: 4),
                Text('Rotates throughout daytime following solar hour', style: TextStyle(color: C.mute, fontSize: 14.5)),
              ]),
            ),
            const SizedBox(width: 8),
            _gain('+22%', C.green),
          ]),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              const Expanded(child: Text('Live Tracker Angle Now:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5))),
              Text(
                up ? '${a >= 0 ? '+' : '-'}${a.abs().round()}° ${a >= 0 ? 'West' : 'East'}' : 'Stowed (flat)',
                style: TextStyle(fontFamilyFallback: kMono, color: C.amber, fontSize: 21, fontWeight: FontWeight.w700),
              ),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      Panel(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const CapsLabel('Dual-Axis Tracker (Altitude + Azimuth)'),
                const SizedBox(height: 4),
                Text('Perpendicular solar beam alignment at all times', style: TextStyle(color: C.mute, fontSize: 14.5)),
              ]),
            ),
            const SizedBox(width: 8),
            _gain('+34%', C.purple),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _target('Target Tilt', up ? '${(90 - pos.alt).round()}°' : '–')),
            const SizedBox(width: 12),
            Expanded(child: _target('Target Azimuth', up ? '${pos.az.round()}°' : '–')),
          ]),
        ]),
      ),
    ];
  }

  Widget _gain(String v, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: c.withValues(alpha: .13), borderRadius: BorderRadius.circular(16)),
        child: Column(children: [
          Text(v, style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 17)),
          Text('Yield', style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 15)),
        ]),
      );

  Widget _target(String label, String v) => Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(16)),
        child: Column(children: [
          FittedBox(fit: BoxFit.scaleDown, child: Text(label.toUpperCase(), maxLines: 1, style: TextStyle(color: C.mute, fontWeight: FontWeight.w800, fontSize: 13.5))),
          const SizedBox(height: 6),
          Text(v, style: TextStyle(fontFamilyFallback: kMono, color: C.purple, fontSize: 25, fontWeight: FontWeight.w700)),
        ]),
      );
}

class _CurvePainter extends CustomPainter {
  final List<double> alt; // every 15 min, 05:00..19:00
  final double nowFrac; // 0..1 across the plotted day
  final bool sunUp;
  _CurvePainter(this.alt, this.nowFrac, this.sunUp);

  @override
  void paint(Canvas canvas, Size size) {
    const bottomPad = 28.0, topPad = 8.0;
    final w = size.width, h = size.height - bottomPad - topPad;
    final peak = math.max(30.0, alt.reduce(math.max));
    final top = (peak / 10).ceil() * 10.0 + 10;
    Offset pt(int i) => Offset(w * i / (alt.length - 1), topPad + h * (1 - alt[i] / top));
    final grid = Paint()..color = C.line..strokeWidth = 1;
    for (final f in const [.25, .6]) {
      canvas.drawLine(Offset(0, topPad + h * f), Offset(w, topPad + h * f), grid);
    }
    canvas.drawLine(Offset(0, topPad + h), Offset(w, topPad + h), Paint()..color = C.line..strokeWidth = 2);
    final line = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (var i = 1; i < alt.length; i++) {
      line.lineTo(pt(i).dx, pt(i).dy);
    }
    final fill = Path.from(line)..lineTo(w, topPad + h)..lineTo(0, topPad + h)..close();
    canvas.drawPath(
      fill,
      Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [C.amber.withValues(alpha: .42), C.amber.withValues(alpha: .02)]).createShader(Rect.fromLTWH(0, topPad, w, h)),
    );
    canvas.drawPath(line, Paint()..color = C.amber..style = PaintingStyle.stroke..strokeWidth = 4.5..strokeJoin = StrokeJoin.round..strokeCap = StrokeCap.round);
    if (nowFrac >= 0 && nowFrac <= 1) {
      final i = nowFrac * (alt.length - 1);
      final i0 = i.floor().clamp(0, alt.length - 1), i1 = math.min(alt.length - 1, i0 + 1);
      final o = Offset.lerp(pt(i0), pt(i1), i - i0)!;
      canvas.drawCircle(o, 22, Paint()..color = C.amber.withValues(alpha: .25));
      canvas.drawCircle(o, 11, Paint()..color = C.amber);
      canvas.drawCircle(o, 11, Paint()..color = C.card..style = PaintingStyle.stroke..strokeWidth = 2.5);
    }
    const labels = [(5, '5 AM'), (9, '9 AM'), (12, '12 PM'), (15, '3 PM'), (19, '7 PM')];
    for (final l in labels) {
      final tp = TextPainter(text: TextSpan(text: l.$2, style: TextStyle(color: C.mute, fontSize: 13, fontFamilyFallback: kMono)), textDirection: TextDirection.ltr)..layout();
      final x = w * (l.$1 - 5) / 14;
      tp.paint(canvas, Offset((x - tp.width / 2).clamp(0.0, w - tp.width), size.height - tp.height));
    }
  }

  @override
  bool shouldRepaint(covariant _CurvePainter old) => old.nowFrac != nowFrac || old.alt != alt;
}
