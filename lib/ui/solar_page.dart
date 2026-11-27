import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/calc.dart';
import '../core/store.dart';
import '../core/sun.dart';
import 'theme.dart';

class SolarPage extends StatefulWidget {
  final AppState state;
  const SolarPage({super.key, required this.state});
  @override
  State<SolarPage> createState() => _SolarPageState();
}

class _SolarPageState extends State<SolarPage> {
  double _hour = DateTime.now().hour + DateTime.now().minute / 60.0;
  double _obstacleHeightM = 1.5; // parapet / water tank height in meters

  AppState get state => widget.state;

  @override
  Widget build(BuildContext context) {
    final site = state.site;
    final hk = state.solarHourlyKw();
    final psh = state.irr?.psh ?? 0.0;
    final mp = state.monthly;
    final pr = state.pr;
    final age = state.profile.commissionDate == null ? 0.0 : DateTime.now().difference(state.profile.commissionDate!).inDays / 365.25;
    final health = (1 - 0.005 * age).clamp(0.5, 1.0).toDouble(); // 0.5%/yr degradation
    final daily = hk.fold(0.0, (a, b) => a + b);
    final peakKw = hk.fold(0.0, (a, b) => a > b ? a : b);
    final year = DateTime.now().year;
    final monthly = List.generate(12, (i) => site.kwp * (mp?.psh[i] ?? kMonthPshHyd[i]) * pr * health * DateTime(year, i + 2, 0).day);
    final annual = monthly.fold(0.0, (a, b) => a + b);
    const months = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];
    final title = TextStyle(color: C.amber, fontSize: 15, fontWeight: FontWeight.w800);

    // Interactive sun path & shadow calculation for selected hour
    final now = DateTime.now();
    final hh = _hour.floor().clamp(0, 23);
    final mm = ((_hour - hh) * 60).round().clamp(0, 59);
    final simTime = DateTime(now.year, now.month, now.day, hh, mm);
    final pos = solarPosition(simTime, site.lat, site.lon);
    final day = dayInfo(simTime, site.lat, site.lon);
    final shadowAz = (pos.az + 180) % 360;
    final shadowLenM = pos.alt > 2.0 ? _obstacleHeightM / math.tan(pos.alt * math.pi / 180) : 0.0;
    final winterNoonAlt = (90 - (site.lat.abs() + 23.44)).clamp(10.0, 89.0);
    final safeSetbackM = _obstacleHeightM / math.tan(winterNoonAlt * math.pi / 180);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        PageHead(state.t('solar'), '${site.city} · ${state.profile.panel.isEmpty ? 'Generation forecast & shadow planner' : state.profile.panel}'),
        StatGrid([
          StatTile('Plant size', '${site.kwp} kWp'),
          StatTile("Today's yield", '${fmt1(daily)} kWh'),
          StatTile('Peak sun hours', psh > 0 ? '${psh.toStringAsFixed(1)} h' : '-'),
          StatTile('Peak output', '${peakKw.toStringAsFixed(2)} kW'),
        ]),
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Today by hour (kW)', style: title),
            const SizedBox(height: 10),
            BarChart(series: [BarSeries('kW', hk, const Color(0xFFF59E0B))], labels: List.generate(24, (i) => i % 3 == 0 ? '$i' : null), highlight: DateTime.now().hour),
          ]),
        ),
        const SizedBox(height: 14),
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.explore_outlined, color: C.orange, size: 20),
              const SizedBox(width: 8),
              const Expanded(child: Text('Sun Compass & Shadow Planner', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800))),
              Text('${hh.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}', style: TextStyle(fontFamilyFallback: kMono, color: C.sky, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 12),
            SizedBox(
              height: 180,
              width: double.infinity,
              child: CustomPaint(
                painter: _SunCompassPainter(sunAz: pos.az, sunAlt: pos.alt, shadowAz: shadowAz, isDark: C.dark),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _miniStat('Sun Azimuth', '${pos.az.round()}° ${compass(pos.az)}', C.orange)),
              const SizedBox(width: 8),
              Expanded(child: _miniStat('Elevation', '${pos.alt.toStringAsFixed(1)}°', C.amber)),
              const SizedBox(width: 8),
              Expanded(child: _miniStat('Shadow', pos.alt > 2 ? '${shadowLenM.toStringAsFixed(1)} m' : 'Night', C.sky)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              const Expanded(child: Text('Time of Day', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
              Text(
                'Rise ${day.rise == null ? '-' : '${day.rise!.hour.toString().padLeft(2, '0')}:${day.rise!.minute.toString().padLeft(2, '0')}'} · '
                'Set ${day.set == null ? '-' : '${day.set!.hour.toString().padLeft(2, '0')}:${day.set!.minute.toString().padLeft(2, '0')}'}',
                style: TextStyle(color: C.mute, fontSize: 11.5),
              ),
            ]),
            Slider(
              value: _hour.clamp(5.0, 19.5),
              min: 5.0,
              max: 19.5,
              divisions: 58,
              activeColor: C.orange,
              onChanged: (v) => setState(() => _hour = v),
            ),
            Row(children: [
              const Expanded(child: Text('Parapet / Obstacle Height', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
              Text('${_obstacleHeightM.toStringAsFixed(1)} m (${(_obstacleHeightM * 3.28084).toStringAsFixed(1)} ft)', style: TextStyle(color: C.sky, fontWeight: FontWeight.w800)),
            ]),
            Slider(
              value: _obstacleHeightM.clamp(0.5, 10.0),
              min: 0.5,
              max: 10.0,
              divisions: 19,
              activeColor: C.sky,
              onChanged: (v) => setState(() => _obstacleHeightM = v),
            ),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: C.chipBlue, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.line)),
              child: Text(
                pos.alt > 2
                    ? 'Shadow falls toward ${compass(shadowAz)} (${shadowAz.round()}°) for ${shadowLenM.toStringAsFixed(2)} m (${(shadowLenM * 3.28084).toStringAsFixed(1)} ft). '
                        'Recommended winter-noon panel clearance: ${safeSetbackM.toStringAsFixed(1)} m.'
                    : 'Sun is near/below the horizon at this time. Recommended winter-noon clearance for ${_obstacleHeightM.toStringAsFixed(1)} m obstacle: ${safeSetbackM.toStringAsFixed(1)} m.',
                style: TextStyle(color: C.text, fontSize: 12.5, height: 1.35),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Typical monthly yield (kWh)', style: title),
            const SizedBox(height: 10),
            BarChart(series: [BarSeries('kWh', monthly, const Color(0xFF38BDF8))], labels: months, highlight: DateTime.now().month - 1),
            const SizedBox(height: 6),
            Text('Long-term average sunshine for ${site.city}${mp != null && mp.fetched ? '' : ' (estimate while offline)'}, performance ratio ${(pr * 100).toStringAsFixed(1)}%${age > 0 ? ', plant age ${age.toStringAsFixed(1)} y' : ''}.', style: TextStyle(color: C.mute, fontSize: 12.5)),
          ]),
        ),
        const SizedBox(height: 14),
        StatGrid([
          StatTile('Annual generation', '${groupIndian(annual)} kWh', hi: true),
          StatTile('Specific yield', '${(annual / (site.kwp < 0.1 ? 0.1 : site.kwp)).round()} kWh/kWp'),
          StatTile('Annual value', '₹${groupIndian(annual * site.tariff)}'),
          StatTile('CO₂ avoided / yr', '${fmt1(annual * kCo2PerKwh / 1000)} t'),
        ]),
      ],
    );
  }

  Widget _miniStat(String l, String v, Color c) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l, style: TextStyle(color: C.mute, fontSize: 11, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          FittedBox(fit: BoxFit.scaleDown, child: Text(v, style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 13.5))),
        ]),
      );
}

class _SunCompassPainter extends CustomPainter {
  final double sunAz, sunAlt, shadowAz;
  final bool isDark;
  _SunCompassPainter({required this.sunAz, required this.sunAlt, required this.shadowAz, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2 - 18;
    final ring = Paint()
      ..color = isDark ? const Color(0xFF233252) : const Color(0xFFD6DFEE)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawCircle(c, r, ring);
    canvas.drawCircle(c, r * .6, ring);
    canvas.drawLine(Offset(c.dx - r, c.dy), Offset(c.dx + r, c.dy), ring);
    canvas.drawLine(Offset(c.dx, c.dy - r), Offset(c.dx, c.dy + r), ring);

    void label(String text, Offset pos) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: TextStyle(color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569), fontSize: 11.5, fontWeight: FontWeight.w800)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
    }

    label('N', Offset(c.dx, c.dy - r - 10));
    label('S', Offset(c.dx, c.dy + r + 10));
    label('E', Offset(c.dx + r + 11, c.dy));
    label('W', Offset(c.dx - r - 11, c.dy));

    Offset polar(double deg, double dist) {
      final rad = (deg - 90) * math.pi / 180;
      return Offset(c.dx + math.cos(rad) * dist, c.dy + math.sin(rad) * dist);
    }

    // Center building/array dot
    canvas.drawCircle(c, 5, Paint()..color = const Color(0xFF0A84FF));

    if (sunAlt > 0) {
      final sunDist = r * (1 - (sunAlt.clamp(0, 90) / 90) * 0.72);
      final sunPt = polar(sunAz, sunDist);
      final shPt = polar(shadowAz, r * (1 - (sunAlt.clamp(5, 90) / 95) * 0.65));

      // Shadow ray
      canvas.drawLine(
        c,
        shPt,
        Paint()
          ..color = const Color(0xFF38BDF8).withValues(alpha: .85)
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round,
      );
      // Sun ray
      canvas.drawLine(
        c,
        sunPt,
        Paint()
          ..color = const Color(0xFFF59E0B).withValues(alpha: .75)
          ..strokeWidth = 2,
      );
      canvas.drawCircle(sunPt, 11, Paint()..color = const Color(0xFFF59E0B).withValues(alpha: .28));
      canvas.drawCircle(sunPt, 6.5, Paint()..color = const Color(0xFFF59E0B));
    }
  }

  @override
  bool shouldRepaint(covariant _SunCompassPainter old) =>
      old.sunAz != sunAz || old.sunAlt != sunAlt || old.shadowAz != shadowAz || old.isDark != isDark;
}
